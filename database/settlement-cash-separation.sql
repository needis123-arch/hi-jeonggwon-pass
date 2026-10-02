begin;
alter table public.jk_internal_items drop constraint jk_internal_items_category_check;
alter table public.jk_internal_items add constraint jk_internal_items_category_check check(category in('vendor','payroll','expense','ad','card','manual','tax','payback','used'));
alter table public.jk_payback_payments add column request_key uuid unique,add column payment_method text not null default '계좌',add column balance_included boolean not null default false,add column voided boolean not null default false,add column void_note text not null default '';
create or replace view public.jk_v_payback_status with(security_invoker=true) as  SELECT l.id AS ledger_id,
    l.activation_date,
    l.customer_name_snapshot AS customer_name,
    l.customer_phone_snapshot AS customer_phone,
    s.name AS salesperson,
    l.payback_amount AS promised_amount,
    COALESCE(sum(p.paid_amount), 0::numeric)::bigint AS paid_amount,
    GREATEST(l.payback_amount::numeric - COALESCE(sum(p.paid_amount), 0::numeric), 0::numeric)::bigint AS outstanding_amount,
    COALESCE(l.payback_due_date, (date_trunc('month'::text, l.activation_date::timestamp without time zone) + '1 mon -1 days'::interval)::date) AS due_date,
    a.bank_name,
    a.account_holder,
    a.account_number,
        CASE
            WHEN l.payback_amount <= 0 THEN 'none'::text
            WHEN COALESCE(sum(p.paid_amount), 0::numeric) >= l.payback_amount::numeric THEN 'paid'::text
            WHEN COALESCE(sum(p.paid_amount), 0::numeric) > 0::numeric THEN 'partial'::text
            WHEN COALESCE(l.payback_due_date, (date_trunc('month'::text, l.activation_date::timestamp without time zone) + '1 mon -1 days'::interval)::date) < CURRENT_DATE THEN 'overdue'::text
            ELSE 'pending'::text
        END AS status
   FROM jk_sales_ledger l
     LEFT JOIN jk_payback_payments p ON p.ledger_id = l.id AND NOT p.voided
     LEFT JOIN jk_payback_accounts a ON a.ledger_id = l.id
     LEFT JOIN jk_staff s ON s.id = l.salesperson_id
  WHERE l.payback_amount > 0
  GROUP BY l.id, l.activation_date, l.customer_name_snapshot, l.customer_phone_snapshot, s.name, l.payback_amount, l.payback_due_date, a.bank_name, a.account_holder, a.account_number;
CREATE OR REPLACE FUNCTION public.jk_log_payback_completion()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    declare
      l record;
      v_paid bigint;
    begin
      select id,customer_name_snapshot,payback_due_date,payback_amount into l
      from public.jk_sales_ledger where id=new.ledger_id;

      select coalesce(sum(paid_amount),0) into v_paid
      from public.jk_payback_payments where ledger_id=new.ledger_id and not voided;

      if v_paid >= coalesce(l.payback_amount,0) and coalesce(l.payback_amount,0)>0
         and not exists (
           select 1 from public.jk_alert_action_log
           where ledger_id=new.ledger_id and alert_type='PAYBACK_MONTHEND' and action='completed'
         ) then
        insert into public.jk_alert_action_log(ledger_id,alert_type,customer_name,due_date,action,detail,acted_by)
        values(new.ledger_id,'PAYBACK_MONTHEND',l.customer_name_snapshot,l.payback_due_date,'completed','페이백 지급 완료',coalesce(new.paid_by,auth.uid()));
      end if;
      return new;
    end;
    $function$;

