begin;
do $test$
declare
 baseline jsonb; got jsonb; survival jsonb; fixture uuid; fixture2 uuid;
begin
 perform set_config('request.jwt.claim.sub',(select user_id::text from public.admin_users where active limit 1),true);
 baseline:=public.jk_cashflow_status('2026-10-01');
 insert into public.jk_sales_ledger(activation_date,customer_name_snapshot,customer_phone_snapshot,base_rebate,cash_sale_amount,cash_received,cash_receipt_method,card_received_amount,card_settlement_amount,card_settlement_due_date)
 values ('2026-10-01','검증 전용','01000000000',500000,300000,600000,'카드',600000,582000,'2026-11-05') returning id into fixture;
 got:=public.jk_cashflow_status('2026-10-01');
 if (got->>'settlement_due_next_month')::bigint-(baseline->>'settlement_due_next_month')::bigint<>762000 then raise exception 'next-month pure card forecast mismatch';end if;
 if (got->>'settlement_due_this_month')::bigint<>(baseline->>'settlement_due_this_month')::bigint then raise exception 'card included in wrong month';end if;
 survival:=public.jk_next_month_cash_survival('2026-10-01');
 if survival->>'next_month_existing_settlement'<>got->>'settlement_due_next_month' then raise exception 'survival disagrees with forecast';end if;
 update public.jk_sales_ledger set card_settled_date='2026-11-05' where id=fixture;
 got:=public.jk_cashflow_status('2026-10-01');
 if (got->>'settlement_due_next_month')::bigint-(baseline->>'settlement_due_next_month')::bigint<>180000 then raise exception 'received card still forecasted';end if;
 update public.jk_sales_ledger set cash_received=800000,cash_receipt_method='계좌+카드',card_settled_date=null where id=fixture;
 got:=public.jk_cashflow_status('2026-10-01');
 if (got->>'settlement_due_next_month')::bigint-(baseline->>'settlement_due_next_month')::bigint<>762000 then raise exception 'mixed card double-counting';end if;
 update public.jk_sales_ledger set card_settlement_due_date='2026-12-05' where id=fixture;
 got:=public.jk_cashflow_status('2026-10-01');
 if (got->>'settlement_due_next_month')::bigint-(baseline->>'settlement_due_next_month')::bigint<>180000 then raise exception 'cross-month date filter mismatch';end if;
 insert into public.jk_sales_ledger(activation_date,customer_name_snapshot,customer_phone_snapshot,base_rebate,cash_sale_amount,cash_received,cash_receipt_method,card_received_amount,card_settlement_amount,card_settlement_due_date)
 values ('2026-09-30','검증 전용','01000000001',500000,300000,600000,'현금+카드',400000,388000,'2026-10-02') returning id into fixture2;
 got:=public.jk_cashflow_status('2026-10-01');
 if (got->>'settlement_due_this_month')::bigint-(baseline->>'settlement_due_this_month')::bigint<>568000 then raise exception 'current-month card forecast mismatch';end if;
 if (got->>'projected_after_month_end')::bigint-(baseline->>'projected_after_month_end')::bigint<>568000 then raise exception 'current-end balance mismatch';end if;
 begin
   update public.jk_sales_ledger set card_settlement_amount=500000 where id=fixture2;
   raise exception 'invalid net amount accepted';
 exception when check_violation then null; end;
 begin
   update public.jk_sales_ledger set cash_receipt_method=null where id=fixture2;
   raise exception 'unclassified positive card amount accepted';
 exception when check_violation then null; end;
 begin
   update public.jk_sales_ledger set card_settlement_due_date=null where id=fixture2;
   raise exception 'missing due date accepted';
 exception when check_violation then null; end;
 update public.jk_sales_ledger set cash_receipt_method='현금',card_received_amount=0,card_settlement_amount=null,card_settlement_due_date=null,card_settled_date=null where id=fixture2;
 got:=public.jk_cashflow_status('2026-10-01');
 if (got->>'settlement_due_this_month')::bigint-(baseline->>'settlement_due_this_month')::bigint<>180000 then raise exception 'changing to cash leaves stale card forecast';end if;
end $test$;
rollback;
select 'PASS: pure/mixed/cash, fees, due-month filtering, actual receipt exclusion, survival and balance totals, constraints; all test rows rolled back' as result;
