-- Private vendor-specific Excel layouts and actual cash/customer receipts.
create table public.jk_vendor_statement_profiles (
 id uuid primary key default gen_random_uuid(),
 vendor text not null check(length(trim(vendor)) between 1 and 200),
 name text not null check(length(trim(name)) between 1 and 80),
 settings jsonb not null check(jsonb_typeof(settings)='object' and length(settings::text)<15000),
 updated_at timestamptz not null default now(),
 unique(vendor,name)
);
alter table public.jk_vendor_statement_profiles enable row level security;
revoke all on public.jk_vendor_statement_profiles from public,anon,authenticated;
grant select,insert,update on public.jk_vendor_statement_profiles to authenticated;
create policy jk_statement_profiles_admin on public.jk_vendor_statement_profiles for all to authenticated
 using((select public.is_admin())) with check((select public.is_admin()));
create function public.jk_save_statement_profile(p_vendor text,p_name text,p_settings jsonb,p_updated_at timestamptz default null) returns uuid
language plpgsql security invoker set search_path=public,pg_temp as $$
declare previous public.jk_vendor_statement_profiles%rowtype;result uuid;
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 if p_vendor is null or p_name is null or jsonb_typeof(p_settings) is distinct from 'object'
  or (p_settings->>'sign') is null or (p_settings->>'sign') not in ('1','-1')
  or (p_settings->>'net_mode') is null or (p_settings->>'net_mode') not in ('net','sales_minus_purchase')
  or coalesce((p_settings->>'header_row')::int,0) not between 1 and 30
  or jsonb_typeof(p_settings->'columns') is distinct from 'object' then raise exception '양식의 제목행·금액 방향·연결 열을 확인하세요.';end if;
 perform pg_advisory_xact_lock(hashtextextended(trim(p_vendor)||':'||trim(p_name),0));
 select * into previous from public.jk_vendor_statement_profiles where vendor=trim(p_vendor) and name=trim(p_name) for update;
 if previous.updated_at is distinct from p_updated_at then raise exception '양식이 다른 화면에서 변경되었습니다. 새로고침하세요.';end if;
 insert into public.jk_vendor_statement_profiles(vendor,name,settings) values(trim(p_vendor),trim(p_name),p_settings)
 on conflict(vendor,name) do update set settings=excluded.settings,updated_at=clock_timestamp() returning id into result;
 return result;
end $$;
revoke all on function public.jk_save_statement_profile(text,text,jsonb,timestamptz) from public,anon;
grant execute on function public.jk_save_statement_profile(text,text,jsonb,timestamptz) to authenticated;

create table public.jk_customer_receipts (
 id uuid primary key default gen_random_uuid(),request_key uuid not null unique,
 kind text not null check(kind='customer'),
 receipt_name text not null check(length(trim(receipt_name)) between 1 and 200),
 amount bigint not null check(amount between 1 and 9007199254740991),
 received_on date not null,
 staff_id uuid not null references public.jk_staff(id),staff_name text not null,
 payment_method text not null check(payment_method in ('현금','계좌')),
 ledger_id uuid references public.jk_sales_ledger(id),
 balance_included boolean not null default false,
 note text not null default '' check(length(note)<=5000),
 voided boolean not null default false,void_note text not null default '',
 created_by uuid default auth.uid(),created_at timestamptz not null default now(),
 check(kind<>'deposit' or (balance_included and payment_method='계좌' and ledger_id is null))
);
create index jk_customer_receipt_date_idx on public.jk_customer_receipts(received_on);
create index jk_customer_receipt_ledger_idx on public.jk_customer_receipts(ledger_id) where not voided;
alter table public.jk_customer_receipts enable row level security;
revoke all on public.jk_customer_receipts from public,anon,authenticated;
grant select,insert,update on public.jk_customer_receipts to authenticated;
create policy jk_customer_receipt_admin on public.jk_customer_receipts for all to authenticated
 using((select public.is_admin())) with check((select public.is_admin()));

