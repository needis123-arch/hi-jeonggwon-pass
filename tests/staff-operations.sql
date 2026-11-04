-- Synthetic records only. Every fixture is rolled back.
begin;
do $$declare u uuid:=gen_random_uuid();l uuid:=gen_random_uuid();c uuid:=gen_random_uuid();mail text;begin
 mail:='staff-operations-'||u||'@example.invalid';
 insert into auth.users(id,email,email_confirmed_at) values(u,mail,now());
 insert into jk_document_private.access_requests(user_id,email,display_name,status) values(u,mail,'SYNTHETIC OPERATIONS STAFF','pending');
 insert into public.jk_sales_ledger(id,activation_date,customer_name_snapshot,customer_phone_snapshot,base_rebate,cash_sale_amount,cash_received,payback_amount,used_device_amount,used_device_model,used_return_required,affiliate_card_status,affiliate_card_company,affiliate_card_amount)
 values(l,'2099-01-20','SYNTHETIC OPERATIONS CUSTOMER','01000000000',170000,319000,319000,100000,50000,'SYNTHETIC MODEL',true,'미완료','SYNTHETIC CARD',10000);
 insert into public.jk_payback_accounts(ledger_id,bank_name,account_holder,account_number) values(l,'SYNTHETIC BANK','SYNTHETIC HOLDER','000');
 insert into public.jk_consultations(id,customer_name,phone_digits,consulted_on,status,consultation_note,next_contact_on) values(c,'SYNTHETIC OPERATIONS CONSULTATION','01000000123','2099-01-20','재연락','SYNTHETIC NOTE','2099-01-23');
 insert into public.jk_consultation_history(consultation_id,action,note,snapshot,created_by) values(c,'SYNTHETIC HISTORY','SYNTHETIC FOLLOWUP',jsonb_build_object('staff_name','테스트','status','재연락','next_contact_on','2099-01-23','private_field','must not expose'),u);
 perform set_config('test.staff_ops_uid',u::text,true);perform set_config('test.staff_ops_ledger',l::text,true);perform set_config('test.staff_ops_consult',c::text,true);
 perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'is_anonymous',false,'role','authenticated')::text,true);
end$$;
set local role authenticated;
do $$begin
 begin perform public.jk_staff_operations('used','2099-01-01');raise exception 'FAIL pending operations allowed';exception when insufficient_privilege then null;end;
 begin perform public.jk_staff_consultations();raise exception 'FAIL pending consultations allowed';exception when insufficient_privilege then null;end;
end$$;
reset role;
update jk_document_private.access_requests set status='approved' where user_id=current_setting('test.staff_ops_uid')::uuid;
set local role authenticated;
do $$declare l uuid:=current_setting('test.staff_ops_ledger')::uuid;c uuid:=current_setting('test.staff_ops_consult')::uuid;data jsonb;r jsonb;n integer;screen text;begin
 if public.is_admin() then raise exception 'FAIL employee became admin';end if;
 foreach screen in array array['used','payback','affiliate'] loop
  data:=public.jk_staff_operations(screen,case when screen='used' then date '2099-01-01' else date '2099-02-01' end);
  if not exists(select 1 from jsonb_array_elements(data) x where x->>'ledger_id'=l::text) then raise exception 'FAIL approved % missing',screen;end if;
  data:=public.jk_staff_operations(screen,'2099-03-01');
  if exists(select 1 from jsonb_array_elements(data) x where x->>'ledger_id'=l::text) then raise exception 'FAIL % month filter',screen;end if;
 end loop;
 data:=public.jk_staff_consultations(p_id=>c);r:=data->'rows'->0;
 if r->>'consultation_note'<>'SYNTHETIC NOTE' or jsonb_array_length(data->'history')<>1 then raise exception 'FAIL consultation detail/history missing';end if;
 if r ? 'public_request_key' or r ? 'consented_at' or (data->'history'->0) ? 'created_by' or (data->'history'->0->'snapshot') ? 'private_field' then raise exception 'FAIL unnecessary consultation fields exposed';end if;
 data:=public.jk_staff_consultations(p_status=>'all',p_search=>'00000123');
 if not exists(select 1 from jsonb_array_elements(data->'rows') x where x->>'id'=c::text) then raise exception 'FAIL consultation phone search';end if;
 data:=public.jk_staff_consultations(p_staff=>'unassigned',p_status=>'all',p_search=>'SYNTHETIC OPERATIONS CONSULTATION');
 if (data->>'count')::int<>1 then raise exception 'FAIL consultation unassigned filter';end if;
 if exists(select 1 from public.jk_consultations where id=c) then raise exception 'FAIL raw consultation policy widened';end if;
 update public.jk_consultations set consultation_note='must not write' where id=c;get diagnostics n=row_count;if n<>0 then raise exception 'FAIL employee consultation write';end if;
 update public.jk_used_device_returns set response_status='반납완료' where ledger_id=l;get diagnostics n=row_count;if n<>0 then raise exception 'FAIL employee used write';end if;
 update public.jk_sales_ledger set affiliate_card_status='완료' where id=l;get diagnostics n=row_count;if n<>0 then raise exception 'FAIL employee affiliate write';end if;
 begin perform public.jk_staff_operations('finance','2099-01-01');raise exception 'FAIL invalid screen';exception when raise_exception then if sqlerrm<>'Invalid screen' then raise;end if;end;
 begin perform public.jk_staff_consultations(p_page=>0);raise exception 'FAIL invalid pagination';exception when raise_exception then if sqlerrm<>'Invalid filters' then raise;end if;end;
end$$;
reset role;
update jk_document_private.access_requests set status='revoked' where user_id=current_setting('test.staff_ops_uid')::uuid;
set local role authenticated;
do $$begin
 begin perform public.jk_staff_operations('used','2099-01-01');raise exception 'FAIL revoked operations allowed';exception when insufficient_privilege then null;end;
 begin perform public.jk_staff_consultations();raise exception 'FAIL revoked consultations allowed';exception when insufficient_privilege then null;end;
end$$;
reset role;
update jk_document_private.access_requests set status='approved',email='different@example.invalid' where user_id=current_setting('test.staff_ops_uid')::uuid;
set local role authenticated;
do $$begin begin perform public.jk_staff_operations('used','2099-01-01');raise exception 'FAIL mismatched identity';exception when insufficient_privilege then null;end;end$$;
reset role;
set local role anon;
do $$begin
 begin perform public.jk_staff_operations('used','2099-01-01');raise exception 'FAIL anonymous operations';exception when insufficient_privilege then null;end;
 begin perform public.jk_staff_consultations();raise exception 'FAIL anonymous consultations';exception when insufficient_privilege then null;end;
end$$;
reset role;
rollback;
select 'PASS: approved operations monthly reads; paginated consultation detail/history/search; pending/revoked/anonymous/identity mismatch denied; no admin/raw table/write expansion; fixtures rolled back' result;
