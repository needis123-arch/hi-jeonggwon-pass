do $$ begin if exists(select 1 from public.jk_internal_used_sales u join public.jk_sales_ledger l on l.id=u.ledger_id where u.adjust_payroll and u.sale_amount<>coalesce(l.used_device_amount,0)) then raise exception 'Existing confirmed prices require reconciliation before retiring override'; end if; end $$;
-- Retire the separate used-sale workflow; retain its historical rows.
CREATE OR REPLACE FUNCTION public.jk_set_margin_values()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
    declare
      v_m bigint;
      v_p bigint;
    begin
      v_m := coalesce(new.base_rebate,0) - coalesce(new.cash_sale_amount,0);
      v_p := round(greatest(v_m,0)::numeric * 0.1)::bigint;

      new.vat_amount := v_p;
      new.final_margin :=
        v_m
        - v_p
        - coalesce(new.payback_amount,0)
        - coalesce(new.penalty_paid,0)
        + coalesce(new.cash_received,0)
        - coalesce(new.sim_cost,0)
        + coalesce(new.used_device_amount,0);

      return new;
    end;
    $function$;

CREATE OR REPLACE FUNCTION public.jk_internal_settlement_data(p_month date, p_as_of date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare first_month date; last_month date; result jsonb;
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 if p_month is null or p_as_of is null or p_month<p_as_of-interval '24 months' or p_month>p_as_of+interval '12 months' then raise exception '조회 월을 확인해 주세요.';end if;
 first_month:=(date_trunc('month',least(p_month,p_as_of))-interval '12 months')::date;
 last_month:=(date_trunc('month',greatest(p_month,p_as_of))+interval '2 months')::date;
 with months as(select generate_series(first_month,last_month-interval '1 month',interval '1 month')::date ms),
 vendor as(
  select date_trunc('month',l.activation_date)::date sm,coalesce(nullif(trim(l.vendor),''),'미지정 거래처') vendor,
  sum(coalesce(l.base_rebate,0)-coalesce(l.cash_sale_amount,0))::bigint gross_signed,sum(l.final_margin)::bigint margin,sum(coalesce(l.cash_received,0))::bigint received,count(*) cnt
  from public.jk_sales_ledger l where l.activation_date>=first_month-interval '1 month' and l.activation_date<last_month group by 1,2
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
   (coalesce(i.category,g.category)='used' or coalesce(i.excluded,false)) excluded,i.item_key is not null confirmed,coalesce(i.note,'') note,coalesce(g.basis,'{}') basis,i.updated_at,coalesce(i.reconciliation_reason,'') reconciliation_reason,i.reconciled_ledger_signed,coalesce(i.payroll_tax_mode,'business33') payroll_tax_mode,coalesce(i.origin_payment_id,(g.basis->>'source_payment_id')::uuid) origin_payment_id
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
  'missing_used_dates',0,
  'missing_card_dates',(select count(*) from public.jk_sales_ledger where card_received_amount>0 and card_settled_date is null and card_settlement_due_date is null)
 ) into result;
 return result;
end $function$;

revoke insert, update on public.jk_internal_used_sales from authenticated;
revoke execute on function public.jk_internal_save_used(uuid,bigint,text,date,date,boolean,uuid,bigint,text,timestamptz) from authenticated;
revoke execute on function public.jk_internal_save_used_with_details(uuid,bigint,text,date,date,boolean,uuid,bigint,text,timestamptz,text,uuid) from authenticated;

