-- Synthetic fixtures; run in the isolated local database and roll everything back.
insert into auth.users(id) values('00000000-0000-4000-8000-000000000099');
insert into public.admin_users(user_id,name) values('00000000-0000-4000-8000-000000000099','합성 서류 관리자');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
insert into public.jk_sales_ledger(id,activation_date,customer_name_snapshot,customer_phone_snapshot)
values('00000000-0000-4000-8000-000000000098',current_date,'합성 서류 고객','01000000000');
set local role authenticated;
insert into public.jk_ledger_documents(id,ledger_id,storage_path,doc_kind,byte_size)
values('00000000-0000-4000-8000-000000000097','00000000-0000-4000-8000-000000000098','00000000-0000-4000-8000-000000000098/00000000-0000-4000-8000-000000000097.jkdoc','신분증 사본',100);
insert into storage.objects(id,bucket_id,name)
values('00000000-0000-4000-8000-000000000096','jk-ledger-documents','00000000-0000-4000-8000-000000000098/00000000-0000-4000-8000-000000000097.jkdoc');
do $$begin
 if (select count(*) from public.jk_ledger_documents)<>1 then raise exception 'admin metadata read failed';end if;
 if not exists(select 1 from storage.objects where bucket_id='jk-ledger-documents') then raise exception 'admin storage read failed';end if;
 begin delete from public.jk_sales_ledger where id='00000000-0000-4000-8000-000000000098';raise exception 'ledger with document was deleted';exception when foreign_key_violation then null;end;
 begin insert into public.jk_ledger_documents(id,ledger_id,storage_path,doc_kind,byte_size) values(gen_random_uuid(),'00000000-0000-4000-8000-000000000098','wrong/path','기타 서류',100);raise exception 'wrong path accepted';exception when check_violation then null;end;
 begin insert into storage.objects(id,bucket_id,name) values(gen_random_uuid(),'jk-ledger-documents','00000000-0000-4000-8000-000000000001/00000000-0000-4000-8000-000000000097.jkdoc');raise exception 'missing ledger upload accepted';exception when insufficient_privilege then null;end;
end $$;
reset role;
-- Deliberately broad LOCAL-ONLY policy proves the restrictive bucket guard works.
create policy synthetic_broad_read on storage.objects for select to public using(true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000095',true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.jk_ledger_documents) then raise exception 'ordinary user metadata exposure';end if;
 if exists(select 1 from storage.objects where bucket_id='jk-ledger-documents') then raise exception 'ordinary user storage exposure';end if;
 begin insert into public.jk_ledger_documents(id,ledger_id,storage_path,doc_kind,byte_size) values('00000000-0000-4000-8000-000000000094','00000000-0000-4000-8000-000000000098','00000000-0000-4000-8000-000000000098/00000000-0000-4000-8000-000000000094.jkdoc','기타 서류',100);raise exception 'ordinary insert accepted';exception when insufficient_privilege then null;end;
 delete from public.jk_ledger_documents;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$begin
 if exists(select 1 from storage.objects where bucket_id='jk-ledger-documents') then raise exception 'anonymous storage exposure';end if;
 begin perform 1 from public.jk_ledger_documents;raise exception 'anonymous metadata exposure';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
set local role authenticated;
delete from storage.objects where bucket_id='jk-ledger-documents';
delete from public.jk_ledger_documents;
delete from public.jk_sales_ledger where id='00000000-0000-4000-8000-000000000098';
reset role;
select 'PASS: private encrypted bucket, admin-only RLS, anon/non-admin denial, strict paths, ledger deletion guard and admin removal' as validation;
