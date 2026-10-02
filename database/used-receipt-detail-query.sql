CREATE OR REPLACE FUNCTION public.jk_internal_used_data(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare result jsonb;
begin
 if not public.is_admin() then raise exception 'not authorized';end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by activation_date desc),'[]') into result from(
 select l.id ledger_id,l.customer_name_snapshot customer_name,l.customer_phone_snapshot customer_phone,l.activation_date,l.vendor,l.used_device_model model,l.used_device_amount expected_amount,
 l.salesperson_id,u.buyer_name,u.handler_staff_id,u.handler_name,u.sale_amount,u.receipt_mode,u.due_date,u.sold_on,u.adjust_payroll,u.included_amount,u.vendor_payment_id,u.note,u.updated_at,
 (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'paid_on',p.paid_on,'amount',p.amount,'receipt_name',p.receipt_name,'handler_name',p.handler_name,'voided',p.voided) order by p.paid_on desc,p.created_at desc),'[]') from public.jk_internal_payments p where p.item_key='used:'||l.id::text) receipts,
 case when u.receipt_mode='vendor' then u.included_amount else coalesce((select sum(p.amount) from public.jk_internal_payments p where p.item_key='used:'||l.id::text and not p.voided),0) end paid_amount,
 (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'paid_on',p.paid_on,'amount',p.amount,'direction',i.direction) order by p.paid_on desc),'[]') from public.jk_internal_payments p join public.jk_internal_items i using(item_key) where not p.voided and i.item_key='vendor:'||date_trunc('month',l.activation_date)::date::text||':'||md5(coalesce(nullif(trim(l.vendor),''),'미지정 거래처'))) vendor_payments
 from public.jk_sales_ledger l left join public.jk_internal_used_sales u on u.ledger_id=l.id
 where l.activation_date>=date_trunc('month',p_month) and l.activation_date<date_trunc('month',p_month)+interval '1 month' and (l.used_device_amount>0 or nullif(l.used_device_model,'') is not null or u.ledger_id is not null)
 ) r;return result;
end $function$
;
