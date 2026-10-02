-- Synthetic fixtures, all rolled back. No production cash or payment is persisted.
begin;
do $$begin perform set_config('request.jwt.claims',jsonb_build_object('sub',(select user_id from public.admin_users limit 1),'role','authenticated')::text,true);end$$;
set local role authenticated;
do $$
declare k text:='test:'||gen_random_uuid(); req uuid:=gen_random_uuid(); p uuid; data jsonb; r jsonb;
 v text:='__FINANCE_TEST_'||gen_random_uuid(); ledger_id uuid:=gen_random_uuid(); card_id uuid:=gen_random_uuid(); today date:=(now() at time zone 'Asia/Seoul')::date; sm date:=(date_trunc('month',today)-interval '1 month')::date; fixture jsonb; writable_columns text;
begin
 insert into public.jk_internal_balances(snapshot_date,total_balance,tax_reserve_target,tax_reserve_saved) values('2000-01-01',123456789,2000,1000);
 begin insert into public.jk_internal_balances(snapshot_date,total_balance,tax_reserve_saved) values('2000-01-02',100,101);raise exception 'FAILED tax subset';exception when check_violation then null;end;
 insert into public.jk_internal_items(item_key,category,title,source_month,direction,amount,due_date) values(k,'payroll','SYNTHETIC test payroll',sm,'out',700,today);
 p:=public.jk_internal_record_payment(k,300,today,req,'계좌',true,'SYNTHETIC partial');
 if public.jk_internal_record_payment(k,300,today,req,'계좌',true,'SYNTHETIC retry')<>p then raise exception 'FAILED idempotency';end if;
 if (select sum(amount) from public.jk_internal_payments where item_key=k and not voided)<>300 then raise exception 'FAILED partial';end if;
 begin perform public.jk_internal_record_payment(k,401,today,gen_random_uuid());raise exception 'FAILED overpayment accepted';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 begin perform public.jk_internal_record_payment(k,1,today+1,gen_random_uuid());raise exception 'FAILED future payment accepted';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 begin update public.jk_internal_items set direction='in' where item_key=k;raise exception 'FAILED direction mutation';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 begin update public.jk_internal_items set amount=299 where item_key=k;raise exception 'FAILED lower than paid';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 perform public.jk_internal_void_payment(p,'SYNTHETIC correction');
 if not(select voided from public.jk_internal_payments where id=p) then raise exception 'FAILED void';end if;
 perform public.jk_internal_record_payment(k,700,today,gen_random_uuid());
 if (select sum(amount) from public.jk_internal_payments where item_key=k and not voided)<>700 then raise exception 'FAILED full';end if;
 insert into public.jk_internal_items(item_key,category,title,source_month,direction,amount,due_date) values(k||':future','manual','SYNTHETIC future receivable',sm,'in',100,today+400);
 perform public.jk_internal_record_payment(k||':future',100,today,gen_random_uuid());
 data:=public.jk_internal_settlement_data(date_trunc('month',today)::date,today);
 if not exists(select 1 from jsonb_array_elements(data->'items') a where a->>'item_key'=k||':future') then raise exception 'FAILED future payment reference missing';end if;
 insert into public.jk_internal_tax_invoices(invoice_date,kind,vendor,supply_amount,vat_amount,creditable) values(today,'purchase','SYNTHETIC invoice',1000,100,true);
 select string_agg(quote_ident(column_name),',' order by ordinal_position) into writable_columns from information_schema.columns where table_schema='public' and table_name='jk_sales_ledger' and is_generated='NEVER';
 select to_jsonb(l) into fixture from public.jk_sales_ledger l limit 1;
 if fixture is not null then
 fixture:=fixture||jsonb_build_object('id',ledger_id,'vendor',v,'customer_id',null,'customer_name_snapshot','SYNTHETIC FINANCE CUSTOMER','customer_phone_snapshot','01000000000','activation_date',sm,'retail_price',1683000,'base_rebate',560000,'cash_sale_amount',1324000,'sim_fee',0,'move_fee',0,'payback_amount',0,'penalty_paid',0,'cash_received',1000000,'sim_cost',0,'used_device_amount',0,'used_return_required',false,'cash_receipt_method','현금','card_received_amount',0,'card_settlement_amount',null,'card_settlement_due_date',null,'card_settled_date',null,'flag_additional',false,'flag_dongpan',false,'flag_bundle',false,'flag_contract_renewal',false,'affiliate_card_status','안함');
 execute format('insert into public.jk_sales_ledger (%s) select %s from jsonb_populate_record(null::public.jk_sales_ledger,$1)',writable_columns,writable_columns) using fixture;
 data:=public.jk_internal_settlement_data(date_trunc('month',today)::date,today);
 select value into r from jsonb_array_elements(data->'items') where value->>'item_key'='vendor:'||sm::text||':'||md5(v);
 if r->>'direction'<>'out' or (r->>'amount')::bigint<>764000 then raise exception 'FAILED signed W-S: %',r;end if;
 fixture:=fixture||jsonb_build_object('id',card_id,'vendor',v||'_card','cash_receipt_method','카드','card_received_amount',1000000,'card_settlement_amount',970000,'card_settlement_due_date',today+5,'card_settled_date',null);
 execute format('insert into public.jk_sales_ledger (%s) select %s from jsonb_populate_record(null::public.jk_sales_ledger,$1)',writable_columns,writable_columns) using fixture;
 insert into public.jk_internal_items(item_key,category,title,source_month,direction,amount,due_date) values('card:'||card_id,'card','SYNTHETIC card',sm,'in',970000,today+5);
 perform public.jk_internal_record_payment('card:'||card_id,300000,today,gen_random_uuid());
 if (select card_settled_date from public.jk_sales_ledger where id=card_id) is not null then raise exception 'FAILED partial card marked settled';end if;
 p:=public.jk_internal_record_payment('card:'||card_id,670000,today,gen_random_uuid());
 if (select card_settled_date from public.jk_sales_ledger where id=card_id)<>today then raise exception 'FAILED card integration';end if;
 perform public.jk_internal_void_payment(p,'SYNTHETIC reversal');
 if (select card_settled_date from public.jk_sales_ledger where id=card_id) is not null then raise exception 'FAILED card reversal';end if;
 perform public.jk_internal_record_payment('card:'||card_id,670000,today,gen_random_uuid());
 perform public.jk_internal_void_payment(p,'SYNTHETIC repeated reversal');
 if (select card_settled_date from public.jk_sales_ledger where id=card_id)<>today then raise exception 'FAILED repeated void undid new payment';end if;
 end if;
end $$;
reset role;
set local role anon;
do $$begin
 begin perform * from public.jk_internal_balances;raise exception 'FAILED anon balances readable';exception when insufficient_privilege then null;end;
 begin perform public.jk_internal_settlement_data(current_date,current_date);raise exception 'FAILED anon RPC callable';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$begin perform set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);end$$;
set local role authenticated;
do $$begin
 if exists(select 1 from public.jk_internal_items) or exists(select 1 from public.jk_internal_payments) or exists(select 1 from public.jk_internal_balances) or exists(select 1 from public.jk_internal_tax_invoices) then raise exception 'FAILED non-admin readable';end if;
 begin perform public.jk_internal_settlement_data(current_date,current_date);raise exception 'FAILED non-admin RPC allowed';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 begin insert into public.jk_internal_balances(snapshot_date,total_balance) values('2000-01-03',123);raise exception 'FAILED non-admin writable';exception when insufficient_privilege then null;end;
end$$;
reset role;
select 'PASS: administrator cash constraints, signed vendor settlement, partial/full/duplicate/future/overpayment checks, payment reversal, card ledger integration, invoice records, anon/non-admin isolation; all fixtures rolled back' as result;
rollback;
