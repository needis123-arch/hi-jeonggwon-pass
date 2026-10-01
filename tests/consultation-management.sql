-- Functional and authorization checks. All test data is rolled back.
begin;
set local role anon;
do $test$
begin
 insert into public.jk_consultations(public_request_key,customer_name,phone_digits,staff_name,services,intake_source,privacy_consent,consent_version,customer_note)
 values('e0000000-0000-4000-8000-000000000001','검증용 공개신청','010-0000-0000','송훈',array['휴대폰'],'고객신청',true,'2026-10-consult-v1','테스트 문의');
 begin
  insert into public.jk_consultations(customer_name,phone_digits,services,intake_source,privacy_consent,consent_version)
  values('동의 없는 신청','01000000001',array['휴대폰'],'고객신청',false,'2026-10-consult-v1');
  raise exception 'consent-free intake accepted';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.jk_consultations(customer_name,phone_digits,services,intake_source,privacy_consent,consent_version,status)
  values('위조 상태','01000000002',array['휴대폰'],'고객신청',true,'2026-10-consult-v1','계약완료');
  raise exception 'public management field accepted';
 exception when insufficient_privilege then null; end;
 begin perform count(*) from public.jk_consultations;raise exception 'anonymous read allowed';exception when insufficient_privilege then null;end;
 begin update public.jk_consultations set customer_name='위조';raise exception 'anonymous update allowed';exception when insufficient_privilege then null;end;
 begin perform count(*) from public.jk_consultation_history;raise exception 'anonymous history read allowed';exception when insufficient_privilege then null;end;
 begin
  insert into public.jk_consultations(public_request_key,customer_name,phone_digits,services,intake_source,privacy_consent,consent_version)
  values('e0000000-0000-4000-8000-000000000001','재시도','01000000000',array['휴대폰'],'고객신청',true,'2026-10-consult-v1');
  raise exception 'retry generated duplicate';
 exception when unique_violation then null; end;
end $test$;
reset role;
do $test$
declare r public.jk_consultations%rowtype;today date:=(now() at time zone 'Asia/Seoul')::date;
begin
 select * into r from public.jk_consultations where public_request_key='e0000000-0000-4000-8000-000000000001';
 if r.phone_digits<>'01000000000' or r.staff_name<>'송훈' or r.status<>'상담전' or r.next_contact_on<>today or r.consented_at is null then raise exception 'public intake defaults wrong';end if;
end $test$;
select set_config('request.jwt.claim.sub',(select user_id::text from public.admin_users where active limit 1),true);
set local role authenticated;
do $test$
declare fixture uuid;today date:=(now() at time zone 'Asia/Seoul')::date;
begin
 insert into public.jk_consultations(customer_name,phone_digits,staff_name,consulted_on,visited_on,followup_days,next_contact_on,status,consultation_note)
 values('검증용 상담','01000000003','인성',today-7,today-5,3,null,'재연락','놓친 고객 기록') returning id into fixture;
 if (select next_contact_on from public.jk_consultations where id=fixture)<>today-2 then raise exception '3-day visit-based schedule wrong';end if;
 if (select count(*) from public.jk_consultation_history where consultation_id=fixture)<>1 then raise exception 'initial history missing';end if;
 if not exists(select 1 from public.jk_consultations where id=fixture and next_contact_on<=today and status not in ('계약완료','종료')) then raise exception 'overdue reminder missing';end if;
 update public.jk_consultations set last_contacted_on=today,last_contacted_at=clock_timestamp(),last_contact_note='연락 시도',followup_days=5,next_contact_on=today+5 where id=fixture;
 if (select next_contact_on from public.jk_consultations where id=fixture)<>today+5 then raise exception '5-day reschedule wrong';end if;
 if (select count(*) from public.jk_consultation_history where consultation_id=fixture and action='재연락 기록')<>1 then raise exception 'contact history missing';end if;
 update public.jk_consultations set last_contacted_at=clock_timestamp() where id=fixture;
 if (select count(*) from public.jk_consultation_history where consultation_id=fixture and action='재연락 기록')<>2 then raise exception 'same-day repeated contact lost';end if;
 update public.jk_consultations set staff_name='송훈',followup_days=4,next_contact_on=today+4 where id=fixture;
 if (select staff_name from public.jk_consultations where id=fixture)<>'송훈' then raise exception 'reassignment failed';end if;
 update public.jk_consultations set status='계약완료' where id=fixture;
 if (select next_contact_on from public.jk_consultations where id=fixture) is not null then raise exception 'completed reminder retained';end if;
 update public.jk_consultations set status='재연락' where id=fixture;
 if (select next_contact_on from public.jk_consultations where id=fixture) is null then raise exception 'reopened reminder missing';end if;
 begin update public.jk_consultations set followup_days=2 where id=fixture;raise exception '2-day interval accepted';exception when check_violation then null;end;
 begin update public.jk_consultations set phone_digits='123' where id=fixture;raise exception 'invalid phone accepted';exception when check_violation then null;end;
end $test$;
reset role;
select set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
set local role authenticated;
do $test$
begin
 if (select count(*) from public.jk_consultations)<>0 then raise exception 'nonadmin data exposed';end if;
 if (select count(*) from public.jk_consultation_history)<>0 then raise exception 'nonadmin history exposed';end if;
 begin
 insert into public.jk_consultations(customer_name,phone_digits,consultation_note) values('위조 직원','01000000004','위조 메모');
 raise exception 'nonadmin management insert allowed';
 exception when insufficient_privilege then null;end;
end $test$;
rollback;
select 'PASS: public intake/consent/idempotency, 3/4/5-day schedules, contact history, reassignment, completion/reopen, phone checks, anonymous/nonadmin isolation; fixtures rolled back' as result;
