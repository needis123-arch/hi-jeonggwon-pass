-- Synthetic fixtures only; always rolled back.
begin;
do $$begin perform set_config('request.jwt.claims',jsonb_build_object('sub',(select user_id from public.admin_users where active limit 1),'role','authenticated')::text,true);end$$;
set local role authenticated;
do $$
declare l uuid;pay uuid;req uuid:=gen_random_uuid();today date:=(now() at time zone 'Asia/Seoul')::date;sm date:=date_trunc('month',today)::date;data jsonb;r jsonb;u jsonb;stamp timestamptz;vendor_name text:='__CASH_SEPARATION_'||gen_random_uuid();w bigint;
begin
 insert into public.jk_sales_ledger(activation_date,vendor,customer_name_snapshot,customer_phone_snapshot,base_rebate,cash_sale_amount,payback_amount,penalty_paid,cash_received,sim_cost,used_device_amount,cash_receipt_method,used_device_model,payback_due_date)
 values(sm,vendor_name,'SYNTHETIC CUSTOMER','01000000000',1100000,200000,100000,25000,300000,5000,200000,'현금','SYNTHETIC MODEL',today) returning id into l;
 if (select vat_amount from public.jk_sales_ledger where id=l)<>100000 then raise exception 'FAILED gross K VAT / 11';end if;
 select final_margin into w from public.jk_sales_ledger where id=l;
 if w<>1170000 then raise exception 'FAILED net wage margin %',w;end if;
 data:=public.jk_internal_settlement_data(sm,today);
 select value into r from jsonb_array_elements(data->'items') where value->>'item_key'='vendor:'||sm::text||':'||md5(vendor_name);
 if (r->>'amount')::bigint<>900000 or r->>'direction'<>'in' or (r->'basis'->>'gross_signed')::bigint<>900000 then raise exception 'FAILED gross vendor independent of VAT/Q/R/S/T/U';end if;
 perform public.jk_internal_save_used(l,250000,'separate',today,null,true,null,0,'SYNTHETIC higher sale',null);
 if (select used_device_amount from public.jk_sales_ledger where id=l)<>200000 or (select final_margin from public.jk_sales_ledger where id=l)<>1220000 then raise exception 'FAILED preserve U and adjust W +50k';end if;
 pay:=public.jk_internal_record_payment('used:'||l,200000,today,req,'계좌',true,'SYNTHETIC partial');
 if public.jk_internal_record_payment('used:'||l,200000,today,req)<>pay then raise exception 'FAILED used retry';end if;
 select value into u from jsonb_array_elements(public.jk_internal_used_data(sm)) where value->>'ledger_id'=l::text;
 if (u->>'paid_amount')::bigint<>200000 or (u->>'sale_amount')::bigint<>250000 then raise exception 'FAILED partial separate from sale valuation';end if;
 select updated_at into stamp from public.jk_internal_used_sales where ledger_id=l;
 begin perform public.jk_internal_save_used(l,199999,'separate',today,null,true,null,0,'SYNTHETIC invalid',stamp);raise exception 'FAILED below paid accepted';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 begin perform public.jk_internal_save_used(l,250000,'vendor',today,null,true,null,0,'SYNTHETIC invalid mode',stamp);raise exception 'FAILED paid mode changed';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 begin perform public.jk_internal_save_used(l,250000,'separate',today,null,true,null,0,'SYNTHETIC stale',null);raise exception 'FAILED stale accepted';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 perform public.jk_internal_record_payment('used:'||l,50000,today,gen_random_uuid(),'계좌',true);
 data:=public.jk_internal_settlement_data(sm,today);
 select value into r from jsonb_array_elements(data->'items') where value->>'item_key'='vendor:'||sm::text||':'||md5(vendor_name);
 if (r->>'amount')::bigint<>900000 then raise exception 'FAILED used proceeds double counted in vendor';end if;
 insert into public.jk_internal_items(item_key,category,title,source_month,direction,amount,due_date) values('payback:'||l,'payback','SYNTHETIC customer payback',sm,'out',100000,today);
 begin perform public.jk_internal_record_payment('payback:'||l,40000,today,gen_random_uuid());raise exception 'FAILED unverified account accepted';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 insert into public.jk_payback_accounts(ledger_id,bank_name,account_holder,account_number,verification_status,verified_at) values(l,'SYNTHETIC','SYNTHETIC','000','verified',now());
 req:=gen_random_uuid();pay:=public.jk_internal_record_payment('payback:'||l,40000,today,req,'계좌',true);
 if public.jk_internal_record_payment('payback:'||l,40000,today,req)<>pay then raise exception 'FAILED payback retry';end if;
 if (select outstanding_amount from public.jk_v_payback_status where ledger_id=l)<>60000 or exists(select 1 from public.jk_internal_payments where id=pay) then raise exception 'FAILED native payback integration/double count';end if;
 data:=public.jk_internal_settlement_data(sm,today);
 if (select count(*) from jsonb_array_elements(data->'payments') where value->>'id'=pay::text)<>1 then raise exception 'FAILED payback cash counted twice';end if;
 begin perform public.jk_internal_record_payment('payback:'||l,60001,today,gen_random_uuid());raise exception 'FAILED payback overpaid';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 perform public.jk_internal_record_payment('payback:'||l,60000,today,gen_random_uuid(),'계좌',true);
 if (select outstanding_amount from public.jk_v_payback_status where ledger_id=l)<>0 then raise exception 'FAILED full payback';end if;
 perform public.jk_internal_void_payment(pay,'SYNTHETIC reversal');
 if (select outstanding_amount from public.jk_v_payback_status where ledger_id=l)<>40000 then raise exception 'FAILED payback reversal';end if;
 -- Lower final sale changes profit by -50k without treating partial receipt as a price loss.
 perform public.jk_internal_void_payment((select id from public.jk_internal_payments where item_key='used:'||l and amount=50000),'SYNTHETIC correction');
 perform public.jk_internal_void_payment((select id from public.jk_internal_payments where item_key='used:'||l and amount=200000),'SYNTHETIC correction');
 select updated_at into stamp from public.jk_internal_used_sales where ledger_id=l;
 perform public.jk_internal_save_used(l,150000,'separate',today,null,true,null,0,'SYNTHETIC lower sale',stamp);
 if (select final_margin from public.jk_sales_ledger where id=l)<>1120000 then raise exception 'FAILED lower sale payroll adjustment';end if;
end $$;
reset role;
do $$begin
 if has_table_privilege('anon','public.jk_internal_used_sales','select') or has_function_privilege('anon','public.jk_internal_used_data(date)','execute') or has_function_privilege('anon','public.jk_internal_save_used(uuid,bigint,text,date,date,boolean,uuid,bigint,text,timestamptz)','execute') then raise exception 'FAILED anonymous access';end if;
end $$;
rollback;
select 'PASS: VAT-inclusive vendor versus net wages, separate payback/native synchronization/reversal, higher/lower used sale and partial receipts, stable U, concurrency guards, no double cash, private access; fixtures rolled back' result;
