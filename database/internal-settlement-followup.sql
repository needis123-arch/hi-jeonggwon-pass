-- Keep void retries idempotent and include the full invoice period.
create or replace function public.jk_internal_void_payment(p_id uuid,p_note text) returns void language plpgsql security invoker set search_path=public,pg_temp as $$
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
