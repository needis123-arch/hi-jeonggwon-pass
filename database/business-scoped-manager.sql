-- Business-only manager scope; the global admin_users / is_admin contract is unchanged.
create table jk_document_private.business_managers(
 user_id uuid primary key references auth.users(id) on delete cascade,
 email text not null,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
alter table jk_document_private.business_managers enable row level security;
revoke all on jk_document_private.business_managers from public,anon,authenticated;
create function jk_document_private.is_business_manager() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
  select 1 from jk_document_private.business_managers m join jk_document_private.access_requests r on r.user_id=m.user_id
  where m.user_id=auth.uid() and m.active and lower(m.email)=jk_document_private.verified_email()
   and lower(r.email)=jk_document_private.verified_email() and r.status='approved'
 );
$$;
revoke all on function jk_document_private.is_business_manager() from public,anon,authenticated;
create function public.jk_business_can_manage() returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce(public.is_admin(),false) or jk_document_private.is_business_manager();
$$;
-- Parameterless authorization predicate: anonymous callers can only get false.
revoke all on function public.jk_business_can_manage() from public;
grant execute on function public.jk_business_can_manage() to anon,authenticated,service_role;
create or replace function jk_document_private.is_owner() returns boolean
language sql stable security definer set search_path='' as $$
 select (auth.uid() is not null and coalesce(public.is_admin(),false)
  and coalesce(jk_document_private.verified_email()='needis123@gmail.com',false))
  or jk_document_private.is_business_manager();
$$;
CREATE OR REPLACE FUNCTION public.jk_document_access_state()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_email text:=jk_document_private.verified_email(); v_row jk_document_private.access_requests;
begin
 if auth.uid() is null or v_email is null then raise exception 'Verified login required' using errcode='42501'; end if;
 select * into v_row from jk_document_private.access_requests where user_id=auth.uid() and email=v_email;
 return jsonb_build_object('owner',jk_document_private.is_owner(),'storage_owner',(coalesce(public.is_admin(),false) and coalesce(jk_document_private.verified_email()='needis123@gmail.com',false)),'status',coalesce(v_row.status,'none'),
 'email',v_email,'display_name',v_row.display_name,'version',v_row.version,
 'drive_connected',exists(select 1 from jk_document_private.drive_connection where refresh_secret_id is not null));