create function public.jk_record_customer_receipt(p_request_key uuid,p_kind text,p_name text,p_amount bigint,p_received_on date,p_staff_id uuid,p_method text,p_balance_included boolean,p_ledger_id uuid default null,p_note text default '') returns uuid
language plpgsql security invoker set search_path=public,pg_temp as $$
declare previous public.jk_customer_receipts%rowtype;staff text;l public.jk_sales_ledger%rowtype;paid bigint;result uuid;
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 if p_request_key is null or p_kind is null or p_kind<>'customer' or p_received_on is null
  or p_received_on>(now() at time zone 'Asia/Seoul')::date or p_amount is null or p_amount<=0
  or p_name is null or length(trim(p_name))=0 or p_balance_included is null
  or p_method is null or p_method not in ('현금','계좌') then raise exception '이름·금액·실제 날짜·담당자·수납방식을 확인하세요.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request_key::text,0));
 select * into previous from public.jk_customer_receipts where request_key=p_request_key;
 if found then
  if previous.kind is distinct from p_kind or previous.receipt_name is distinct from trim(p_name) or previous.amount is distinct from p_amount
   or previous.received_on is distinct from p_received_on or previous.staff_id is distinct from p_staff_id
   or previous.payment_method is distinct from p_method or previous.ledger_id is distinct from p_ledger_id
   or previous.balance_included is distinct from p_balance_included or previous.note is distinct from coalesce(p_note,'') then raise exception '이미 사용된 수납 요청입니다.';end if;
  if previous.voided then raise exception '취소한 수납 기록입니다. 새로 기록해 주세요.';end if;
  return previous.id;
 end if;
 select name into staff from public.jk_staff where id=p_staff_id and active;
 if not found then raise exception '활성 담당자를 선택해 주세요.';end if;
 if p_kind='deposit' and (not p_balance_included or p_method<>'계좌' or p_ledger_id is not null) then raise exception '현금 통장 이동은 새 수입이 아닙니다.';end if;
 if p_kind='customer' and p_ledger_id is not null then
  select * into l from public.jk_sales_ledger where id=p_ledger_id for update;
  if not found then raise exception '연결 장부가 없습니다.';end if;
  select coalesce(sum(amount),0) into paid from public.jk_customer_receipts where ledger_id=p_ledger_id and kind='customer' and not voided;
  if paid+p_amount>greatest(coalesce(l.cash_received,0)-coalesce(l.card_received_amount,0),0) then raise exception '장부 S의 현금·계좌 수납액을 초과합니다. 장부 또는 기존 수납 기록을 확인하세요.';end if;
 end if;
 insert into public.jk_customer_receipts(request_key,kind,receipt_name,amount,received_on,staff_id,staff_name,payment_method,ledger_id,balance_included,note)
 values(p_request_key,p_kind,trim(p_name),p_amount,p_received_on,p_staff_id,staff,p_method,p_ledger_id,p_balance_included,coalesce(p_note,'')) returning id into result;
 return result;
end $$;
revoke all on function public.jk_record_customer_receipt(uuid,text,text,bigint,date,uuid,text,boolean,uuid,text) from public,anon;
grant execute on function public.jk_record_customer_receipt(uuid,text,text,bigint,date,uuid,text,boolean,uuid,text) to authenticated;

create function public.jk_void_customer_receipt(p_id uuid,p_note text) returns void
language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 if nullif(trim(p_note),'') is null then raise exception '취소 사유를 입력하세요.';end if;
 update public.jk_customer_receipts set voided=true,void_note=p_note where id=p_id and not voided;
end $$;
revoke all on function public.jk_void_customer_receipt(uuid,text) from public,anon;
grant execute on function public.jk_void_customer_receipt(uuid,text) to authenticated;

create function public.jk_customer_receipt_data(p_month date,p_as_of date) returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare base_date date;base_stamp timestamptz;result jsonb;
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 if p_month is null or p_as_of is null then raise exception '조회 월을 확인하세요.';end if;
 select snapshot_date,updated_at into base_date,base_stamp from public.jk_internal_balances where snapshot_date<=p_as_of order by snapshot_date desc,updated_at desc limit 1;
 select jsonb_build_object(
  'rows',(select coalesce(jsonb_agg(to_jsonb(r) order by received_on desc,created_at desc),'[]') from public.jk_customer_receipts r where received_on>=date_trunc('month',p_month) and received_on<date_trunc('month',p_month)+interval '1 month'),
  'cash_delta',case when base_date is null then 0 else (select coalesce(sum(amount),0) from public.jk_customer_receipts where kind='customer' and not voided and not balance_included and received_on<=p_as_of and (received_on>base_date or (received_on=base_date and created_at>base_stamp))) end,
  'actual_customer_in',(select coalesce(sum(amount),0) from public.jk_customer_receipts where kind='customer' and not voided and received_on<=p_as_of and received_on>=date_trunc('month',p_month) and received_on<date_trunc('month',p_month)+interval '1 month')
 ) into result;
 return result;