CREATE OR REPLACE FUNCTION public.jk_internal_record_payment(p_item_key text, p_amount bigint, p_paid_on date, p_request_key uuid, p_payment_method text DEFAULT '계좌'::text, p_balance_included boolean DEFAULT false, p_note text DEFAULT ''::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare item public.jk_internal_items%rowtype; previous public.jk_internal_payments%rowtype; paid bigint; result uuid;
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 select * into item from public.jk_internal_items where item_key=p_item_key;
 if item.origin_payment_id is not null then
  perform pg_advisory_xact_lock(hashtextextended(item.origin_payment_id::text,0));
  if not exists(select 1 from public.jk_internal_payments where id=item.origin_payment_id and not voided) then raise exception '취소된 급여의 원천세입니다.';end if;
 end if;
 select * into item from public.jk_internal_items where item_key=p_item_key for update;
 if not found or item.excluded then raise exception '정산 항목을 먼저 확인해 주세요.';end if;
 if item.category='payroll' and item.payroll_tax_mode='business33' then raise exception '새 급여 화면에서 총액·3.3%% 공제를 확인하세요.';end if;
 if item.category='payback' and exists(select 1 from public.jk_payback_payments where request_key=p_request_key) then
  select id into result from public.jk_payback_payments where request_key=p_request_key and ledger_id=substring(p_item_key from 9)::uuid and paid_amount=p_amount and (paid_at at time zone 'Asia/Seoul')::date=p_paid_on;
  if result is null then raise exception '이미 사용한 지급 요청입니다.';end if; return result;
 end if;
 select * into previous from public.jk_internal_payments where request_key=p_request_key;
 if found then
  if previous.item_key<>p_item_key or previous.amount<>p_amount or previous.paid_on<>p_paid_on then raise exception '이미 사용된 지급 요청입니다.';end if;
  return previous.id;
 end if;
 if p_amount is null or p_amount<=0 or p_paid_on is null or p_paid_on>(now() at time zone 'Asia/Seoul')::date then raise exception '실제 지급일과 금액을 확인해 주세요.';end if;
 if item.category='payback' then
  perform 1 from public.jk_sales_ledger where id=substring(p_item_key from 9)::uuid for update;
  if item.direction<>'out' or item.amount<>(select payback_amount from public.jk_sales_ledger where id=substring(p_item_key from 9)::uuid) then raise exception '페이백 약속금액과 장부를 확인하세요.';end if;
  select coalesce(sum(paid_amount),0) into paid from public.jk_payback_payments where ledger_id=substring(p_item_key from 9)::uuid and not voided;
  if p_amount+paid>item.amount then raise exception '페이백 미지급액을 초과합니다.';end if;
  insert into public.jk_payback_payments(ledger_id,paid_amount,paid_at,paid_by,request_key,payment_method,balance_included,note)
   values(substring(p_item_key from 9)::uuid,p_amount,(p_paid_on::text||' 00:00:00 Asia/Seoul')::timestamptz,auth.uid(),p_request_key,p_payment_method,p_balance_included,coalesce(p_note,'')) returning id into result;
  return result;
 end if;
 select coalesce(sum(gross_amount),0) into paid from public.jk_internal_payments where item_key=p_item_key and not voided;
 if p_amount+paid>item.amount then raise exception '미정산 잔액보다 큰 금액입니다. 확정 금액을 먼저 수정해 주세요.';end if;
 insert into public.jk_internal_payments(request_key,item_key,paid_on,amount,payment_method,balance_included,note)
 values(p_request_key,p_item_key,p_paid_on,p_amount,p_payment_method,p_balance_included,coalesce(p_note,'')) returning id into result;
 if item.category='card' and item.item_key ~ '^card:[0-9a-f-]{36}$' and paid+p_amount=item.amount then
  update public.jk_sales_ledger set card_settled_date=p_paid_on where id=substring(item.item_key from 6)::uuid and card_settled_date is null;
 end if;
 return result;
end $function$;

CREATE OR REPLACE FUNCTION public.jk_internal_void_payment(p_id uuid, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare payment public.jk_internal_payments%rowtype; item public.jk_internal_items%rowtype;
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 if exists(select 1 from public.jk_internal_used_sales where vendor_payment_id=p_id and included_amount>0) then raise exception '연결 중고 상계 확인을 먼저 해제하세요.';end if;
 if length(trim(coalesce(p_note,'')))=0 then raise exception '취소 사유를 입력하세요.';end if;
 if not exists(select 1 from public.jk_internal_payments where id=p_id) and exists(select 1 from public.jk_payback_payments where id=p_id) then
  perform 1 from public.jk_sales_ledger where id=(select ledger_id from public.jk_payback_payments where id=p_id) for update;
  update public.jk_payback_payments set voided=true,void_note=p_note where id=p_id and not voided;return;
 end if;
 select * into payment from public.jk_internal_payments where id=p_id;
 if not found then raise exception '지급 기록이 없습니다.';end if;
 select * into item from public.jk_internal_items where item_key=payment.item_key for update;
 select * into payment from public.jk_internal_payments where id=p_id;
 if payment.voided then return;end if;
 perform pg_advisory_xact_lock(hashtextextended(payment.id::text,0));
 if exists(select 1 from public.jk_internal_payments cp join public.jk_internal_items ci using(item_key) where ci.origin_payment_id=payment.id and not cp.voided) then raise exception '관련 원천세 납부 기록을 먼저 취소하세요.';end if;


 if item.category='card' and item.item_key ~ '^card:[0-9a-f-]{36}$' then
  update public.jk_sales_ledger set card_settled_date=null where id=substring(item.item_key from 6)::uuid
   and card_settled_date=(select max(paid_on) from public.jk_internal_payments where item_key=item.item_key and not voided);
 end if;
 update public.jk_internal_payments set voided=true,void_note=p_note where id=p_id and not voided;
 update public.jk_internal_items set excluded=true where origin_payment_id=payment.id;
end $function$;

create function public.jk_validate_payback_payment() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare q bigint;paid bigint;
begin
 if new.voided then return new;end if;
 select payback_amount into q from public.jk_sales_ledger where id=new.ledger_id for update;
 select coalesce(sum(paid_amount),0) into paid from public.jk_payback_payments where ledger_id=new.ledger_id and id<>new.id and not voided;
 if new.paid_amount<=0 or new.paid_amount+paid>coalesce(q,0) then raise exception '고객 페이백 약정액을 초과합니다.';end if;
 if new.paid_at>(now()+interval '1 minute') then raise exception '실제 지급일을 확인하세요.';end if;
 if not exists(select 1 from public.jk_payback_accounts where ledger_id=new.ledger_id and verification_status='verified') then raise exception '고객 계좌를 먼저 확인하세요.';end if;
 return new;
end $$;
revoke all on function public.jk_validate_payback_payment() from public,anon;
create trigger jk_validate_payback_payment before insert or update of paid_amount,ledger_id,paid_at on public.jk_payback_payments for each row execute function public.jk_validate_payback_payment();
CREATE OR REPLACE FUNCTION public.jk_internal_validate_item()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare paid bigint;
begin
 select coalesce(sum(gross_amount),0) into paid from public.jk_internal_payments where item_key=old.item_key and not voided;
 if paid>new.amount or (paid>0 and new.direction<>old.direction) then raise exception '이미 처리한 금액·방향과 맞지 않습니다.';end if;
 if paid>0 and new.category<>old.category then raise exception '지급 이력이 있는 항목의 종류는 변경할 수 없습니다.';end if;
 if old.category='payback' then
  select coalesce(sum(paid_amount),0) into paid from public.jk_payback_payments where ledger_id=substring(old.item_key from 9)::uuid and not voided;
  if new.direction<>'out' or new.amount<(paid) or new.amount<>(select payback_amount from public.jk_sales_ledger where id=substring(old.item_key from 9)::uuid) then raise exception '페이백 금액은 연결 장부 약정액을 따릅니다.';end if;
 end if;
 if old.category='used' and (new.direction<>'in' or new.amount<>(select sale_amount from public.jk_internal_used_sales where ledger_id=substring(old.item_key from 6)::uuid)) then raise exception '중고 판매금액은 중고 판매 관리에서 수정하세요.';end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION public.jk_set_margin_values()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
    declare
      v_m bigint;
      v_p bigint;
      v_used_adjustment bigint;
    begin
      v_m := coalesce(new.base_rebate,0) - coalesce(new.cash_sale_amount,0);
      v_p := round(greatest(v_m,0)::numeric * 0.1)::bigint;
      select case when adjust_payroll then sale_amount-coalesce(new.used_device_amount,0) else 0 end into v_used_adjustment from public.jk_internal_used_sales where ledger_id=new.id;

      new.vat_amount := v_p;
      new.final_margin :=
        v_m
        - v_p
        - coalesce(new.payback_amount,0)
        - coalesce(new.penalty_paid,0)
        + coalesce(new.cash_received,0)
        - coalesce(new.sim_cost,0)
        + coalesce(new.used_device_amount,0)
        + coalesce(v_used_adjustment,0);

      return new;
    end;
    $function$;

create or replace function public.jk_internal_settlement_data(p_month date,p_as_of date) returns jsonb
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
  sum(coalesce(l.base_rebate,0)-coalesce(l.cash_sale_amount,0)+case when u.receipt_mode='vendor' then u.sale_amount else 0 end)::bigint gross_signed,sum(l.final_margin)::bigint margin,sum(coalesce(l.cash_received,0))::bigint received,count(*) cnt
  from public.jk_sales_ledger l left join public.jk_internal_used_sales u on u.ledger_id=l.id where l.activation_date>=first_month-interval '1 month' and l.activation_date<last_month group by 1,2
 ),
 generated as(
  select 'vendor:'||v.sm::text||':'||md5(v.vendor) item_key,'vendor' category,v.vendor||' · '||to_char(v.sm,'YYYY-MM')||' 판매분' title,v.sm source_month,
   case when v.gross_signed>=0 then 'in' else 'out' end direction,abs(v.gross_signed)::bigint amount,(v.sm+interval '2 months - 1 day')::date due_date,
   jsonb_build_object('gross_signed',v.gross_signed,'vat_included',true,'margin',v.margin,'received',v.received,'count',v.cnt,'formula','K(부가세 포함) − L · 고객 페이백/급여/유심/별도 중고입금은 개별 처리') basis
  from vendor v
  union all
  select 'payroll:'||p.sales_month::text||':'||p.staff_id::text,'payroll',p.staff_name||' · '||to_char(p.sales_month,'YYYY-MM')||' 판매급여',p.sales_month,'out',p.payroll_amount,p.payroll_due_date,
   jsonb_build_object('generated_amount',p.payroll_amount,'staff_id',p.staff_id,'staff_name',p.staff_name,'margin',p.margin_total,'rate',p.rate_pct,'formula','max(W 최종마진 합계, 0) × 급여율')
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
  select 'payback:'||l.id::text,'payback',l.customer_name_snapshot||' · 고객 페이백',date_trunc('month',l.activation_date)::date,'out',l.payback_amount,coalesce(l.payback_due_date,(date_trunc('month',l.activation_date)+interval '1 month - 1 day')::date),
   jsonb_build_object('formula','고객에게 보낼 페이백 Q · 거래처 입금과 별도 지출','source_id',l.id,'account_verified',coalesce(a.verification_status,'unchecked')='verified','bank_name',a.bank_name,'account_holder',a.account_holder,'account_number',a.account_number)
  from public.jk_sales_ledger l left join public.jk_payback_accounts a on a.ledger_id=l.id where l.payback_amount>0
  union all
  select 'used:'||l.id::text,'used',l.customer_name_snapshot||' · 중고업체 입금',date_trunc('month',l.activation_date)::date,'in',u.sale_amount,u.due_date,
   jsonb_build_object('formula','중고업체 별도 입금 · 판매 확정금액','source_id',l.id,'expected_amount',l.used_device_amount,'confirmed_sale_amount',u.sale_amount,'difference',u.sale_amount-l.used_device_amount)
  from public.jk_internal_used_sales u join public.jk_sales_ledger l on l.id=u.ledger_id where u.receipt_mode='separate'
  union all
  select 'card:'||l.id::text,'card',l.customer_name_snapshot||' · 카드 정산',date_trunc('month',l.activation_date)::date,'in',coalesce(l.card_settlement_amount,0),l.card_settlement_due_date,
   jsonb_build_object('formula','수수료 차감 후 카드 정산 예정액','source_id',l.id,'settled_on',l.card_settled_date)
  from public.jk_sales_ledger l where l.card_received_amount>0 and l.card_settlement_due_date is not null and l.card_settlement_due_date<last_month
  union all
  select 'withholding:'||p.id::text||':'||t.kind,'tax',i.title||' · '||t.label,date_trunc('month',p.paid_on)::date,'out',t.amount,
   (date_trunc('month',p.paid_on)+interval '1 month 9 days')::date,
   jsonb_build_object('formula','급여에서 이미 공제한 원천세 · 비용에 다시 더하지 않음','withholding',true,'source_payment_id',p.id,'tax_type',t.kind,'payroll_paid_on',p.paid_on)
  from public.jk_internal_payments p join public.jk_internal_items i using(item_key)
  cross join lateral (values('income','사업소득세 3%',p.income_tax),('local','지방소득세 0.3%',p.local_tax)) t(kind,label,amount)
  where not p.voided and i.category='payroll' and t.amount>0
 ),
 merged as(
  select coalesce(i.item_key,g.item_key) item_key,coalesce(i.category,g.category) category,coalesce(i.title,g.title) title,coalesce(i.source_month,g.source_month) source_month,
   coalesce(i.direction,g.direction) direction,coalesce(i.amount,g.amount) amount,coalesce(i.due_date,g.due_date) due_date,
   coalesce(i.excluded,false) excluded,i.item_key is not null confirmed,coalesce(i.note,'') note,coalesce(g.basis,'{}') basis,i.updated_at,coalesce(i.reconciliation_reason,'') reconciliation_reason,i.reconciled_ledger_signed,coalesce(i.payroll_tax_mode,'business33') payroll_tax_mode,coalesce(i.origin_payment_id,(g.basis->>'source_payment_id')::uuid) origin_payment_id
  from generated g full join public.jk_internal_items i using(item_key)
 )
 select jsonb_build_object(
  'snapshot',(select to_jsonb(s) from public.jk_internal_balances s where snapshot_date<=p_as_of order by snapshot_date desc,updated_at desc limit 1),
  'items',(select coalesce(jsonb_agg(to_jsonb(m) order by due_date,title),'[]') from merged m where m.due_date<last_month or m.confirmed),
  'payments',coalesce((select jsonb_agg(to_jsonb(p) order by p.paid_on desc,p.created_at desc) from public.jk_internal_payments p),'[]')||coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'item_key','payback:'||p.ledger_id::text,'amount',p.paid_amount,'gross_amount',p.paid_amount,'income_tax',0,'local_tax',0,'paid_on',(p.paid_at at time zone 'Asia/Seoul')::date,'created_at',p.created_at,'payment_method',p.payment_method,'balance_included',p.balance_included,'note',p.note,'voided',p.voided,'void_note',p.void_note,'native_payback',true)) from public.jk_payback_payments p),'[]'),
  'vendor_checks',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from (select * from public.jk_internal_vendor_checks order by created_at desc limit 25) r),
  'payroll_reports',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from public.jk_internal_payroll_reports r),
  'invoices',(select coalesce(jsonb_agg(to_jsonb(t) order by invoice_date desc,created_at desc),'[]') from public.jk_internal_tax_invoices t),
  'ledger_vat',(select coalesce(sum(vat_amount),0) from public.jk_sales_ledger where activation_date>=date_trunc('month',p_month) and activation_date<date_trunc('month',p_month)+interval '1 month'),
  'unclassified_receipts',(select count(*) from public.jk_sales_ledger where cash_received>0 and cash_receipt_method is null),
  'missing_used_dates',(select count(*) from public.jk_sales_ledger l left join public.jk_internal_used_sales u on u.ledger_id=l.id where l.used_device_amount>0 and u.ledger_id is null),
  'missing_card_dates',(select count(*) from public.jk_sales_ledger where card_received_amount>0 and card_settled_date is null and card_settlement_due_date is null)
 ) into result;
 return result;
