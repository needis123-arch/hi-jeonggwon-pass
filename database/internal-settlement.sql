-- Internal cash settlement: actual cash, obligations, payments and VAT evidence.
-- Existing W-S net settlement and W * staff rate payroll are retained.
begin;
create table public.jk_internal_balances (
 id uuid primary key default gen_random_uuid(),
 snapshot_date date not null unique,
 total_balance bigint not null check(total_balance>=0),
 minimum_buffer bigint not null default 0 check(minimum_buffer>=0),
 tax_reserve_target bigint not null default 0 check(tax_reserve_target>=0),
 tax_reserve_saved bigint not null default 0 check(tax_reserve_saved>=0 and tax_reserve_saved<=total_balance),
 tax_reserve_configured boolean not null default false,
 note text not null default '' check(length(note)<=5000),
 created_by uuid default auth.uid(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.jk_internal_items (
 item_key text primary key check(length(item_key) between 1 and 200),
 category text not null check(category in ('vendor','payroll','expense','ad','card','manual','tax')),
 title text not null check(length(trim(title)) between 1 and 200),
 source_month date not null check(extract(day from source_month)=1),
 direction text not null check(direction in ('in','out')),
 amount bigint not null check(amount>=0),
 due_date date not null,
 excluded boolean not null default false,
 note text not null default '' check(length(note)<=5000),
 created_by uuid default auth.uid(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index jk_internal_items_due_idx on public.jk_internal_items(due_date);
create table public.jk_internal_payments (
 id uuid primary key default gen_random_uuid(),
 request_key uuid not null unique,
 item_key text not null references public.jk_internal_items(item_key),
 paid_on date not null,
 amount bigint not null check(amount>0),
 payment_method text not null default '계좌' check(payment_method in ('계좌','현금','카드','기타')),
 balance_included boolean not null default false,
 note text not null default '' check(length(note)<=5000),
 voided boolean not null default false,
 void_note text not null default '',
 created_by uuid default auth.uid(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index jk_internal_payments_item_idx on public.jk_internal_payments(item_key);
create index jk_internal_payments_date_idx on public.jk_internal_payments(paid_on);
create table public.jk_internal_tax_invoices (
 id uuid primary key default gen_random_uuid(),
 invoice_date date not null,
 kind text not null check(kind in ('sales','purchase')),
 vendor text not null check(length(trim(vendor)) between 1 and 200),
 supply_amount bigint not null check(supply_amount>=0),
 vat_amount bigint not null check(vat_amount>=0),
 creditable boolean not null default true,
 note text not null default '' check(length(note)<=5000),
 voided boolean not null default false,
 created_by uuid default auth.uid(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index jk_internal_tax_invoices_date_idx on public.jk_internal_tax_invoices(invoice_date);
alter table public.jk_internal_balances enable row level security;
alter table public.jk_internal_items enable row level security;
alter table public.jk_internal_payments enable row level security;
alter table public.jk_internal_tax_invoices enable row level security;
revoke all on public.jk_internal_balances,public.jk_internal_items,public.jk_internal_payments,public.jk_internal_tax_invoices from public,anon,authenticated;
grant select,insert,update on public.jk_internal_balances,public.jk_internal_items,public.jk_internal_payments,public.jk_internal_tax_invoices to authenticated;
create policy jk_internal_admin on public.jk_internal_balances for all to authenticated using((select public.is_admin())) with check((select public.is_admin()));
create policy jk_internal_admin on public.jk_internal_items for all to authenticated using((select public.is_admin())) with check((select public.is_admin()));
create policy jk_internal_admin on public.jk_internal_payments for all to authenticated using((select public.is_admin())) with check((select public.is_admin()));
create policy jk_internal_admin on public.jk_internal_tax_invoices for all to authenticated using((select public.is_admin())) with check((select public.is_admin()));

create function public.jk_internal_stamp() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin new.updated_at:=clock_timestamp();return new;end $$;
create trigger jk_internal_stamp before update on public.jk_internal_balances for each row execute function public.jk_internal_stamp();
create trigger jk_internal_stamp before update on public.jk_internal_items for each row execute function public.jk_internal_stamp();
create trigger jk_internal_stamp before update on public.jk_internal_payments for each row execute function public.jk_internal_stamp();
create trigger jk_internal_stamp before update on public.jk_internal_tax_invoices for each row execute function public.jk_internal_stamp();
create function public.jk_internal_validate_item() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare paid bigint;
begin
 select coalesce(sum(amount),0) into paid from public.jk_internal_payments where item_key=old.item_key and not voided;
 if paid>new.amount or (paid>0 and new.direction<>old.direction) then raise exception '이미 처리한 금액·방향과 맞지 않습니다.';end if;
 return new;
end $$;
create trigger jk_internal_validate_item before update on public.jk_internal_items for each row execute function public.jk_internal_validate_item();

create function public.jk_internal_record_payment(p_item_key text,p_amount bigint,p_paid_on date,p_request_key uuid,p_payment_method text default '계좌',p_balance_included boolean default false,p_note text default '')
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare item public.jk_internal_items%rowtype; previous public.jk_internal_payments%rowtype; paid bigint; result uuid;
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 select * into item from public.jk_internal_items where item_key=p_item_key for update;
 if not found or item.excluded then raise exception '정산 항목을 먼저 확인해 주세요.';end if;
 select * into previous from public.jk_internal_payments where request_key=p_request_key;
 if found then
  if previous.item_key<>p_item_key or previous.amount<>p_amount or previous.paid_on<>p_paid_on then raise exception '이미 사용된 지급 요청입니다.';end if;
  return previous.id;
 end if;
 if p_amount is null or p_amount<=0 or p_paid_on is null or p_paid_on>(now() at time zone 'Asia/Seoul')::date then raise exception '실제 지급일과 금액을 확인해 주세요.';end if;
 select coalesce(sum(amount),0) into paid from public.jk_internal_payments where item_key=p_item_key and not voided;
 if p_amount+paid>item.amount then raise exception '미정산 잔액보다 큰 금액입니다. 확정 금액을 먼저 수정해 주세요.';end if;
 insert into public.jk_internal_payments(request_key,item_key,paid_on,amount,payment_method,balance_included,note)
 values(p_request_key,p_item_key,p_paid_on,p_amount,p_payment_method,p_balance_included,coalesce(p_note,'')) returning id into result;
 if item.category='card' and item.item_key ~ '^card:[0-9a-f-]{36}$' and paid+p_amount=item.amount then
  update public.jk_sales_ledger set card_settled_date=p_paid_on where id=substring(item.item_key from 6)::uuid and card_settled_date is null;
 end if;
 return result;
end $$;

create function public.jk_internal_void_payment(p_id uuid,p_note text) returns void language plpgsql security invoker set search_path=public,pg_temp as $$
declare payment public.jk_internal_payments%rowtype; item public.jk_internal_items%rowtype;
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 if length(trim(coalesce(p_note,'')))=0 then raise exception '취소 사유를 입력하세요.';end if;
 select * into payment from public.jk_internal_payments where id=p_id;
 if not found then raise exception '지급 기록이 없습니다.';end if;
 select * into item from public.jk_internal_items where item_key=payment.item_key for update;
 select * into payment from public.jk_internal_payments where id=p_id;
 if payment.voided then return;end if;
 if item.category='card' and item.item_key ~ '^card:[0-9a-f-]{36}$' then
  update public.jk_sales_ledger set card_settled_date=null where id=substring(item.item_key from 6)::uuid
   and card_settled_date=(select max(paid_on) from public.jk_internal_payments where item_key=item.item_key and not voided);
 end if;
 update public.jk_internal_payments set voided=true,void_note=p_note where id=p_id and not voided;
end $$;

create function public.jk_internal_settlement_data(p_month date,p_as_of date) returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare first_month date; last_month date; result jsonb;
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 if p_month is null or p_as_of is null or p_month<p_as_of-interval '24 months' or p_month>p_as_of+interval '12 months' then raise exception '조회 월을 확인해 주세요.';end if;
 first_month:=(date_trunc('month',least(p_month,p_as_of))-interval '12 months')::date;
 last_month:=(date_trunc('month',greatest(p_month,p_as_of))+interval '2 months')::date;
 with months as(select generate_series(first_month,last_month-interval '1 month',interval '1 month')::date ms),
 vendor as(
  select date_trunc('month',l.activation_date)::date sm,coalesce(nullif(trim(l.vendor),''),'미지정 거래처') vendor,
  sum(l.final_margin)::bigint margin,sum(coalesce(l.cash_received,0))::bigint received,count(*) cnt
  from public.jk_sales_ledger l where l.activation_date>=first_month-interval '1 month' and l.activation_date<last_month group by 1,2
 ),
 generated as(
  select 'vendor:'||v.sm::text||':'||md5(v.vendor) item_key,'vendor' category,v.vendor||' · '||to_char(v.sm,'YYYY-MM')||' 판매분' title,v.sm source_month,
   case when v.margin-v.received>=0 then 'in' else 'out' end direction,abs(v.margin-v.received)::bigint amount,(v.sm+interval '2 months - 1 day')::date due_date,
   jsonb_build_object('margin',v.margin,'received',v.received,'count',v.cnt,'formula','W 최종마진 - S 완납 수납총액') basis
  from vendor v
  union all
  select 'payroll:'||p.sales_month::text||':'||p.staff_id::text,'payroll',p.staff_name||' · '||to_char(p.sales_month,'YYYY-MM')||' 판매급여',p.sales_month,'out',p.payroll_amount,p.payroll_due_date,
   jsonb_build_object('staff_id',p.staff_id,'staff_name',p.staff_name,'margin',p.margin_total,'rate',p.rate_pct,'formula','max(W 최종마진 합계, 0) × 급여율')
  from public.jk_v_staff_payroll_due p where p.payroll_due_date>=first_month and p.payroll_due_date<last_month
  union all
  select 'expense:'||m.ms::text||':'||e.id::text,'expense',e.category||' · '||coalesce(nullif(e.description,''),e.vendor,'비용'),m.ms,'out',e.allocated_amount,
   case when e.recurrence_type='one_time' then e.start_date else make_date(extract(year from m.ms)::int,extract(month from m.ms)::int,least(extract(day from e.start_date)::int,extract(day from m.ms+interval '1 month - 1 day')::int)) end,
   jsonb_build_object('formula','비용원장 월 배분액','source_id',e.id,'payment_method',e.payment_method,'is_fixed',e.is_fixed)
  from months m cross join lateral public.jk_expense_monthly_rows(m.ms) e where trim(coalesce(e.category,''))<>'급여' and e.allocated_amount>0
  union all
  select 'ad:'||m.ms::text||':'||a.id::text,'ad',a.channel||' · '||coalesce(nullif(a.campaign,''),'광고비'),m.ms,'out',a.allocated_amount,
   case when a.billing_type='one_time' then a.start_date else (m.ms+interval '1 month - 1 day')::date end,
   jsonb_build_object('formula','광고비 월 배분 추정액 · 실제 청구액 확인','source_id',a.id,'billing_type',a.billing_type)
  from months m cross join lateral public.jk_ad_monthly_rows(m.ms) a where a.allocated_amount>0
  union all
  select 'card:'||l.id::text,'card',l.customer_name_snapshot||' · 카드 정산',date_trunc('month',l.activation_date)::date,'in',coalesce(l.card_settlement_amount,0),l.card_settlement_due_date,
   jsonb_build_object('formula','수수료 차감 후 카드 정산 예정액','source_id',l.id,'settled_on',l.card_settled_date)
  from public.jk_sales_ledger l where l.card_received_amount>0 and l.card_settlement_due_date is not null and l.card_settlement_due_date<last_month
 ),
 merged as(
  select coalesce(i.item_key,g.item_key) item_key,coalesce(i.category,g.category) category,coalesce(i.title,g.title) title,coalesce(i.source_month,g.source_month) source_month,
   coalesce(i.direction,g.direction) direction,coalesce(i.amount,g.amount) amount,coalesce(i.due_date,g.due_date) due_date,
   coalesce(i.excluded,false) excluded,i.item_key is not null confirmed,coalesce(i.note,'') note,coalesce(g.basis,'{}') basis,i.updated_at
  from generated g full join public.jk_internal_items i using(item_key)
 )
 select jsonb_build_object(
  'snapshot',(select to_jsonb(s) from public.jk_internal_balances s where snapshot_date<=p_as_of order by snapshot_date desc,updated_at desc limit 1),
  'items',(select coalesce(jsonb_agg(to_jsonb(m) order by due_date,title),'[]') from merged m where m.due_date<last_month or m.confirmed),
  'payments',(select coalesce(jsonb_agg(to_jsonb(p) order by p.paid_on desc,p.created_at desc),'[]') from public.jk_internal_payments p),
  'invoices',(select coalesce(jsonb_agg(to_jsonb(t) order by invoice_date desc,created_at desc),'[]') from public.jk_internal_tax_invoices t),
  'ledger_vat',(select coalesce(sum(vat_amount),0) from public.jk_sales_ledger where activation_date>=date_trunc('month',p_month) and activation_date<date_trunc('month',p_month)+interval '1 month'),
  'unclassified_receipts',(select count(*) from public.jk_sales_ledger where cash_received>0 and cash_receipt_method is null),
  'missing_card_dates',(select count(*) from public.jk_sales_ledger where card_received_amount>0 and card_settled_date is null and card_settlement_due_date is null)
 ) into result;
 return result;
end $$;
revoke all on function public.jk_internal_record_payment(text,bigint,date,uuid,text,boolean,text),public.jk_internal_void_payment(uuid,text),public.jk_internal_settlement_data(date,date),public.jk_internal_stamp(),public.jk_internal_validate_item() from public,anon;
grant execute on function public.jk_internal_record_payment(text,bigint,date,uuid,text,boolean,text),public.jk_internal_void_payment(uuid,text),public.jk_internal_settlement_data(date,date) to authenticated;
-- No cash data is inserted. Admins explicitly save combined balances in the UI.
commit;
