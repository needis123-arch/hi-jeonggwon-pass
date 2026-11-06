begin;
do $$declare s uuid:=gen_random_uuid();o uuid:=gen_random_uuid();m uuid:=gen_random_uuid();begin
 insert into auth.users(id,email,email_confirmed_at) values(s,s||'@example.invalid',now()),(o,o||'@example.invalid',now()),(m,m||'@example.invalid',now());
 insert into jk_document_private.access_requests(user_id,email,display_name,status) values(s,s||'@example.invalid','SYNTHETIC CAL STAFF','approved'),(o,o||'@example.invalid','SYNTHETIC CAL OTHER','approved'),(m,m||'@example.invalid','SYNTHETIC CAL MANAGER','approved');
 insert into jk_document_private.business_managers(user_id,email) values(m,m||'@example.invalid');
 perform set_config('test.cal_staff',s::text,true);perform set_config('test.cal_other',o::text,true);perform set_config('test.cal_manager',m::text,true);perform set_config('test.cal_task',gen_random_uuid()::text,true);
 perform set_config('request.jwt.claim.sub',m::text,true);perform set_config('request.jwt.claims',json_build_object('sub',m,'is_anonymous',false)::text,true);
end$$;
set local role authenticated;
do $$declare d date:=(now() at time zone 'Asia/Seoul')::date;r jsonb;b jsonb;begin
 r:=public.jk_set_daily_report_assignment(current_setting('test.cal_staff')::uuid,'enabled',false,d,0);
 if not exists(select 1 from jsonb_array_elements(r->'rows') t where t->>'author_id'=current_setting('test.cal_staff') and t->>'required'='false') then raise exception 'FAIL global off';end if;
 perform public.jk_set_daily_report_assignment(current_setting('test.cal_staff')::uuid,'enabled',false,d,0);
 begin perform public.jk_set_daily_report_assignment(current_setting('test.cal_staff')::uuid,'enabled',true,d,0);raise exception 'FAIL stale setting';exception when serialization_failure then null;end;
 perform public.jk_set_daily_report_assignment(current_setting('test.cal_staff')::uuid,'enabled',true,d,1);
 r:=public.jk_set_daily_report_assignment(current_setting('test.cal_staff')::uuid,'day_off',true,d,0);
 if not exists(select 1 from jsonb_array_elements(r->'rows') t where t->>'author_id'=current_setting('test.cal_staff') and t->>'day_off'='true' and t->>'required'='false') then raise exception 'FAIL day off';end if;
 r:=public.jk_daily_report_assignments(d+1);if not exists(select 1 from jsonb_array_elements(r->'rows') t where t->>'author_id'=current_setting('test.cal_staff') and t->>'required'='true') then raise exception 'FAIL next day resumes';end if;
 r:=public.jk_team_calendar(date_trunc('month',d)::date,d);if not exists(select 1 from jsonb_array_elements(r->'days') x where x->>'date'=d::text and (x->>'holiday_count')::int>=1) then raise exception 'FAIL calendar holiday';end if;
 if exists(select 1 from jsonb_array_elements(public.jk_daily_report_reminder()->'pending') t where t->>'author_id'=current_setting('test.cal_staff')) then raise exception 'FAIL off staff reminder';end if;
 r:=public.jk_save_calendar_task(current_setting('test.cal_task')::uuid,d,current_setting('test.cal_staff')::uuid,'SYNTHETIC TASK',false,0);if r->>'author_id'<>current_setting('test.cal_staff') then raise exception 'FAIL manager assignment';end if;
 b:='{"visit":0,"phone":0,"online":0,"flyers_done":false,"reels_filmed":0,"reels_uploaded":0,"completed":"done","tomorrow":"SYNTHETIC TODAY PLAN","shared":"","followups":[]}'::jsonb;
 perform public.jk_save_daily_report(d-1,b,'submitted',0,current_setting('test.cal_staff')::uuid);
end$$;
reset role;
do $$declare d date:=(now() at time zone 'Asia/Seoul')::date;begin
 if exists(select 1 from jk_document_private.daily_report_targets(d) t join auth.users u on u.id=t.author_id where lower(u.email)='needis123@gmail.com' and not exists(select 1 from jk_document_private.daily_report_assignments a where a.author_id=t.author_id) and t.required) then raise exception 'FAIL representative default off';end if;
 if exists(select 1 from jk_document_private.daily_reports where report_date=d and author_id=current_setting('test.cal_staff')::uuid) then raise exception 'FAIL setting auto submitted report';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.cal_staff'),true);perform set_config('request.jwt.claims',json_build_object('sub',current_setting('test.cal_staff'),'is_anonymous',false)::text,true);
end$$;
set local role authenticated;
do $$declare d date:=(now() at time zone 'Asia/Seoul')::date;r jsonb;begin
 r:=public.jk_daily_report_reminder();if (r->>'own_required')::boolean or r->>'own_report_status'<>'missing' or r->>'own_status'<>'submitted' then raise exception 'FAIL personal suppression';end if;
 r:=public.jk_team_calendar(date_trunc('month',d)::date,d);if not exists(select 1 from jsonb_array_elements(r->'plans') t where t->>'text'='SYNTHETIC TODAY PLAN') or not exists(select 1 from jsonb_array_elements(r->'tasks') t where t->>'title'='SYNTHETIC TASK') then raise exception 'FAIL today plans/tasks';end if;
 r:=public.jk_save_calendar_task(current_setting('test.cal_task')::uuid,d,current_setting('test.cal_staff')::uuid,'SYNTHETIC TASK',true,1);if r->>'done'<>'true' then raise exception 'FAIL own complete';end if;
 begin perform public.jk_save_calendar_task(gen_random_uuid(),d,current_setting('test.cal_other')::uuid,'SPOOF',false,0);raise exception 'FAIL other task write';exception when insufficient_privilege then null;end;
 begin perform public.jk_set_daily_report_assignment(current_setting('test.cal_staff')::uuid,'day_off',false,d,1);raise exception 'FAIL employee holiday change';exception when insufficient_privilege then null;end;
 begin perform public.jk_daily_report_assignments(d);raise exception 'FAIL employee management';exception when insufficient_privilege then null;end;
 begin perform 1 from jk_document_private.calendar_tasks;raise exception 'FAIL raw tasks';exception when insufficient_privilege then null;end;
 begin perform 1 from jk_document_private.daily_report_assignments;raise exception 'FAIL raw settings';exception when insufficient_privilege then null;end;
end$$;
reset role;
update jk_document_private.access_requests set status='revoked' where user_id=current_setting('test.cal_staff')::uuid;
set local role authenticated;
do $$begin begin perform public.jk_team_calendar(date_trunc('month',current_date)::date,current_date);raise exception 'FAIL revoked read';exception when insufficient_privilege then null;end;end$$;
reset role;
set local role anon;
do $$begin
 begin perform public.jk_team_calendar(date_trunc('month',current_date)::date,current_date);raise exception 'FAIL anon calendar';exception when insufficient_privilege then null;end;
 begin perform public.jk_daily_report_assignments(current_date);raise exception 'FAIL anon settings';exception when insufficient_privilege then null;end;
end$$;
reset role;
rollback;
select 'PASS: manager ON/OFF and date-specific holidays with version/retry checks; next-day resume; representative default off; no auto-submission; calendar counts/plans/tasks; staff own task completion; read/write isolation and revoked/anonymous denial; synthetic fixtures rolled back' result;
