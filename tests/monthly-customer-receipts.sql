begin;
select set_config('request.jwt.claim.sub',(select user_id::text from public.admin_users where active limit 1),true);
set local role authenticated;
do $$declare sm date:=date_trunc('month',now())::date;b jsonb;a jsonb;l uuid;begin
 b:=public.jk_monthly_customer_receipts(sm);
 insert into public.jk_sales_ledger(activation_date,customer_name_snapshot,customer_phone_snapshot,base_rebate,cash_sale_amount,cash_received,cash_receipt_method)
 values(sm,'SYNTHETIC','01000000000',170000,319000,319000,'현금') returning id into l;
 if (select vat_amount from public.jk_sales_ledger where id=l)<>0 or (select final_margin from public.jk_sales_ledger where id=l)<>170000 then raise exception 'negative real rebate cash example incorrect';end if;
 insert into public.jk_sales_ledger(activation_date,customer_name_snapshot,customer_phone_snapshot,cash_received,cash_receipt_method,card_received_amount,card_settlement_amount,card_settlement_due_date)
 values(sm,'SYNTHETIC MIXED','01000000001',500000,'계좌+카드',300000,290000,sm+10);
 a:=public.jk_monthly_customer_receipts(sm);
 if (a->>'cash')::bigint-(b->>'cash')::bigint<>319000 or (a->>'bank')::bigint-(b->>'bank')::bigint<>200000 or (a->>'card_charged')::bigint-(b->>'card_charged')::bigint<>300000 then raise exception 'receipt classification double counted card';end if;
 if has_function_privilege('anon','public.jk_monthly_customer_receipts(date)','execute') then raise exception 'public money data exposed';end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
set local role authenticated;
do $$begin
 begin perform public.jk_monthly_customer_receipts(current_date);raise exception 'FAILED nonadmin access';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
end $$;
rollback;
select 'PASS: K170k-L319k+S319k=W170k, cash/bank/card classification, nonadmin isolation; rolled back' result;
