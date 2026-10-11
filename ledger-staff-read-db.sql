-- Approved employees can read ledger rows only through this bounded RPC.
-- Existing table write policies, admin membership and document approval remain unchanged.
begin;
create or replace function public.jk_staff_ledger(p_month date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_start date; v_end date; v_year date; v_rows jsonb; v_year_rows jsonb; v_staff jsonb;
begin
 if not jk_document_private.can_read() then raise exception 'Staff approval required' using errcode='42501'; end if;
 if p_month is null or p_month < date '2000-01-01' or p_month >= date '2100-01-01' then raise exception 'Invalid month'; end if;
 v_start:=date_trunc('month',p_month)::date; v_end:=(v_start+interval '1 month')::date;
 v_year:=date_trunc('year',p_month)::date;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.activation_date desc,r.id),'[]'::jsonb) into v_rows from (
  select l.id,l.activation_date,l.vendor,l.customer_name_snapshot,l.customer_phone_snapshot,
   l.model_name,l.activation_type,l.plan_name,l.retail_price,l.base_rebate,l.cash_sale_amount,l.real_rebate,
   l.sim_fee,l.move_fee,l.vat_amount,l.payback_amount,l.penalty_paid,l.cash_received,l.sim_cost,
   l.used_device_amount,l.used_device_model,l.final_margin,l.salesperson_id,l.flag_additional,l.flag_dongpan,
   l.flag_contract_renewal,l.flag_bundle,l.payback_due_date,l.memo,l.payback_note,l.used_return_required,
   l.lead_source,l.deal_type,l.customer_birth_date_snapshot,l.carrier,l.affiliate_card_status,
   l.affiliate_card_company,l.affiliate_card_amount,l.affiliate_card_due_date,l.plan_change_date,
   l.insurance_cancel_date,l.addon_cancel_date,l.plan_change_done,l.insurance_cancel_done,l.addon_cancel_done,
   l.cash_receipt_method,l.card_received_amount,l.card_settlement_amount,l.card_settlement_due_date,l.card_settled_date
  from public.jk_sales_ledger l where l.activation_date>=v_start and l.activation_date<v_end
 )r;
 select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) into v_year_rows from (
  select l.activation_date,l.final_margin,l.deal_type,l.vendor from public.jk_sales_ledger l
  where l.activation_date>=v_year and l.activation_date<(v_year+interval '1 year')::date
 )r;
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'active',s.active) order by s.name),'[]'::jsonb)
 into v_staff from public.jk_staff s;
 return jsonb_build_object('rows',v_rows,'year',v_year_rows,'staff',v_staff);
end $$;
revoke all on function public.jk_staff_ledger(date) from public,anon;
grant execute on function public.jk_staff_ledger(date) to authenticated;
comment on function public.jk_staff_ledger(date) is 'Owner-approved, verified employees: monthly ledger read only; every call checks current approval. No financial writes or Drive credentials.';
commit;