end $$;


create or replace view public.jk_v_monthly_settlement_receivables with(security_invoker=true) as  SELECT date_trunc('month'::text, activation_date::timestamp with time zone)::date AS sales_month,
    (date_trunc('month'::text, activation_date::timestamp without time zone) + '2 mons'::interval - '1 day'::interval)::date AS settlement_due_date,
    count(*)::integer AS sales_count,
    sum(coalesce(base_rebate,0)-coalesce(cash_sale_amount,0))::bigint AS expected_settlement_amount,
    sum(final_margin)::bigint AS margin_total,
    sum(COALESCE(cash_received, 0::bigint))::bigint AS cash_received_now
   FROM jk_sales_ledger
  GROUP BY (date_trunc('month'::text, activation_date::timestamp with time zone)::date), ((date_trunc('month'::text, activation_date::timestamp without time zone) + '2 mons'::interval - '1 day'::interval)::date);
CREATE OR REPLACE FUNCTION public.jk_cashflow_status(p_as_of date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    declare
      s public.jk_cash_snapshots%rowtype;
      v_available bigint := 0;
      v_settlement_this_month bigint := 0;
      v_settlement_next_month bigint := 0;
      v_vendor_this bigint := 0;
      v_vendor_next bigint := 0;
      v_card_this bigint := 0;
      v_card_next bigint := 0;
      v_payback bigint := 0;
      v_payroll bigint := 0;
      v_payroll_sales_month date := null;
      v_ad_month bigint := 0;
      v_monthly_expense_total bigint := 0;
      v_scheduled_expenses bigint := 0;
      v_scheduled_fixed bigint := 0;
      v_scheduled_variable bigint := 0;
      v_scheduled_card bigint := 0;
      v_projected bigint := 0;
      v_gap bigint := 0;
      v_month_start date := date_trunc('month',p_as_of)::date;
      v_next_month date := (date_trunc('month',p_as_of)+interval '1 month')::date;
      v_after_next date := (date_trunc('month',p_as_of)+interval '2 months')::date;
      v_month_end date := ((date_trunc('month',p_as_of)+interval '1 month')-interval '1 day')::date;
      v_balance_date date;
    begin
      if not public.is_admin() then raise exception 'not authorized'; end if;

      select *
      into s
      from public.jk_cash_snapshots
      where snapshot_date<=p_as_of
      order by snapshot_date desc,updated_at desc
      limit 1;

      v_balance_date := coalesce(s.snapshot_date,p_as_of);
      v_available := coalesce(s.bank_balance,0)+coalesce(s.cash_on_hand,0)+coalesce(s.other_liquid,0);

      select coalesce(sum(expected_settlement_amount),0)::bigint
      into v_settlement_this_month
      from public.jk_v_monthly_settlement_receivables
      where settlement_due_date>=v_month_start and settlement_due_date<v_next_month;

      select coalesce(sum(expected_settlement_amount),0)::bigint
      into v_settlement_next_month
      from public.jk_v_monthly_settlement_receivables
      where settlement_due_date>=v_next_month and settlement_due_date<v_after_next;

      -- S remains excluded from vendor settlement; add only pending net card receipts.
      v_vendor_this := v_settlement_this_month;
      v_vendor_next := v_settlement_next_month;
      select
        coalesce(sum(card_settlement_amount) filter (where card_settlement_due_date>=v_month_start and card_settlement_due_date<v_next_month),0)::bigint,
        coalesce(sum(card_settlement_amount) filter (where card_settlement_due_date>=v_next_month and card_settlement_due_date<v_after_next),0)::bigint
      into v_card_this,v_card_next
      from public.jk_sales_ledger
      where card_received_amount>0 and card_settled_date is null;
      v_settlement_this_month := v_vendor_this + v_card_this;
      v_settlement_next_month := v_vendor_next + v_card_next;

      select coalesce(sum(outstanding_amount),0)::bigint
      into v_payback
      from public.jk_v_payback_status
      where outstanding_amount>0
        and due_date>=v_month_start
        and due_date<v_next_month;

      select
        coalesce(sum(payroll_amount),0)::bigint,
        min(sales_month)
      into v_payroll,v_payroll_sales_month
      from public.jk_v_staff_payroll_due
      where payroll_due_date>=v_month_start
        and payroll_due_date<v_next_month;

      select coalesce(sum(allocated_amount),0)::bigint
      into v_ad_month
      from public.jk_ad_monthly_rows(v_month_start);

      with expense_due as (
        select
          e.*,
          case
            when e.recurrence_type='one_time' then e.start_date
            else make_date(
              extract(year from v_month_start)::int,
              extract(month from v_month_start)::int,
              least(
                extract(day from e.start_date)::int,
                extract(day from v_month_end)::int
              )
            )
          end as due_date,
          (
            coalesce(e.payment_method,'') in ('사업자카드','개인카드')
            or coalesce(e.description,'') like '%카드%'
            or coalesce(e.description,'') like '%할부%'
          ) as card_like
        from public.jk_expense_monthly_rows(v_month_start) e
      )
      select
        coalesce(sum(allocated_amount),0)::bigint,
        coalesce(sum(allocated_amount) filter (where card_like or due_date>v_balance_date),0)::bigint,
        coalesce(sum(allocated_amount) filter (where (card_like or due_date>v_balance_date) and is_fixed),0)::bigint,
        coalesce(sum(allocated_amount) filter (where (card_like or due_date>v_balance_date) and not is_fixed),0)::bigint,
        coalesce(sum(allocated_amount) filter (where card_like),0)::bigint
      into
        v_monthly_expense_total,
        v_scheduled_expenses,
        v_scheduled_fixed,
        v_scheduled_variable,
        v_scheduled_card
      from expense_due;

      -- 현금/계좌이체: 최신 잔고 기준일 이후 남은 지출만 예약.
      -- 카드/할부: 통장에서 아직 안 빠졌을 가능성이 높아 해당 월 비용을 전액 예약.
      -- 거래처 입금은 부가세 포함 K-L. 고객 페이백은 별도 현금 지출.
      v_projected :=
        v_available
        + v_settlement_this_month
        - v_payback
        - v_payroll
        - v_scheduled_expenses
        - coalesce(s.other_upcoming_outflow,0);

      v_gap := greatest(coalesce(s.minimum_buffer,0)-v_projected,0);

      return jsonb_build_object(
        'snapshot_date',s.snapshot_date,
        'bank_balance',coalesce(s.bank_balance,0),
        'cash_on_hand',coalesce(s.cash_on_hand,0),
        'other_liquid',coalesce(s.other_liquid,0),
        'available_cash',v_available,
        'minimum_buffer',coalesce(s.minimum_buffer,0),
        'other_upcoming_outflow',coalesce(s.other_upcoming_outflow,0),
        'note',s.note,
        'vendor_settlement_due_this_month',v_vendor_this,
        'vendor_settlement_due_next_month',v_vendor_next,
        'card_settlement_due_this_month',v_card_this,
        'card_settlement_due_next_month',v_card_next,
        'settlement_due_this_month',v_settlement_this_month,
        'settlement_due_next_month',v_settlement_next_month,
        'payback_due_this_month',v_payback,
        'payroll_due_this_month',v_payroll,
        'payroll_source_sales_month',v_payroll_sales_month,
        'ad_budget_this_month',v_ad_month,
        'monthly_expense_total',v_monthly_expense_total,
        'scheduled_expense_outflow',v_scheduled_expenses,
        'scheduled_fixed_outflow',v_scheduled_fixed,
        'scheduled_variable_outflow',v_scheduled_variable,
        'scheduled_card_outflow',v_scheduled_card,
        'projected_after_month_end',v_projected,
        'cash_gap_to_buffer',v_gap,
        'month_end_date',v_month_end,
        'next_month_end_date',(v_after_next-1)
      );
    end;
    $function$;

comment on column public.jk_sales_ledger.vat_amount is 'P: operating wage reserve, round(max(K-L,0)*0.1). Actual tax returns use invoice evidence.';
comment on column public.jk_sales_ledger.cash_received is 'S total customer receipts. Vendor gross cash comparison uses K-L; customer payback and used proceeds are separate.';
-- Recalculate derived P/W only; preserve all raw entries and actual payments.
update public.jk_sales_ledger set base_rebate=base_rebate;
CREATE OR REPLACE FUNCTION public.jk_next_month_cash_survival(p_as_of date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    declare
      v_current_month date := date_trunc('month',p_as_of)::date;
      v_next_month date := (date_trunc('month',p_as_of)+interval '1 month')::date;
      v_after_next date := (date_trunc('month',p_as_of)+interval '2 months')::date;

      v_cash jsonb;
      v_current_end_cash bigint := 0;
      v_buffer bigint := 0;
      v_current_margin bigint := 0;
      v_current_target bigint := 0;
      v_next_settlement bigint := 0;
      v_next_payroll bigint := 0;
      v_next_expenses bigint := 0;
      v_next_ads bigint := 0;
      v_next_payback bigint := 0;

      v_avg_rate numeric := 0;
      v_safe_rate numeric := 0;
      v_next_end_no_more_sales bigint := 0;
      v_cash_deficit bigint := 0;
      v_additional_needed bigint := 0;
      v_safe_additional_needed bigint := 0;
      v_required_close bigint := 0;
      v_safe_required_close bigint := 0;
    begin
      if not public.is_admin() then raise exception 'not authorized'; end if;

      v_cash := public.jk_cashflow_status(p_as_of);
      v_current_end_cash := coalesce((v_cash->>'projected_after_month_end')::bigint,0);
      v_buffer := coalesce((v_cash->>'minimum_buffer')::bigint,0);

      select coalesce(sum(final_margin),0)::bigint
      into v_current_margin
      from public.jk_sales_ledger
      where activation_date>=v_current_month
        and activation_date<v_next_month;

      select coalesce(target_margin,0)
      into v_current_target
      from public.jk_targets
      where target_month=v_current_month
      limit 1;

      v_next_settlement := coalesce((v_cash->>'settlement_due_next_month')::bigint,0);

      select coalesce(sum(payroll_amount),0)::bigint
      into v_next_payroll
      from public.jk_v_staff_payroll_due
      where payroll_due_date>=v_next_month
        and payroll_due_date<v_after_next;

      select coalesce(sum(allocated_amount),0)::bigint
      into v_next_expenses
      from public.jk_expense_monthly_rows(v_next_month)
      where trim(coalesce(category,'')) <> '급여';

      select coalesce(sum(allocated_amount),0)::bigint
      into v_next_ads
      from public.jk_ad_monthly_rows(v_next_month);

      with rates as (
        select coalesce((
          select pr.rate_pct
          from public.jk_staff_pay_rates pr
          where pr.staff_id=s.id
            and pr.effective_month<=v_current_month
          order by pr.effective_month desc
          limit 1
        ),0)::numeric as rate_pct
        from public.jk_staff s
        where s.active
      )
      select
        least(95,greatest(0,coalesce(avg(rate_pct),0))),
        least(95,greatest(0,coalesce(max(rate_pct),0)))
      into v_avg_rate,v_safe_rate
      from rates;

      select coalesce(sum(outstanding_amount),0)::bigint into v_next_payback from public.jk_v_payback_status where due_date>=v_next_month and due_date<v_after_next;
      v_next_end_no_more_sales :=
        v_current_end_cash
        + v_next_settlement
        - v_next_payback
        - v_next_payroll
        - v_next_expenses
        - v_next_ads;

      v_cash_deficit := greatest(v_buffer-v_next_end_no_more_sales,0);

      if v_cash_deficit>0 then
        v_additional_needed := ceil(
          v_cash_deficit::numeric / nullif(1-(v_avg_rate/100),0)
        )::bigint;
        v_safe_additional_needed := ceil(
          v_cash_deficit::numeric / nullif(1-(v_safe_rate/100),0)
        )::bigint;
      end if;

      v_required_close := v_current_margin + v_additional_needed;
      v_safe_required_close := v_current_margin + v_safe_additional_needed;

      return jsonb_build_object(
        'sales_month',v_current_month,
        'survival_month',v_next_month,
        'current_booked_margin',v_current_margin,
        'current_target_margin',v_current_target,
        'current_month_end_cash',v_current_end_cash,
        'minimum_buffer',v_buffer,
        'next_month_existing_settlement',v_next_settlement,
        'next_month_existing_payroll',v_next_payroll,
        'next_month_expenses',v_next_expenses,
        'next_month_ads',v_next_ads,
        'next_month_payback',v_next_payback,
        'next_month_end_without_more_sales',v_next_end_no_more_sales,
        'cash_deficit_without_more_sales',v_cash_deficit,
        'weighted_payroll_rate',round(v_avg_rate,2),
        'safe_payroll_rate',round(v_safe_rate,2),
        'rate_basis','active_staff_average',
        'additional_margin_needed',v_additional_needed,
        'safe_additional_margin_needed',v_safe_additional_needed,
        'required_month_close_margin',v_required_close,
        'safe_required_month_close_margin',v_safe_required_close,
        'target_gap',greatest(v_current_target-v_current_margin,0),
        'target_headroom_over_required',v_current_target-v_required_close,
        'target_headroom_over_safe',v_current_target-v_safe_required_close
      );
    end;
    $function$;
commit;

