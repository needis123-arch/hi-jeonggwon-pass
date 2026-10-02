-- Settings-to-public-directory sync and permissions. All fixtures roll back.
begin;
select set_config('request.jwt.claim.sub',(select user_id::text from public.admin_users where active limit 1),true);
set local role authenticated;
insert into public.jk_staff(name) values('__CONSULT_SETTINGS_TEST__');
do $$ begin
 if not exists(select 1 from public.jk_consultation_staff_directory where name='__CONSULT_SETTINGS_TEST__' and active) then raise exception 'staff addition not synchronized';end if;
end $$;
insert into public.jk_consultations(customer_name,phone_digits,staff_name,consultation_note)
 values('SYNTHETIC','01000000000','__CONSULT_SETTINGS_TEST__','SYNTHETIC');
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$begin
 if not exists(select 1 from public.jk_consultation_staff_directory where name='__CONSULT_SETTINGS_TEST__') then raise exception 'public staff missing';end if;
 insert into public.jk_consultations(customer_name,phone_digits,staff_name,services,intake_source,privacy_consent,consent_version)
 values('SYNTHETIC PUBLIC','01000000001','__CONSULT_SETTINGS_TEST__',array['휴대폰'],'고객신청',true,'2026-10-consult-v1');
 begin perform count(*) from public.jk_staff;raise exception 'private staff exposed';exception when insufficient_privilege then null;end;
 begin perform count(*) from public.jk_consultations;raise exception 'private consultations exposed';exception when insufficient_privilege then null;end;
 begin update public.jk_consultation_staff_directory set active=false;raise exception 'public write allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select user_id::text from public.admin_users where active limit 1),true);
set local role authenticated;
update public.jk_staff set active=false where name='__CONSULT_SETTINGS_TEST__';
update public.jk_consultations set consultation_note='Edited after deactivation' where staff_name='__CONSULT_SETTINGS_TEST__';
do $$begin
 if (select count(*) from public.jk_consultations where staff_name='__CONSULT_SETTINGS_TEST__')<>2 then raise exception 'historical assignment lost';end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$begin
 if exists(select 1 from public.jk_consultation_staff_directory where name='__CONSULT_SETTINGS_TEST__') then raise exception 'inactive staff exposed';end if;
 begin
 insert into public.jk_consultations(customer_name,phone_digits,staff_name,services,intake_source,privacy_consent,consent_version)
 values('STALE PUBLIC','01000000002','__CONSULT_SETTINGS_TEST__',array['휴대폰'],'고객신청',true,'2026-10-consult-v1');
 raise exception 'inactive assignment allowed';exception when check_violation then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select user_id::text from public.admin_users where active limit 1),true);
set local role authenticated;
update public.jk_staff set active=true where name='__CONSULT_SETTINGS_TEST__';
do $$begin
 if not exists(select 1 from public.jk_consultation_staff_directory where name='__CONSULT_SETTINGS_TEST__' and active) then raise exception 'reactivation not synchronized';end if;
end $$;
rollback;
select 'PASS: settings add/deactivate/reactivate, public names only, dynamic public assignment, inactive history preserved, stale assignment rejected; rolled back' as result;
