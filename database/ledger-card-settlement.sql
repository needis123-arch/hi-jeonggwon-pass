-- Additive BUSINESS CENTER V3.41 upgrade. Existing S and W values remain unchanged.
-- NULL receipt method denotes legacy records whose actual receipt method is unknown.
alter table public.jk_sales_ledger
  add column cash_receipt_method text,
  add column card_received_amount bigint not null default 0,
  add column card_settlement_amount bigint,
  add column card_settlement_due_date date,
  add column card_settled_date date,
  add constraint jk_receipt_method_check check (cash_receipt_method is null or cash_receipt_method in ('현금','계좌','카드','현금+카드','계좌+카드')),
  add constraint jk_card_receipt_check check (
    (card_received_amount=0 and card_settlement_amount is null and card_settlement_due_date is null and card_settled_date is null and coalesce(cash_receipt_method,'') not in ('카드','현금+카드','계좌+카드'))
    or
    (cash_receipt_method is not null and cash_receipt_method in ('카드','현금+카드','계좌+카드') and
     card_received_amount>0 and card_received_amount<=cash_received and
     card_settlement_amount is not null and card_settlement_amount>=0 and card_settlement_amount<=card_received_amount and
     card_settlement_due_date is not null and card_settlement_due_date>=activation_date and
     (card_settled_date is null or card_settled_date>=activation_date) and
     ((cash_receipt_method='카드' and card_received_amount=cash_received) or
      (cash_receipt_method in ('현금+카드','계좌+카드') and card_received_amount<cash_received)))
  );
comment on column public.jk_sales_ledger.cash_received is 'S: total customer upfront receipts, including gross card payments. Excluded from vendor settlement (W-S).';
comment on column public.jk_sales_ledger.card_settlement_amount is 'Net card deposit after fees; included in due-month cash forecast only while card_settled_date is NULL.';
create index jk_sales_pending_card_due_idx on public.jk_sales_ledger(card_settlement_due_date) where card_received_amount>0 and card_settled_date is null;

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
      -- 페이백 Q는 W에 이미 반영되어 있으므로 중복 차감하지 않는다.
      v_projected :=
        v_available
        + v_settlement_this_month
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
    $function$
;
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

      v_next_end_no_more_sales :=
        v_current_end_cash
        + v_next_settlement
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
    $function$
;
notify pgrst,'reload schema';

