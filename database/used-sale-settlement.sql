begin;
create table public.jk_internal_used_sales(
 ledger_id uuid primary key references public.jk_sales_ledger(id),
 sale_amount bigint not null check(sale_amount>=0),
 receipt_mode text not null check(receipt_mode in('separate','vendor')),
 due_date date not null,sold_on date,
 adjust_payroll boolean not null default true,
 vendor_payment_id uuid references public.jk_internal_payments(id),
 included_amount bigint not null default 0 check(included_amount>=0 and included_amount<=sale_amount),
 note text not null default '' check(length(note)<=5000),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check((receipt_mode='vendor' or included_amount=0) and (included_amount=0 or vendor_payment_id is not null))
);
alter table public.jk_internal_used_sales enable row level security;
revoke all on public.jk_internal_used_sales from public,anon,authenticated;
grant select,insert,update on public.jk_internal_used_sales to authenticated;
create policy jk_internal_admin on public.jk_internal_used_sales for all to authenticated using((select public.is_admin())) with check((select public.is_admin()));
create trigger jk_internal_stamp before update on public.jk_internal_used_sales for each row execute function public.jk_internal_stamp();

create function public.jk_internal_used_data(p_month date) returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare result jsonb;
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by activation_date desc),'[]') into result from(
 select l.id ledger_id,l.customer_name_snapshot customer_name,l.customer_phone_snapshot customer_phone,l.activation_date,l.vendor,l.used_device_model model,l.used_device_amount expected_amount,
 u.sale_amount,u.receipt_mode,u.due_date,u.sold_on,u.adjust_payroll,u.included_amount,u.vendor_payment_id,u.note,u.updated_at,
 case when u.receipt_mode='vendor' then u.included_amount else coalesce((select sum(p.amount) from public.jk_internal_payments p where p.item_key='used:'||l.id::text and not p.voided),0) end paid_amount,
 (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'paid_on',p.paid_on,'amount',p.amount,'direction',i.direction) order by p.paid_on desc),'[]') from public.jk_internal_payments p join public.jk_internal_items i using(item_key) where not p.voided and i.item_key='vendor:'||date_trunc('month',l.activation_date)::date::text||':'||md5(coalesce(nullif(trim(l.vendor),''),'미지정 거래처'))) vendor_payments
 from public.jk_sales_ledger l left join public.jk_internal_used_sales u on u.ledger_id=l.id
 where l.activation_date>=date_trunc('month',p_month) and l.activation_date<date_trunc('month',p_month)+interval '1 month' and (l.used_device_amount>0 or nullif(l.used_device_model,'') is not null or u.ledger_id is not null)
 ) r;return result;
end $$;

create function public.jk_internal_save_used(p_ledger_id uuid,p_sale_amount bigint,p_receipt_mode text,p_due_date date,p_sold_on date,p_adjust_payroll boolean,p_vendor_payment_id uuid,p_included_amount bigint,p_note text,p_updated_at timestamptz) returns void
language plpgsql security invoker set search_path=public,pg_temp as $$
declare l public.jk_sales_ledger%rowtype;u public.jk_internal_used_sales%rowtype;paid bigint;vendor_key text;
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 select * into l from public.jk_sales_ledger where id=p_ledger_id for update;
 if not found then raise exception '연결 장부가 없습니다.';end if;
 select * into u from public.jk_internal_used_sales where ledger_id=p_ledger_id for update;
 if u.updated_at is distinct from p_updated_at then raise exception '다른 화면에서 수정되었습니다. 새로고침하세요.';end if;
 if p_sale_amount is null or p_sale_amount<0 or p_receipt_mode not in('separate','vendor') or p_due_date is null or p_adjust_payroll is null or p_included_amount is null or p_included_amount<0 or p_included_amount>p_sale_amount or p_sold_on>(now() at time zone 'Asia/Seoul')::date then raise exception '판매금액·날짜·수령방식을 확인하세요.';end if;
 if p_sale_amount<>coalesce(l.used_device_amount,0) and nullif(trim(p_note),'') is null then raise exception '중고 판매금액 차액 사유를 입력하세요.';end if;
 select coalesce(sum(amount),0) into paid from public.jk_internal_payments where item_key='used:'||p_ledger_id::text and not voided;
 if p_sale_amount<paid or (paid>0 and p_receipt_mode<>'separate') then raise exception '이미 별도로 받은 중고금액을 확인하세요.';end if;
 vendor_key:='vendor:'||date_trunc('month',l.activation_date)::date::text||':'||md5(coalesce(nullif(trim(l.vendor),''),'미지정 거래처'));
 if p_receipt_mode='vendor' and p_included_amount>0 then
  perform pg_advisory_xact_lock(hashtextextended(p_vendor_payment_id::text,0));
  if not exists(select 1 from public.jk_internal_payments where id=p_vendor_payment_id and item_key=vendor_key and not voided) then raise exception '이 판매월 거래처의 실제 정산 처리 기록을 선택하세요.';end if;
 elsif p_included_amount<>0 then raise exception '별도 입금은 실제 수령 기록에서 입력하세요.';end if;
 insert into public.jk_internal_used_sales(ledger_id,sale_amount,receipt_mode,due_date,sold_on,adjust_payroll,vendor_payment_id,included_amount,note)
 values(p_ledger_id,p_sale_amount,p_receipt_mode,p_due_date,p_sold_on,p_adjust_payroll,case when p_receipt_mode='vendor' then p_vendor_payment_id end,p_included_amount,coalesce(p_note,''))
 on conflict(ledger_id) do update set sale_amount=excluded.sale_amount,receipt_mode=excluded.receipt_mode,due_date=excluded.due_date,sold_on=excluded.sold_on,adjust_payroll=excluded.adjust_payroll,vendor_payment_id=excluded.vendor_payment_id,included_amount=excluded.included_amount,note=excluded.note;
 if p_receipt_mode='separate' then
  insert into public.jk_internal_items(item_key,category,title,source_month,direction,amount,due_date,note)
  values('used:'||p_ledger_id::text,'used',l.customer_name_snapshot||' · 중고업체 입금',date_trunc('month',l.activation_date)::date,'in',p_sale_amount,p_due_date,coalesce(p_note,''))
  on conflict(item_key) do update set amount=excluded.amount,due_date=excluded.due_date,note=excluded.note,excluded=false;
 else update public.jk_internal_items set excluded=true where item_key='used:'||p_ledger_id::text;end if;
 -- Preserve original U estimate; trigger recalculates only derived profit using confirmed sale difference.
 update public.jk_sales_ledger set base_rebate=base_rebate where id=p_ledger_id;
end $$;
revoke all on function public.jk_internal_used_data(date),public.jk_internal_save_used(uuid,bigint,text,date,date,boolean,uuid,bigint,text,timestamptz) from public,anon;
grant execute on function public.jk_internal_used_data(date),public.jk_internal_save_used(uuid,bigint,text,date,date,boolean,uuid,bigint,text,timestamptz) to authenticated;
commit;
