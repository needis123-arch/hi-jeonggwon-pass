-- Only synthetic records, rolled back after verification.
begin;
do $$begin perform set_config('request.jwt.claims',jsonb_build_object('sub',(select user_id from public.admin_users where active limit 1),'role','authenticated')::text,true);end$$;
do $$
declare l uuid;today date:=(now() at time zone 'Asia/Seoul')::date;
begin
 insert into public.jk_sales_ledger(activation_date,vendor,customer_name_snapshot,customer_phone_snapshot,base_rebate,cash_sale_amount,cash_received,used_device_amount,cash_receipt_method)
 values(today,'__USED_LEDGER_ONLY_TEST','SYNTHETIC CUSTOMER','01000000000',170000,319000,319000,50000,'현금') returning id into l;
 insert into public.jk_internal_used_sales(ledger_id,sale_amount,receipt_mode,due_date,adjust_payroll) values(l,999000,'vendor',today+40,true);
 insert into public.jk_internal_items(item_key,category,title,source_month,direction,amount,due_date) values('used:'||l,'used','SYNTHETIC OLD SALE',date_trunc('month',today)::date,'in',999000,today+40);
 perform set_config('test.used_ledger_id',l::text,true);
end$$;
set local role authenticated;
do $$
declare l uuid:=current_setting('test.used_ledger_id')::uuid;w bigint;p bigint;data jsonb;r jsonb;today date:=(now() at time zone 'Asia/Seoul')::date;
begin
 update public.jk_sales_ledger set used_device_amount=80000 where id=l;
 select final_margin,vat_amount into w,p from public.jk_sales_ledger where id=l;
 if w<>250000 or p<>0 then raise exception 'FAIL: stale sale overrides edited ledger U: %, %',w,p;end if;
 update public.jk_sales_ledger set used_device_amount=20000 where id=l;
 if (select final_margin from public.jk_sales_ledger where id=l)<>190000 then raise exception 'FAIL: decreasing U does not recalculate W';end if;
 data:=public.jk_internal_settlement_data(date_trunc('month',today)::date,today);
 select value into r from jsonb_array_elements(data->'items') where value->>'item_key'='used:'||l;
 if not coalesce((r->>'excluded')::boolean,false) or coalesce((data->>'missing_used_dates')::int,-1)<>0 then raise exception 'FAIL: retired used workflow still forecasts income';end if;
 select value into r from jsonb_array_elements(data->'items') where value->>'item_key'='vendor:'||date_trunc('month',today)::date::text||':'||md5('__USED_LEDGER_ONLY_TEST');
 if r->>'direction'<>'out' or (r->>'amount')::bigint<>149000 then raise exception 'FAIL: vendor settlement changed';end if;
 if has_table_privilege('authenticated','public.jk_internal_used_sales','insert') or has_function_privilege('authenticated','public.jk_internal_save_used(uuid,bigint,text,date,date,boolean,uuid,bigint,text,timestamptz)','execute') then raise exception 'FAIL: old workflow remains writable';end if;
end$$;
reset role;
rollback;
select 'PASS: editing U increases/decreases W despite a stale confirmed price; vendor and real-rebate reserve unchanged; retired forecast excluded; history preserved; obsolete write blocked; fixtures rolled back' result;
