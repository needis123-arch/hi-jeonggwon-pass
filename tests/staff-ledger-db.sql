-- Synthetic fixtures only; the entire transaction is rolled back.
begin;
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-4000-8000-000000000881','staff-ledger-test@example.invalid',now());
insert into jk_document_private.access_requests(user_id,email,display_name,status)
values('00000000-0000-4000-8000-000000000881','staff-ledger-test@example.invalid','합성 장부 테스트','pending');
insert into public.jk_sales_ledger(id,activation_date,customer_name_snapshot,customer_phone_snapshot,base_rebate,cash_sale_amount,cash_received)
values('00000000-0000-4000-8000-000000000882','2099-01-20','합성 장부 테스트 고객','01000000000',170000,319000,319000);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000881',true);
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000881","is_anonymous":false,"role":"authenticated"}',true);
set local role authenticated;
do $$begin
 begin perform public.jk_staff_ledger('2099-01-01');raise exception 'pending user allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
update jk_document_private.access_requests set status='approved' where user_id='00000000-0000-4000-8000-000000000881';
set local role authenticated;
do $$declare v jsonb; n integer; begin
 if public.is_admin() then raise exception 'staff became admin';end if;
 v:=public.jk_staff_ledger('2099-01-01');
 if not exists(select 1 from jsonb_array_elements(v->'rows') r where r->>'id'='00000000-0000-4000-8000-000000000882' and (r->>'final_margin')::bigint=170000) then raise exception 'approved monthly ledger unavailable';end if;
 if exists(select 1 from jsonb_array_elements(public.jk_staff_ledger('2099-02-01')->'rows') r where r->>'id'='00000000-0000-4000-8000-000000000882') then raise exception 'month filter leaked row';end if;
 if exists(select 1 from jsonb_array_elements(v->'rows') r where r ? 'created_by' or r ? 'customer_id' or r ? 'identifier_masked') then raise exception 'unnecessary fields exposed';end if;
 if exists(select 1 from public.jk_sales_ledger where id='00000000-0000-4000-8000-000000000882') then raise exception 'raw table policy broadened';end if;
 update public.jk_sales_ledger set memo='must not write' where id='00000000-0000-4000-8000-000000000882';get diagnostics n=row_count;if n<>0 then raise exception 'staff updated ledger';end if;
 delete from public.jk_sales_ledger where id='00000000-0000-4000-8000-000000000882';get diagnostics n=row_count;if n<>0 then raise exception 'staff deleted ledger';end if;
 begin insert into public.jk_sales_ledger(activation_date,customer_name_snapshot) values('2099-01-21','must not insert');raise exception 'staff inserted ledger';exception when insufficient_privilege then null;end;
 begin perform public.jk_document_access_requests();raise exception 'staff read approval directory';exception when insufficient_privilege then null;end;
 begin perform public.jk_staff_ledger(null);raise exception 'null month accepted';exception when raise_exception then if sqlerrm<>'Invalid month' then raise;end if;end;
end $$;
reset role;
update jk_document_private.access_requests set status='revoked' where user_id='00000000-0000-4000-8000-000000000881';
set local role authenticated;
do $$begin begin perform public.jk_staff_ledger('2099-01-01');raise exception 'revoked user allowed';exception when insufficient_privilege then null;end;end $$;
reset role;
update jk_document_private.access_requests set status='approved',email='different@example.invalid' where user_id='00000000-0000-4000-8000-000000000881';
set local role authenticated;
do $$begin begin perform public.jk_staff_ledger('2099-01-01');raise exception 'identity mismatch allowed';exception when insufficient_privilege then null;end;end $$;
reset role;
set local role anon;
do $$begin begin perform public.jk_staff_ledger('2099-01-01');raise exception 'anonymous user allowed';exception when insufficient_privilege then null;end;end $$;
reset role;
rollback;
select 'PASS: pending/revoked/anonymous/identity mismatch denied, approved month read, unchanged admin and raw table writes, no saved fixtures' as validation;
