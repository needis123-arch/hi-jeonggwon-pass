begin;
do $$declare s uuid:=gen_random_uuid();m uuid:=gen_random_uuid();l uuid:=gen_random_uuid();begin
 insert into auth.users(id,email,email_confirmed_at) values(s,s||'@example.invalid',now()),(m,m||'@example.invalid',now());
 insert into jk_document_private.access_requests(user_id,email,display_name,status) values(s,s||'@example.invalid','SYNTHETIC STAFF','approved'),(m,m||'@example.invalid','SYNTHETIC MANAGER','approved');
 insert into jk_document_private.business_managers(user_id,email) values(m,m||'@example.invalid');
 insert into public.jk_sales_ledger(id,activation_date,customer_name_snapshot,customer_phone_snapshot,base_rebate) values(l,current_date,'SYNTHETIC MANAGER LEDGER','01000000000',100000);
 perform set_config('test.create_staff',s::text,true);perform set_config('test.create_manager',m::text,true);perform set_config('test.create_ledger',l::text,true);
 perform set_config('request.jwt.claim.sub',s::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',s,'role','authenticated','is_anonymous',false)::text,true);
end$$;
set local role authenticated;
do $$declare payload jsonb;key uuid:=gen_random_uuid();result jsonb;id uuid;n integer;today date:=(now() at time zone 'Asia/Seoul')::date;begin
 if public.jk_business_can_manage() or public.is_admin() then raise exception 'FAIL ordinary employee administrator';end if;
 payload:=jsonb_build_object('customer_name','SYNTHETIC NEW CONSULTATION','phone_digits','01012345678','staff_name',null,'services',jsonb_build_array('휴대폰'),'contact_method','방문','consulted_on',today,'visited_on',today,'followup_days',3,'next_contact_on',today+3,'status','재연락','consultation_note','SYNTHETIC CUSTOMER NOTE');
 result:=public.jk_staff_create_consultation(payload,key);id:=(result->>'id')::uuid;perform set_config('test.created_consultation',id::text,true);
 if (public.jk_staff_create_consultation(payload,key)->>'id')::uuid<>id then raise exception 'FAIL duplicate request';end if;
 result:=public.jk_staff_consultations(p_id=>id);
 if result->'rows'->0->>'consultation_note'<>'SYNTHETIC CUSTOMER NOTE' or jsonb_array_length(result->'history')<>1 or result->'history'->0->>'action'<>'직원 상담 등록' then raise exception 'FAIL created row/audit';end if;
 begin perform public.jk_staff_create_consultation(payload||'{"id":"00000000-0000-4000-8000-000000000001"}',gen_random_uuid());raise exception 'FAIL extra field accepted';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.jk_staff_create_consultation(payload||'{"consultation_note":"CHANGED"}',key);raise exception 'FAIL changed retry accepted';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 update public.jk_consultations set consultation_note='must not update' where jk_consultations.id=current_setting('test.created_consultation')::uuid;get diagnostics n=row_count;if n<>0 then raise exception 'FAIL employee edited existing';end if;
 update public.jk_sales_ledger set base_rebate=300000 where jk_sales_ledger.id=current_setting('test.create_ledger')::uuid;get diagnostics n=row_count;if n<>0 then raise exception 'FAIL employee edited ledger';end if;
end$$;
reset role;
do $$begin perform set_config('request.jwt.claim.sub',current_setting('test.create_manager'),true);perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.create_manager'),'role','authenticated','is_anonymous',false)::text,true);end$$;
set local role authenticated;
do $$declare state jsonb;n integer;begin
 if public.is_admin() then raise exception 'FAIL global admin expanded';end if;
 if not public.jk_business_can_manage() then raise exception 'FAIL manager denied';end if;
 state:=public.jk_document_access_state();if not (state->>'owner')::boolean or (state->>'storage_owner')::boolean then raise exception 'FAIL business manager/storage owner distinction';end if;
 update public.jk_sales_ledger set base_rebate=200000 where id=current_setting('test.create_ledger')::uuid;get diagnostics n=row_count;
 if n<>1 or (select final_margin from public.jk_sales_ledger where id=current_setting('test.create_ledger')::uuid)<>180000 then raise exception 'FAIL manager ledger save';end if;
 if public.jk_internal_settlement_data(date_trunc('month',current_date)::date,current_date) is null then raise exception 'FAIL manager finance screen';end if;
 update public.jk_consultations set consultation_note='SYNTHETIC MANAGER EDIT' where id=current_setting('test.created_consultation')::uuid;get diagnostics n=row_count;if n<>1 then raise exception 'FAIL manager consultation edit';end if;
end$$;
reset role;
update jk_document_private.access_requests set status='revoked' where user_id in(current_setting('test.create_manager')::uuid,current_setting('test.create_staff')::uuid);
set local role authenticated;
do $$begin
 if public.jk_business_can_manage() then raise exception 'FAIL revoked manager';end if;
 begin perform public.jk_staff_create_consultation('{}',gen_random_uuid());raise exception 'FAIL revoked create';exception when insufficient_privilege then null;end;
end$$;
reset role;
set local role anon;
do $$begin
 if public.jk_business_can_manage() then raise exception 'FAIL anonymous manager';end if;
 begin perform public.jk_staff_create_consultation('{}',gen_random_uuid());raise exception 'FAIL anonymous create';exception when insufficient_privilege then null;end;
end$$;
reset role;
rollback;
select 'PASS: approved staff create with idempotent retry and audit; no existing-row/ledger writes; scoped manager ledger/finance/consultation permissions; global admin and Drive ownership unchanged; revoked/anonymous denied; fixtures rolled back' result;
