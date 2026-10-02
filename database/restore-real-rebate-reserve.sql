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


comment on column public.jk_sales_ledger.vat_amount is 'P: operating wage reserve, round(max(K-L,0)*0.1). Actual tax returns use invoice evidence.';
-- The margin trigger runs on input columns, not on vat_amount itself.
update public.jk_sales_ledger set base_rebate=base_rebate where vat_amount is distinct from round(greatest(coalesce(base_rebate,0)-coalesce(cash_sale_amount,0),0)::numeric*0.1)::bigint;
notify pgrst,'reload schema';