end $$;
revoke all on function public.jk_customer_receipt_data(date,date) from public,anon;
grant execute on function public.jk_customer_receipt_data(date,date) to authenticated;

alter table public.jk_internal_used_sales add column buyer_name text not null default '' check(length(buyer_name)<=200),
 add column handler_staff_id uuid references public.jk_staff(id),add column handler_name text not null default '';
alter table public.jk_internal_payments add column receipt_name text not null default '' check(length(receipt_name)<=200),
 add column handler_staff_id uuid references public.jk_staff(id),add column handler_name text not null default '';

create function public.jk_internal_save_used_with_details(p_ledger_id uuid,p_sale_amount bigint,p_receipt_mode text,p_due_date date,p_sold_on date,p_adjust_payroll boolean,p_vendor_payment_id uuid,p_included_amount bigint,p_note text,p_updated_at timestamptz,p_buyer_name text,p_staff_id uuid) returns void
language plpgsql security invoker set search_path=public,pg_temp as $$
declare staff text;
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 if p_sold_on is null or nullif(trim(p_buyer_name),'') is null or length(p_buyer_name)>200 then raise exception '중고 판매일·매입처 이름·담당자를 입력하세요.';end if;
 select name into staff from public.jk_staff where id=p_staff_id and (active or id=(select handler_staff_id from public.jk_internal_used_sales where ledger_id=p_ledger_id));
 if not found then raise exception '담당자를 선택하세요.';end if;
 perform public.jk_internal_save_used(p_ledger_id,p_sale_amount,p_receipt_mode,p_due_date,p_sold_on,p_adjust_payroll,p_vendor_payment_id,p_included_amount,p_note,p_updated_at);
 update public.jk_internal_used_sales set buyer_name=trim(p_buyer_name),handler_staff_id=p_staff_id,handler_name=staff where ledger_id=p_ledger_id;
end $$;
revoke all on function public.jk_internal_save_used_with_details(uuid,bigint,text,date,date,boolean,uuid,bigint,text,timestamptz,text,uuid) from public,anon;
grant execute on function public.jk_internal_save_used_with_details(uuid,bigint,text,date,date,boolean,uuid,bigint,text,timestamptz,text,uuid) to authenticated;

create function public.jk_internal_record_receipt(p_item_key text,p_amount bigint,p_paid_on date,p_request_key uuid,p_payment_method text,p_balance_included boolean,p_note text,p_receipt_name text,p_staff_id uuid) returns uuid
language plpgsql security invoker set search_path=public,pg_temp as $$
declare staff text;result uuid;previous public.jk_internal_payments%rowtype;
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 if nullif(trim(p_receipt_name),'') is null or length(p_receipt_name)>200 then raise exception '입금자 / 매입처 이름을 입력하세요.';end if;
 if p_request_key is null then raise exception '수령 요청을 다시 시작하세요.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request_key::text,0));
 select * into previous from public.jk_internal_payments where request_key=p_request_key;
 if previous.voided then raise exception '취소한 수령 기록입니다. 새로 기록하세요.';end if;
 if found and (previous.receipt_name is distinct from trim(p_receipt_name) or previous.handler_staff_id is distinct from p_staff_id) then raise exception '이미 사용한 수령 요청입니다.';end if;
 select name into staff from public.jk_staff where id=p_staff_id and (active or (previous.id is not null and previous.handler_staff_id=p_staff_id));
 if not found then raise exception '담당자를 선택하세요.';end if;
 if not exists(select 1 from public.jk_internal_items where item_key=p_item_key and category='used' and direction='in') then raise exception '중고 별도 입금 항목을 선택하세요.';end if;
 result:=public.jk_internal_record_payment(p_item_key,p_amount,p_paid_on,p_request_key,p_payment_method,p_balance_included,p_note);
 update public.jk_internal_payments set receipt_name=trim(p_receipt_name),handler_staff_id=p_staff_id,handler_name=staff where id=result;
 return result;
end $$;
revoke all on function public.jk_internal_record_receipt(text,bigint,date,uuid,text,boolean,text,text,uuid) from public,anon;
grant execute on function public.jk_internal_record_receipt(text,bigint,date,uuid,text,boolean,text,text,uuid) to authenticated;
notify pgrst,'reload schema';