end $function$;
alter policy "jk_consultation_history_insert" on public."jk_consultation_history" with check ((( SELECT public.jk_business_can_manage() AS is_admin) AND (created_by = ( SELECT auth.uid() AS uid))));
alter policy "jk_consultation_history_select" on public."jk_consultation_history" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_targets" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_targets" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_targets" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_targets" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_monthly_close" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_monthly_close" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_monthly_close" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_monthly_close" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_backup_runs" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_backup_runs" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_backup_runs" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_backup_runs" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_staff" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_staff" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_staff" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_staff" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_customers" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_customers" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_customers" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_customers" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_sales_ledger" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_sales_ledger" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_sales_ledger" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_sales_ledger" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_payback_accounts" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_payback_accounts" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_payback_accounts" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_payback_accounts" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_payback_payments" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_payback_payments" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_payback_payments" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_payback_payments" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_expenses" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_expenses" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_expenses" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_expenses" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_ad_spend" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_ad_spend" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_ad_spend" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_ad_spend" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_used_device_returns" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_used_device_returns" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_used_device_returns" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_used_device_returns" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_lookup_options" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_lookup_options" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_lookup_options" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_lookup_options" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_year_targets" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_year_targets" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_year_targets" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_year_targets" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "admins manage quote drafts" on public."jk_quote_drafts" using (public.jk_business_can_manage()) with check (public.jk_business_can_manage());
alter policy "jk_admin_delete" on public."jk_affiliate_card_registrations" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_affiliate_card_registrations" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_affiliate_card_registrations" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_affiliate_card_registrations" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_alert_action_log" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_alert_action_log" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_alert_action_log" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_alert_action_log" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_notification_templates" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_notification_templates" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_notification_templates" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_notification_templates" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_notification_queue" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_notification_queue" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_notification_queue" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_notification_queue" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_external_notification_log" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_external_notification_log" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_external_notification_log" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_external_notification_log" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_cash_snapshots" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_cash_snapshots" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_cash_snapshots" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_cash_snapshots" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_delete" on public."jk_staff_pay_rates" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_insert" on public."jk_staff_pay_rates" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_select" on public."jk_staff_pay_rates" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_admin_update" on public."jk_staff_pay_rates" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_daily_lead_activity_delete" on public."jk_daily_lead_activity" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_daily_lead_activity_insert" on public."jk_daily_lead_activity" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_daily_lead_activity_select" on public."jk_daily_lead_activity" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_daily_lead_activity_update" on public."jk_daily_lead_activity" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_internal_admin" on public."jk_internal_tax_invoices" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_internal_admin" on public."jk_internal_balances" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_internal_admin" on public."jk_internal_items" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_internal_admin" on public."jk_internal_payroll_reports" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_internal_admin" on public."jk_internal_vendor_checks" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_consult_staff_admin_write" on public."jk_consultation_staff_directory" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_consult_staff_public_names" on public."jk_consultation_staff_directory" using ((active OR ( SELECT public.jk_business_can_manage() AS is_admin)));
alter policy "jk_consultation_admin_delete" on public."jk_consultations" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_consultation_admin_insert" on public."jk_consultations" with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_consultation_admin_select" on public."jk_consultations" using (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_consultation_admin_update" on public."jk_consultations" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_statement_profiles_admin" on public."jk_vendor_statement_profiles" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_customer_receipt_admin" on public."jk_customer_receipts" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_internal_admin" on public."jk_internal_used_sales" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
alter policy "jk_internal_admin" on public."jk_internal_payments" using (( SELECT public.jk_business_can_manage() AS is_admin)) with check (( SELECT public.jk_business_can_manage() AS is_admin));
CREATE OR REPLACE FUNCTION public.jk_ad_monthly_rows(p_month date)
 RETURNS TABLE(id uuid, start_date date, end_date date, channel text, campaign text, billing_type text, preset_type text, configured_amount bigint, duration_months integer, allocated_amount bigint, inquiries integer, visits integer, activations integer, attributed_margin bigint, note text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
      with params as (
        select
          date_trunc('month',p_month::timestamp)::date as ms,
          (date_trunc('month',p_month::timestamp)+interval '1 month - 1 day')::date as me
      ),
      base as (
        select
          a.*,
          p.ms,p.me,
          greatest(a.start_date,p.ms) as overlap_start,
          least(coalesce(a.end_date,p.me),p.me) as overlap_end,
          greatest(((least(coalesce(a.end_date,p.me),p.me) - greatest(a.start_date,p.ms)) + 1),0)::int as overlap_days,
          case
            when a.duration_months is not null then a.duration_months*30
            when a.end_date is not null then ((a.end_date-a.start_date)+1)
            else null
          end::int as total_days
        from public.jk_ad_spend a
        cross join params p
        where public.jk_business_can_manage()
          and a.start_date<=p.me
          and (a.end_date is null or a.end_date>=p.ms)
      )
      select
        b.id,b.start_date,b.end_date,b.channel,b.campaign,b.billing_type,b.preset_type,
        b.amount as configured_amount,b.duration_months,
        case
          when b.billing_type='one_time' then
            case when b.start_date between b.ms and b.me then b.amount else 0 end
          when b.billing_type='daily' then
            b.amount * b.overlap_days
          when b.billing_type='monthly' then b.amount
          when b.billing_type='contract_total' and coalesce(b.total_days,0)>0 then
            case
              when b.overlap_end>=b.overlap_start
              then round(b.amount::numeric * b.overlap_days / b.total_days)::bigint
              else 0
            end
          else 0
        end::bigint as allocated_amount,
        case when b.start_date between b.ms and b.me then b.inquiries else 0 end,
        case when b.start_date between b.ms and b.me then b.visits else 0 end,
        case when b.start_date between b.ms and b.me then b.activations else 0 end,
        case when b.start_date between b.ms and b.me then b.attributed_margin else 0 end,
        b.note
      from base b
      order by b.start_date desc,b.channel,b.campaign;
    $function$;
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
      if not public.jk_business_can_manage() then raise exception 'not authorized'; end if;

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
CREATE OR REPLACE FUNCTION public.jk_customer_receipt_data(p_month date, p_as_of date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare base_date date;base_stamp timestamptz;result jsonb;
begin
 if not public.jk_business_can_manage() then raise exception 'not authorized';end if;
 if p_month is null or p_as_of is null then raise exception '조회 월을 확인하세요.';end if;
 select snapshot_date,updated_at into base_date,base_stamp from public.jk_internal_balances where snapshot_date<=p_as_of order by snapshot_date desc,updated_at desc limit 1;
 select jsonb_build_object(
  'rows',(select coalesce(jsonb_agg(to_jsonb(r) order by received_on desc,created_at desc),'[]') from public.jk_customer_receipts r where received_on>=date_trunc('month',p_month) and received_on<date_trunc('month',p_month)+interval '1 month'),
  'cash_delta',case when base_date is null then 0 else (select coalesce(sum(amount),0) from public.jk_customer_receipts where kind='customer' and not voided and not balance_included and received_on<=p_as_of and (received_on>base_date or (received_on=base_date and created_at>base_stamp))) end,
  'actual_customer_in',(select coalesce(sum(amount),0) from public.jk_customer_receipts where kind='customer' and not voided and received_on<=p_as_of and received_on>=date_trunc('month',p_month) and received_on<date_trunc('month',p_month)+interval '1 month')
 ) into result;
 return result;
end $function$;
CREATE OR REPLACE FUNCTION public.jk_expense_monthly_rows(p_month date)
 RETURNS TABLE(id uuid, expense_date date, start_date date, end_date date, is_fixed boolean, category text, subcategory text, description text, amount bigint, allocated_amount bigint, payment_method text, vendor text, note text, recurrence_type text, duration_months integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
      with params as (
        select date_trunc('month',p_month::timestamp)::date as ms
      ),
      base as (
        select
          e.*,
          p.ms,
          (
            (extract(year from p.ms)::int-extract(year from date_trunc('month',e.start_date))::int)*12
            + extract(month from p.ms)::int-extract(month from date_trunc('month',e.start_date))::int
          )::int as month_idx
        from public.jk_expenses e
        cross join params p
        where public.jk_business_can_manage()
      )
      select
        b.id,b.expense_date,b.start_date,b.end_date,b.is_fixed,b.category,b.subcategory,b.description,
        b.amount,
        case
          when b.recurrence_type='installment_total' and coalesce(b.duration_months,0)>0 then
            case
              when b.month_idx=b.duration_months-1
                then b.amount - floor(b.amount::numeric/b.duration_months)::bigint*(b.duration_months-1)
              else floor(b.amount::numeric/b.duration_months)::bigint
            end
          else b.amount
        end::bigint as allocated_amount,
        b.payment_method,b.vendor,b.note,b.recurrence_type,b.duration_months
      from base b
      where
        (b.recurrence_type='one_time' and date_trunc('month',b.start_date::timestamp)::date=b.ms)
        or
        (b.recurrence_type='monthly'
          and b.ms>=date_trunc('month',b.start_date::timestamp)::date
          and (b.end_date is null or b.ms<=date_trunc('month',b.end_date::timestamp)::date))
        or
        (b.recurrence_type in ('limited_months','installment_total')
          and b.month_idx>=0
          and b.month_idx<coalesce(b.duration_months,0))
      order by b.start_date desc,b.category,b.description;
    $function$;
CREATE OR REPLACE FUNCTION public.jk_internal_record_payment(p_item_key text, p_amount bigint, p_paid_on date, p_request_key uuid, p_payment_method text DEFAULT '계좌'::text, p_balance_included boolean DEFAULT false, p_note text DEFAULT ''::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare item public.jk_internal_items%rowtype; previous public.jk_internal_payments%rowtype; paid bigint; result uuid;
begin
 if not public.jk_business_can_manage() then raise exception 'not authorized';end if;
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
CREATE OR REPLACE FUNCTION public.jk_internal_record_payroll(p_item_key text, p_gross_amount bigint, p_income_tax bigint, p_local_tax bigint, p_paid_on date, p_request_key uuid, p_payment_method text DEFAULT '계좌'::text, p_balance_included boolean DEFAULT false, p_note text DEFAULT ''::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare item public.jk_internal_items%rowtype; previous public.jk_internal_payments%rowtype; paid bigint; result uuid;
begin
 if not public.jk_business_can_manage() then raise exception 'not authorized';end if;
 select * into item from public.jk_internal_items where item_key=p_item_key for update;
 if not found or item.excluded or item.category<>'payroll' or item.direction<>'out' then raise exception '급여 항목을 먼저 확인하세요.';end if;
 select * into previous from public.jk_internal_payments where request_key=p_request_key;
 if found then
  if previous.item_key<>p_item_key or previous.gross_amount<>p_gross_amount or previous.income_tax<>p_income_tax or previous.local_tax<>p_local_tax or previous.paid_on<>p_paid_on then raise exception '이미 사용된 지급 요청입니다.';end if;
  return previous.id;
 end if;
 if p_gross_amount is null or p_income_tax is null or p_local_tax is null or p_income_tax<0 or p_local_tax<0 or p_gross_amount<=p_income_tax+p_local_tax or p_paid_on is null or p_paid_on>(now() at time zone 'Asia/Seoul')::date then raise exception '급여 총액·공제액·실제 지급일을 확인하세요.';end if;
 if item.payroll_tax_mode='none' and p_income_tax+p_local_tax<>0 then raise exception '3.3%% 공제 설정을 확인하세요.';end if;
 select coalesce(sum(gross_amount),0) into paid from public.jk_internal_payments where item_key=p_item_key and not voided;
 if paid+p_gross_amount>item.amount then raise exception '급여 미정산 총액을 초과합니다.';end if;
 insert into public.jk_internal_payments(request_key,item_key,paid_on,amount,income_tax,local_tax,payment_method,balance_included,note)
 values(p_request_key,p_item_key,p_paid_on,p_gross_amount-p_income_tax-p_local_tax,p_income_tax,p_local_tax,p_payment_method,p_balance_included,coalesce(p_note,'')) returning id into result;
 return result;
end $function$;
CREATE OR REPLACE FUNCTION public.jk_internal_record_receipt(p_item_key text, p_amount bigint, p_paid_on date, p_request_key uuid, p_payment_method text, p_balance_included boolean, p_note text, p_receipt_name text, p_staff_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare staff text;result uuid;previous public.jk_internal_payments%rowtype;
begin
 if not public.jk_business_can_manage() then raise exception 'not authorized';end if;
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
end $function$;
CREATE OR REPLACE FUNCTION public.jk_internal_save_used(p_ledger_id uuid, p_sale_amount bigint, p_receipt_mode text, p_due_date date, p_sold_on date, p_adjust_payroll boolean, p_vendor_payment_id uuid, p_included_amount bigint, p_note text, p_updated_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l public.jk_sales_ledger%rowtype;u public.jk_internal_used_sales%rowtype;paid bigint;vendor_key text;
begin
 if not public.jk_business_can_manage() then raise exception 'not authorized';end if;
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
end $function$;
CREATE OR REPLACE FUNCTION public.jk_internal_save_used_with_details(p_ledger_id uuid, p_sale_amount bigint, p_receipt_mode text, p_due_date date, p_sold_on date, p_adjust_payroll boolean, p_vendor_payment_id uuid, p_included_amount bigint, p_note text, p_updated_at timestamp with time zone, p_buyer_name text, p_staff_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare staff text;
begin
 if not public.jk_business_can_manage() then raise exception 'not authorized';end if;
 if p_sold_on is null or nullif(trim(p_buyer_name),'') is null or length(p_buyer_name)>200 then raise exception '중고 판매일·매입처 이름·담당자를 입력하세요.';end if;
 select name into staff from public.jk_staff where id=p_staff_id and (active or id=(select handler_staff_id from public.jk_internal_used_sales where ledger_id=p_ledger_id));
 if not found then raise exception '담당자를 선택하세요.';end if;
 perform public.jk_internal_save_used(p_ledger_id,p_sale_amount,p_receipt_mode,p_due_date,p_sold_on,p_adjust_payroll,p_vendor_payment_id,p_included_amount,p_note,p_updated_at);
 update public.jk_internal_used_sales set buyer_name=trim(p_buyer_name),handler_staff_id=p_staff_id,handler_name=staff where ledger_id=p_ledger_id;
end $function$;
CREATE OR REPLACE FUNCTION public.jk_internal_settlement_data(p_month date, p_as_of date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare first_month date; last_month date; result jsonb;
begin
 if not public.jk_business_can_manage() then raise exception 'not authorized';end if;
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
CREATE OR REPLACE FUNCTION public.jk_internal_used_data(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare result jsonb;
begin
 if not public.jk_business_can_manage() then raise exception 'not authorized';end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by activation_date desc),'[]') into result from(
 select l.id ledger_id,l.customer_name_snapshot customer_name,l.customer_phone_snapshot customer_phone,l.activation_date,l.vendor,l.used_device_model model,l.used_device_amount expected_amount,
 l.salesperson_id,u.buyer_name,u.handler_staff_id,u.handler_name,u.sale_amount,u.receipt_mode,u.due_date,u.sold_on,u.adjust_payroll,u.included_amount,u.vendor_payment_id,u.note,u.updated_at,
 (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'paid_on',p.paid_on,'amount',p.amount,'receipt_name',p.receipt_name,'handler_name',p.handler_name,'voided',p.voided) order by p.paid_on desc,p.created_at desc),'[]') from public.jk_internal_payments p where p.item_key='used:'||l.id::text) receipts,
 case when u.receipt_mode='vendor' then u.included_amount else coalesce((select sum(p.amount) from public.jk_internal_payments p where p.item_key='used:'||l.id::text and not p.voided),0) end paid_amount,
 (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'paid_on',p.paid_on,'amount',p.amount,'direction',i.direction) order by p.paid_on desc),'[]') from public.jk_internal_payments p join public.jk_internal_items i using(item_key) where not p.voided and i.item_key='vendor:'||date_trunc('month',l.activation_date)::date::text||':'||md5(coalesce(nullif(trim(l.vendor),''),'미지정 거래처'))) vendor_payments
 from public.jk_sales_ledger l left join public.jk_internal_used_sales u on u.ledger_id=l.id
 where l.activation_date>=date_trunc('month',p_month) and l.activation_date<date_trunc('month',p_month)+interval '1 month' and (l.used_device_amount>0 or nullif(l.used_device_model,'') is not null or u.ledger_id is not null)
 ) r;return result;
end $function$;
CREATE OR REPLACE FUNCTION public.jk_internal_void_payment(p_id uuid, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare payment public.jk_internal_payments%rowtype; item public.jk_internal_items%rowtype;
begin
 if not public.jk_business_can_manage() then raise exception 'not authorized';end if;
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
CREATE OR REPLACE FUNCTION public.jk_log_consultation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_action text; v_note text;
begin
 -- Public writes do not acquire access to history; intake details remain on the parent record.
 if not public.jk_business_can_manage() then return new; end if;
 if tg_op='INSERT' then v_action:='상담 등록';v_note:=new.consultation_note;
 elsif (to_jsonb(new)-'updated_at')=(to_jsonb(old)-'updated_at') then return new;
 elsif new.last_contacted_at is distinct from old.last_contacted_at or new.last_contacted_on is distinct from old.last_contacted_on or new.last_contact_note is distinct from old.last_contact_note then v_action:='재연락 기록';v_note:=new.last_contact_note;
 else v_action:='상담 정보 수정';v_note:=new.consultation_note; end if;
 insert into public.jk_consultation_history(consultation_id,action,note,snapshot,created_by)
 values(new.id,v_action,coalesce(v_note,''),jsonb_build_object('staff_name',new.staff_name,'status',new.status,'visited_on',new.visited_on,'next_contact_on',new.next_contact_on,'last_contacted_on',new.last_contacted_on),auth.uid());
 return new;
end $function$;
CREATE OR REPLACE FUNCTION public.jk_mark_external_notification_sent(p_ledger_id uuid, p_event_type text, p_due_date date, p_provider text DEFAULT 'zeronote'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    declare
      l record;
      v_provider text;
    begin
      if not public.jk_business_can_manage() then raise exception 'not authorized'; end if;
      if p_event_type not in ('AFFILIATE_CARD','USED_DEVICE_RETURN','PLAN_CHANGE','INSURANCE_CANCEL','ADDON_CANCEL') then
        raise exception 'unsupported event type';
      end if;

      select customer_name_snapshot,customer_phone_snapshot
      into l
      from public.jk_sales_ledger
      where id=p_ledger_id;

      if not found then raise exception 'ledger not found'; end if;

      v_provider := coalesce(nullif(trim(p_provider),''),'zeronote');

      insert into public.jk_external_notification_log(
        ledger_id,event_type,due_date,customer_name,recipient_phone,provider,sent_at,created_by
      )
      values(
        p_ledger_id,p_event_type,p_due_date,l.customer_name_snapshot,l.customer_phone_snapshot,v_provider,now(),auth.uid()
      )
      on conflict (ledger_id,event_type,due_date)
      do update set
        provider=excluded.provider,
        sent_at=excluded.sent_at,
        customer_name=excluded.customer_name,
        recipient_phone=excluded.recipient_phone,
        created_by=auth.uid();

      update public.jk_notification_queue
      set status='cancelled',
          last_error='외부발송 완료로 자동발송 취소',
          updated_at=now()
      where ledger_id=p_ledger_id
        and event_type=p_event_type
        and status in ('pending','failed')
        and scheduled_for<=current_date;

      insert into public.jk_alert_action_log(
        ledger_id,alert_type,customer_name,due_date,action,detail,acted_by
      )
      values(
        p_ledger_id,p_event_type,l.customer_name_snapshot,p_due_date,'note',
        case when v_provider='zeronote' then '제로노트 외부발송 완료' else v_provider||' 외부발송 완료' end,
        auth.uid()
      );
    end;
    $function$;
CREATE OR REPLACE FUNCTION public.jk_mark_maintenance_done(p_ledger_id uuid, p_event_type text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    begin
      if not public.jk_business_can_manage() then raise exception 'not authorized'; end if;
      if p_event_type='PLAN_CHANGE' then
        update public.jk_sales_ledger set plan_change_done=true,updated_at=now() where id=p_ledger_id;
      elsif p_event_type='INSURANCE_CANCEL' then
        update public.jk_sales_ledger set insurance_cancel_done=true,updated_at=now() where id=p_ledger_id;
      elsif p_event_type='ADDON_CANCEL' then
        update public.jk_sales_ledger set addon_cancel_done=true,updated_at=now() where id=p_ledger_id;
      else
        raise exception 'unsupported event type';
      end if;
      update public.jk_notification_queue
        set status='cancelled',updated_at=now()
        where ledger_id=p_ledger_id and event_type=p_event_type and status in ('pending','failed');
    end;
    $function$;
CREATE OR REPLACE FUNCTION public.jk_monthly_customer_receipts(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
 if not public.jk_business_can_manage() then raise exception 'not authorized';end if;
 if p_month is null then raise exception '판매월을 선택해 주세요.';end if;
 return (
 select jsonb_build_object(
  'cash',coalesce(sum(greatest(coalesce(cash_received,0)-coalesce(card_received_amount,0),0)) filter(where cash_receipt_method in ('현금','현금+카드')),0),
  'bank',coalesce(sum(greatest(coalesce(cash_received,0)-coalesce(card_received_amount,0),0)) filter(where cash_receipt_method in ('계좌','계좌+카드')),0),
  'unclassified',coalesce(sum(greatest(coalesce(cash_received,0)-coalesce(card_received_amount,0),0)) filter(where cash_receipt_method is null),0),
  'card_charged',coalesce(sum(card_received_amount),0),
  'vendor_signed',coalesce(sum(coalesce(base_rebate,0)-coalesce(cash_sale_amount,0)),0),
  'final_margin',coalesce(sum(final_margin),0),
  'count',count(*)
 ) from public.jk_sales_ledger
 where activation_date>=date_trunc('month',p_month) and activation_date<date_trunc('month',p_month)+interval '1 month'
 );
end $function$;
CREATE OR REPLACE FUNCTION public.jk_next_month_break_even(p_as_of date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    declare
      v_current_month date := date_trunc('month',p_as_of)::date;
      v_next_month date := (date_trunc('month',p_as_of)+interval '1 month')::date;
      v_after_next date := (date_trunc('month',p_as_of)+interval '2 months')::date;

      v_expenses bigint := 0;
      v_ads bigint := 0;
      v_fixed_cost bigint := 0;
      v_booked_margin bigint := 0;

      v_current_margin bigint := 0;
      v_current_payroll bigint := 0;
      v_weighted_rate numeric := 0;
      v_avg_rate numeric := 0;
      v_safe_rate numeric := 0;

      v_break_even bigint := 0;
      v_safe_break_even bigint := 0;

      v_target bigint := null;
      v_current_target bigint := null;
      v_display_target bigint := null;
      v_target_carried boolean := false;
    begin
      if not public.jk_business_can_manage() then raise exception 'not authorized'; end if;

      select coalesce(sum(allocated_amount),0)::bigint
      into v_expenses
      from public.jk_expense_monthly_rows(v_next_month)
      where trim(coalesce(category,'')) <> '급여';

      select coalesce(sum(allocated_amount),0)::bigint
      into v_ads
      from public.jk_ad_monthly_rows(v_next_month);

      v_fixed_cost := v_expenses + v_ads;

      select coalesce(sum(final_margin),0)::bigint
      into v_booked_margin
      from public.jk_sales_ledger
      where activation_date>=v_next_month
        and activation_date<v_after_next;

      select
        coalesce(sum(margin_total),0)::bigint,
        coalesce(sum(payroll_amount),0)::bigint
      into v_current_margin,v_current_payroll
      from public.jk_v_staff_monthly_payroll
      where month=v_current_month;

      with rates as (
        select
          s.id,
          coalesce(r.rate_pct,0)::numeric as rate_pct
        from public.jk_staff s
        left join lateral (
          select p.rate_pct
          from public.jk_staff_pay_rates p
          where p.staff_id=s.id
            and p.effective_month<=v_next_month
          order by p.effective_month desc
          limit 1
        ) r on true
        where s.active
      )
      select
        coalesce(avg(rate_pct),0),
        coalesce(max(rate_pct),0)
      into v_avg_rate,v_safe_rate
      from rates;

      if v_current_margin > 0 then
        v_weighted_rate := least(95, greatest(0, (v_current_payroll::numeric / v_current_margin::numeric) * 100));
      else
        v_weighted_rate := least(95, greatest(0, v_avg_rate));
      end if;

      v_safe_rate := least(95, greatest(v_weighted_rate, coalesce(v_safe_rate,0)));

      if v_fixed_cost > 0 then
        v_break_even := ceil(v_fixed_cost::numeric / nullif(1-(v_weighted_rate/100),0))::bigint;
        v_safe_break_even := ceil(v_fixed_cost::numeric / nullif(1-(v_safe_rate/100),0))::bigint;
      end if;

      select target_margin
      into v_target
      from public.jk_targets
      where target_month=v_next_month
      limit 1;

      select target_margin
      into v_current_target
      from public.jk_targets
      where target_month=v_current_month
      limit 1;

      if v_target is not null and v_target>0 then
        v_display_target := v_target;
      elsif v_current_target is not null and v_current_target>0 then
        v_display_target := v_current_target;
        v_target_carried := true;
      end if;

      return jsonb_build_object(
        'plan_month',v_next_month,
        'booked_margin',v_booked_margin,
        'expense_total',v_expenses,
        'ad_total',v_ads,
        'non_payroll_cost',v_fixed_cost,
        'weighted_payroll_rate',round(v_weighted_rate,2),
        'safe_payroll_rate',round(v_safe_rate,2),
        'break_even_margin',v_break_even,
        'safe_break_even_margin',v_safe_break_even,
        'break_even_gap',greatest(v_break_even-v_booked_margin,0),
        'safe_break_even_gap',greatest(v_safe_break_even-v_booked_margin,0),
        'target_margin',v_target,
        'display_target_margin',v_display_target,
        'target_carried_forward',v_target_carried,
        'target_gap',case when v_display_target is null then null else greatest(v_display_target-v_booked_margin,0) end,
        'target_headroom_over_break_even',case when v_display_target is null then null else v_display_target-v_break_even end,
        'safe_target_headroom',case when v_display_target is null then null else v_display_target-v_safe_break_even end
      );
    end;
    $function$;
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
      if not public.jk_business_can_manage() then raise exception 'not authorized'; end if;

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
CREATE OR REPLACE FUNCTION public.jk_notification_connection_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    declare
      cfg record;
      enabled_templates integer;
      pending_count integer;
      failed_count integer;
    begin
      if not public.jk_business_can_manage() then raise exception 'not authorized'; end if;

      select enabled,
             (api_key is not null and api_key<>'') as has_api_key,
             (api_secret is not null and api_secret<>'') as has_api_secret,
             (pf_id is not null and pf_id<>'') as has_pf_id,
             (from_number is not null and from_number<>'') as has_from_number
      into cfg
      from public.jk_notification_provider_config where id=1;

      select count(*) into enabled_templates
      from public.jk_notification_templates
      where enabled and template_id is not null and template_id<>'';

      select count(*) into pending_count
      from public.jk_notification_queue
      where status='pending';

      select count(*) into failed_count
      from public.jk_notification_queue
      where status='failed';

      return jsonb_build_object(
        'provider','solapi',
        'enabled',coalesce(cfg.enabled,false),
        'credentials_ready',coalesce(cfg.has_api_key,false) and coalesce(cfg.has_api_secret,false),
        'channel_ready',coalesce(cfg.has_pf_id,false) and coalesce(cfg.has_from_number,false),
        'enabled_templates',enabled_templates,
        'pending_count',pending_count,
        'failed_count',failed_count,
        'schedule','09:10 / 18:10 KST'
      );
    end;
    $function$;
CREATE OR REPLACE FUNCTION public.jk_notification_template_settings()
 RETURNS TABLE(event_type text, label text, template_id text, enabled boolean, message_preview text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
      select t.event_type,t.label,t.template_id,t.enabled,t.message_preview
      from public.jk_notification_templates t
      where public.jk_business_can_manage()
      order by case t.event_type
        when 'AFFILIATE_CARD' then 1
        when 'USED_DEVICE_RETURN' then 2
        when 'PLAN_CHANGE' then 3
        when 'INSURANCE_CANCEL' then 4
        when 'ADDON_CANCEL' then 5
        else 99 end;
    $function$;
CREATE OR REPLACE FUNCTION public.jk_record_customer_receipt(p_request_key uuid, p_kind text, p_name text, p_amount bigint, p_received_on date, p_staff_id uuid, p_method text, p_balance_included boolean, p_ledger_id uuid DEFAULT NULL::uuid, p_note text DEFAULT ''::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare previous public.jk_customer_receipts%rowtype;staff text;l public.jk_sales_ledger%rowtype;paid bigint;result uuid;
begin
 if not public.jk_business_can_manage() then raise exception 'not authorized';end if;
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
end $function$;
CREATE OR REPLACE FUNCTION public.jk_sales_month_survival_floor(p_sales_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    declare
      v_sales_month date := date_trunc('month',p_sales_month)::date;
      v_survival_month date := (date_trunc('month',p_sales_month)+interval '1 month')::date;

      v_expenses bigint := 0;
      v_ads bigint := 0;
      v_cost bigint := 0;
      v_booked bigint := 0;
      v_target bigint := 0;

      v_avg_rate numeric := 0;
      v_safe_rate numeric := 0;
      v_floor bigint := 0;
      v_safe_floor bigint := 0;
    begin
      if not public.jk_business_can_manage() then raise exception 'not authorized'; end if;

      select coalesce(sum(allocated_amount),0)::bigint
      into v_expenses
      from public.jk_expense_monthly_rows(v_survival_month)
      where trim(coalesce(category,'')) <> '급여';

      select coalesce(sum(allocated_amount),0)::bigint
      into v_ads
      from public.jk_ad_monthly_rows(v_survival_month);

      v_cost := v_expenses + v_ads;

      select coalesce(sum(final_margin),0)::bigint
      into v_booked
      from public.jk_sales_ledger
      where activation_date>=v_sales_month
        and activation_date<v_survival_month;

      -- 계획용 적용 급여율:
      -- 해당 매출월에 적용되는 '활성 담당자' 급여율의 단순 평균.
      -- 예: 인성 0% + 송훈 40% = 20%.
      with rates as (
        select coalesce((
          select pr.rate_pct
          from public.jk_staff_pay_rates pr
          where pr.staff_id=s.id
            and pr.effective_month<=v_sales_month
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

      if v_cost>0 then
        v_floor := ceil(v_cost::numeric/nullif(1-(v_avg_rate/100),0))::bigint;
        v_safe_floor := ceil(v_cost::numeric/nullif(1-(v_safe_rate/100),0))::bigint;
      end if;

      select coalesce(target_margin,0)
      into v_target
      from public.jk_targets
      where target_month=v_sales_month
      limit 1;

      return jsonb_build_object(
        'sales_month',v_sales_month,
        'survival_month',v_survival_month,
        'booked_margin',v_booked,
        'target_margin',v_target,
        'survival_expense_total',v_expenses,
        'survival_ad_total',v_ads,
        'survival_cost_total',v_cost,
        'weighted_payroll_rate',round(v_avg_rate,2),
        'safe_payroll_rate',round(v_safe_rate,2),
        'rate_basis','active_staff_average',
        'required_sales_margin',v_floor,
        'safe_required_sales_margin',v_safe_floor,
        'required_gap',greatest(v_floor-v_booked,0),
        'safe_required_gap',greatest(v_safe_floor-v_booked,0),
        'target_gap',case when v_target>0 then greatest(v_target-v_booked,0) else null end,
        'target_headroom',case when v_target>0 then v_target-v_floor else null end,
        'safe_target_headroom',case when v_target>0 then v_target-v_safe_floor else null end
      );
    end;
    $function$;
CREATE OR REPLACE FUNCTION public.jk_save_cash_snapshot(p_snapshot_date date, p_bank_balance bigint, p_cash_on_hand bigint, p_other_liquid bigint, p_minimum_buffer bigint, p_other_upcoming_outflow bigint, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    begin
      if not public.jk_business_can_manage() then raise exception 'not authorized'; end if;
      insert into public.jk_cash_snapshots(
        snapshot_date,bank_balance,cash_on_hand,other_liquid,minimum_buffer,other_upcoming_outflow,note,created_by,updated_at
      )
      values(
        p_snapshot_date,coalesce(p_bank_balance,0),coalesce(p_cash_on_hand,0),coalesce(p_other_liquid,0),
        coalesce(p_minimum_buffer,0),coalesce(p_other_upcoming_outflow,0),nullif(trim(coalesce(p_note,'')),''),
        auth.uid(),now()
      )
      on conflict (snapshot_date)
      do update set
        bank_balance=excluded.bank_balance,
        cash_on_hand=excluded.cash_on_hand,
        other_liquid=excluded.other_liquid,
        minimum_buffer=excluded.minimum_buffer,
        other_upcoming_outflow=excluded.other_upcoming_outflow,
        note=excluded.note,
        updated_at=now();
    end;
    $function$;
CREATE OR REPLACE FUNCTION public.jk_save_notification_provider_config(p_api_key text, p_api_secret text, p_pf_id text, p_from_number text, p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    begin
      if not public.jk_business_can_manage() then raise exception 'not authorized'; end if;

      update public.jk_notification_provider_config
      set
        api_key = case when nullif(trim(coalesce(p_api_key,'')),'') is null then api_key else trim(p_api_key) end,
        api_secret = case when nullif(trim(coalesce(p_api_secret,'')),'') is null then api_secret else trim(p_api_secret) end,
        pf_id = case when nullif(trim(coalesce(p_pf_id,'')),'') is null then pf_id else trim(p_pf_id) end,
        from_number = case when nullif(regexp_replace(coalesce(p_from_number,''),'[^0-9]','','g'),'') is null then from_number else regexp_replace(p_from_number,'[^0-9]','','g') end,
        enabled = coalesce(p_enabled,false),
        updated_at = now(),
        updated_by = auth.uid()
      where id=1;

      return public.jk_notification_connection_status();
    end;
    $function$;
CREATE OR REPLACE FUNCTION public.jk_save_notification_template(p_event_type text, p_template_id text, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    begin
      if not public.jk_business_can_manage() then raise exception 'not authorized'; end if;
      if p_event_type not in ('AFFILIATE_CARD','USED_DEVICE_RETURN','PLAN_CHANGE','INSURANCE_CANCEL','ADDON_CANCEL') then
        raise exception 'invalid event type';
      end if;

      update public.jk_notification_templates
      set template_id=nullif(trim(coalesce(p_template_id,'')),''),
          enabled=coalesce(p_enabled,false),
          updated_at=now()
      where event_type=p_event_type;
    end;
    $function$;
CREATE OR REPLACE FUNCTION public.jk_save_statement_profile(p_vendor text, p_name text, p_settings jsonb, p_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare previous public.jk_vendor_statement_profiles%rowtype;result uuid;
begin
 if not public.jk_business_can_manage() then raise exception 'not authorized';end if;
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
end $function$;
CREATE OR REPLACE FUNCTION public.jk_set_staff_pay_rate(p_staff_id uuid, p_effective_month date, p_rate_pct numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    declare v_month date;
    begin
      if not public.jk_business_can_manage() then raise exception 'not authorized'; end if;
      if p_rate_pct < 0 or p_rate_pct > 100 then raise exception 'rate must be between 0 and 100'; end if;
      v_month := date_trunc('month',p_effective_month)::date;
      insert into public.jk_staff_pay_rates(staff_id,effective_month,rate_pct,created_by,updated_at)
      values(p_staff_id,v_month,p_rate_pct,auth.uid(),now())
      on conflict (staff_id,effective_month)
      do update set rate_pct=excluded.rate_pct,updated_at=now();
    end;
    $function$;
CREATE OR REPLACE FUNCTION public.jk_set_staff_pay_rate_from_month(p_staff_id uuid, p_effective_month date, p_rate_pct numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    declare
      v_month date;
    begin
      if not public.jk_business_can_manage() then raise exception 'not authorized'; end if;
      if p_rate_pct < 0 or p_rate_pct > 100 then raise exception 'rate must be between 0 and 100'; end if;

      v_month := date_trunc('month',p_effective_month)::date;

      -- "선택한 월부터 적용"은 그 이후에 저장돼 있던 급여율 예약값을 제거하고
      -- 선택월의 비율을 다음 변경월 전까지 계속 상속하도록 한다.
      delete from public.jk_staff_pay_rates
      where staff_id=p_staff_id
        and effective_month>=v_month;

      insert into public.jk_staff_pay_rates(
        staff_id,effective_month,rate_pct,created_by,updated_at
      )
      values(
        p_staff_id,v_month,p_rate_pct,auth.uid(),now()
      );
    end;
    $function$;
CREATE OR REPLACE FUNCTION public.jk_staff_pay_rate_settings(p_month date)
 RETURNS TABLE(staff_id uuid, staff_name text, rate_pct numeric, effective_month date)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
      select
        s.id,
        s.name,
        coalesce(r.rate_pct,0),
        r.effective_month
      from public.jk_staff s
      left join lateral (
        select p.rate_pct,p.effective_month
        from public.jk_staff_pay_rates p
        where p.staff_id=s.id
          and p.effective_month<=date_trunc('month',p_month)::date
        order by p.effective_month desc
        limit 1
      ) r on true
      where public.jk_business_can_manage()
        and s.active
      order by s.name;
    $function$;
CREATE OR REPLACE FUNCTION public.jk_void_customer_receipt(p_id uuid, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
 if not public.jk_business_can_manage() then raise exception 'not authorized';end if;
 if nullif(trim(p_note),'') is null then raise exception '취소 사유를 입력하세요.';end if;
 update public.jk_customer_receipts set voided=true,void_note=p_note where id=p_id and not voided;
end $function$;
