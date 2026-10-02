-- All synthetic records and temporary balance checkpoint changes roll back.
begin;
select set_config('request.jwt.claim.sub',(select user_id::text from public.admin_users where active limit 1),true);
set local role authenticated;
do $$
declare staff uuid;l uuid;a uuid;b uuid;profile uuid;stamp timestamptz;pay uuid;request uuid:=gen_random_uuid();
 today date:=(now() at time zone 'Asia/Seoul')::date;data jsonb;task_vendor text:='__STATEMENT_TEST_'||gen_random_uuid();settings jsonb;
begin
 insert into public.jk_staff(name) values('__RECEIPT_STAFF_'||gen_random_uuid()) returning id into staff;
 settings:=jsonb_build_object('sheet','정산','header_row',2,'sign',-1,'net_mode','net','columns',jsonb_build_object('net',jsonb_build_object('index',8,'header','정산합계')));
 profile:=public.jk_save_statement_profile(task_vendor,'휴대폰 정산',settings,null);
 perform public.jk_save_statement_profile(task_vendor||'_OTHER','다른 양식',settings||'{"header_row":5,"sign":1}',null);
 if (select count(*) from public.jk_vendor_statement_profiles where vendor in (task_vendor,task_vendor||'_OTHER'))<>2 then raise exception 'vendor layouts not independent';end if;
 select updated_at into stamp from public.jk_vendor_statement_profiles where id=profile;
 perform public.jk_save_statement_profile(task_vendor,'휴대폰 정산',settings||'{"header_row":3}',stamp);
 begin perform public.jk_save_statement_profile(task_vendor,'휴대폰 정산',settings,stamp);raise exception 'FAILED stale layout accepted';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 insert into public.jk_sales_ledger(activation_date,customer_name_snapshot,customer_phone_snapshot,base_rebate,cash_sale_amount,cash_received,cash_receipt_method,used_device_amount,used_device_model)
 values(today,'SYNTHETIC CUSTOMER','01000000000',170000,319000,319000,'현금',200000,'SYNTHETIC USED') returning id into l;
 insert into public.jk_internal_balances(snapshot_date,total_balance,updated_at) values(today,1000000,now())
 on conflict(snapshot_date) do update set total_balance=1000000;
 a:=public.jk_record_customer_receipt(request,'customer','SYNTHETIC CUSTOMER',200000,today,staff,'현금',true,l,'included');
 if public.jk_record_customer_receipt(request,'customer','SYNTHETIC CUSTOMER',200000,today,staff,'현금',true,l,'included')<>a then raise exception 'cash retry not idempotent';end if;
 b:=public.jk_record_customer_receipt(gen_random_uuid(),'customer','SYNTHETIC CUSTOMER',119000,today,staff,'계좌',false,l,'new');
 update public.jk_customer_receipts set created_at=clock_timestamp() where id=b;
 data:=public.jk_customer_receipt_data(today,today);
 if (data->>'cash_delta')::bigint<>119000 then raise exception 'included cash counted twice or new cash missing %',data->>'cash_delta';end if;
 if (select final_margin from public.jk_sales_ledger where id=l)<>370000 then raise exception 'cash record incorrectly changed S/W';end if;
 begin perform public.jk_record_customer_receipt(gen_random_uuid(),'customer','EXCESS',1,today,staff,'현금',true,l,'');raise exception 'FAILED customer overreceipt accepted';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 begin perform public.jk_record_customer_receipt(gen_random_uuid(),'customer','FUTURE',1,today+1,staff,'현금',true,null,'');raise exception 'FAILED future receipt accepted';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 begin perform public.jk_record_customer_receipt(request,'customer','SYNTHETIC CUSTOMER',200001,today,staff,'현금',true,l,'included');raise exception 'FAILED changed retry accepted';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
 perform public.jk_void_customer_receipt(b,'SYNTHETIC wrong entry');
 if (public.jk_customer_receipt_data(today,today)->>'cash_delta')::bigint<>0 then raise exception 'void did not undo cash change';end if;
 perform public.jk_internal_save_used_with_details(l,250000,'separate',today,today,true,null,0,'SYNTHETIC higher price',null,'SYNTHETIC BUYER',staff);
 if (select final_margin from public.jk_sales_ledger where id=l)<>420000 then raise exception 'used confirmed difference changed';end if;
 request:=gen_random_uuid();pay:=public.jk_internal_record_receipt('used:'||l,100000,today,request,'계좌',true,'partial','SYNTHETIC BUYER',staff);
 if public.jk_internal_record_receipt('used:'||l,100000,today,request,'계좌',true,'partial','SYNTHETIC BUYER',staff)<>pay then raise exception 'used retry not idempotent';end if;
 if not exists(select 1 from public.jk_internal_payments where id=pay and receipt_name='SYNTHETIC BUYER' and handler_staff_id=staff and handler_name<>'') then raise exception 'receipt person/staff missing';end if;
 select value into data from jsonb_array_elements(public.jk_internal_used_data(today)) where value->>'ledger_id'=l::text;
 if data->>'buyer_name'<>'SYNTHETIC BUYER' or (data->>'paid_amount')::bigint<>100000 or jsonb_array_length(data->'receipts')<>1 then raise exception 'used detail/history missing';end if;
 update public.jk_staff set active=false where id=staff;
 if (select staff_name from public.jk_customer_receipts where id=a)='' then raise exception 'inactive staff snapshot lost';end if;
 begin perform public.jk_record_customer_receipt(gen_random_uuid(),'customer','INACTIVE',1,today,staff,'계좌',true,null,'');raise exception 'FAILED inactive staff accepted';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
end $$;
reset role;
set local role anon;
do $$begin
 begin perform count(*) from public.jk_customer_receipts;raise exception 'anonymous receipts exposed';exception when insufficient_privilege then null;end;
 begin perform count(*) from public.jk_vendor_statement_profiles;raise exception 'anonymous layouts exposed';exception when insufficient_privilege then null;end;
 if has_function_privilege('anon','public.jk_customer_receipt_data(date,date)','execute') then raise exception 'anonymous receipt RPC exposed';end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
set local role authenticated;
do $$begin
 if (select count(*) from public.jk_customer_receipts)<>0 or (select count(*) from public.jk_vendor_statement_profiles)<>0 then raise exception 'nonadmin data exposed';end if;
 begin perform public.jk_customer_receipt_data(current_date,current_date);raise exception 'FAILED nonadmin RPC';exception when raise_exception then if sqlerrm like 'FAILED%' then raise;end if;end;
end $$;
rollback;
select 'PASS: independent vendor profiles/stale guards, named dated staffed cash/used receipts, partial/retry/excess/void controls, unchanged ledger S/W, private access; rolled back' as result;
