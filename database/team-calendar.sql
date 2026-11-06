create table jk_document_private.calendar_tasks(
 id uuid primary key,task_date date not null,author_id uuid not null references auth.users(id),author_name text not null,
 title text not null check(length(trim(title)) between 1 and 1000),done boolean not null default false,revision integer not null default 1,
 created_by uuid not null references auth.users(id),updated_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index calendar_tasks_date_idx on jk_document_private.calendar_tasks(task_date);
create index calendar_tasks_open_idx on jk_document_private.calendar_tasks(task_date) where not done;
alter table jk_document_private.calendar_tasks enable row level security;
revoke all on jk_document_private.calendar_tasks from public,anon,authenticated;

create function public.jk_save_calendar_task(p_id uuid,p_date date,p_author_id uuid,p_title text,p_done boolean,p_expected_revision integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_old jk_document_private.calendar_tasks;v_saved jk_document_private.calendar_tasks;v_name text;
begin
 if auth.uid() is null or not coalesce(jk_document_private.can_read(),false) then raise exception '직원 승인이 필요합니다.' using errcode='42501';end if;
 if p_author_id is null or (p_author_id<>auth.uid() and not public.jk_business_can_manage()) then raise exception '본인의 할 일만 변경할 수 있습니다.' using errcode='42501';end if;
 if p_id is null or p_date is null or p_date<date '2020-01-01' or p_date>(now() at time zone 'Asia/Seoul')::date+366 or p_title is null or length(trim(p_title)) not between 1 and 1000 or p_done is null or p_expected_revision is null or p_expected_revision<0 then raise exception '날짜·담당자·할 일을 확인하세요.';end if;
 perform pg_advisory_xact_lock(hashtextextended('calendar-task:'||p_id::text,0));
 select * into v_old from jk_document_private.calendar_tasks where id=p_id for update;
 if v_old.id is not null and (v_old.author_id<>p_author_id or v_old.task_date<>p_date) then raise exception '기존 할 일의 담당자·날짜를 변경할 수 없습니다.';end if;
 if coalesce(v_old.revision,0)<>p_expected_revision then
  if v_old.title=trim(p_title) and v_old.done=p_done then return to_jsonb(v_old);end if;
  raise exception '다른 화면에서 할 일을 변경했습니다. 새로고침 후 확인하세요.' using errcode='40001';
 end if;
 select author_name into v_name from jk_document_private.daily_report_roster() where author_id=p_author_id;
 v_name:=coalesce(v_name,v_old.author_name);if v_name is null then raise exception '승인된 담당자를 확인하세요.';end if;
 insert into jk_document_private.calendar_tasks(id,task_date,author_id,author_name,title,done,created_by,updated_by)
 values(p_id,p_date,p_author_id,v_name,trim(p_title),p_done,auth.uid(),auth.uid())
 on conflict(id) do update set title=excluded.title,done=excluded.done,revision=jk_document_private.calendar_tasks.revision+1,updated_at=now(),updated_by=auth.uid() returning * into v_saved;
 return to_jsonb(v_saved);
end$$;
revoke all on function public.jk_save_calendar_task(uuid,date,uuid,text,boolean,integer) from public,anon;
grant execute on function public.jk_save_calendar_task(uuid,date,uuid,text,boolean,integer) to authenticated;

create function public.jk_team_calendar(p_month date,p_date date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_today date:=(now() at time zone 'Asia/Seoul')::date;v_end date;v_roster jsonb;v_days jsonb;v_tasks jsonb;v_plans jsonb;v_consults jsonb;v_task_count integer;v_consult_count integer;
begin
 if auth.uid() is null or not coalesce(jk_document_private.can_read(),false) then raise exception '직원 승인이 필요합니다.' using errcode='42501';end if;
 if p_month is null or p_date is null or p_month<>date_trunc('month',p_month)::date or p_month<date '2020-01-01' or p_date<p_month or p_date>=(p_month+interval '1 month')::date or p_date>v_today+366 then raise exception '일정 날짜를 확인하세요.';end if;
 v_end:=(p_month+interval '1 month')::date;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.author_name),'[]') into v_roster from jk_document_private.daily_report_targets(p_date) r;
 select coalesce(jsonb_agg(jsonb_build_object('date',d.dt,'holiday_count',(select count(*) from jk_document_private.daily_report_days_off o join jk_document_private.daily_report_roster() r on r.author_id=o.author_id where o.report_date=d.dt and o.day_off),
 'task_count',(select count(*) from jk_document_private.calendar_tasks t where t.task_date=d.dt and not t.done),
 'contact_count',(select count(*) from public.jk_consultations c where c.next_contact_on=d.dt and c.status in ('상담전','상담중','재연락','방문예정'))) order by d.dt),'[]') into v_days
 from (select generate_series(p_month::timestamp,(v_end-1)::timestamp,interval '1 day')::date dt) d;
 select count(*) into v_task_count from jk_document_private.calendar_tasks where task_date=p_date or(p_date=v_today and task_date<p_date and not done);
 select coalesce(jsonb_agg(to_jsonb(t) order by t.done,t.task_date,t.created_at),'[]') into v_tasks from(select * from jk_document_private.calendar_tasks where task_date=p_date or(p_date=v_today and task_date<p_date and not done) order by done,task_date,created_at limit 200)t;
 select coalesce(jsonb_agg(jsonb_build_object('author_id',r.author_id,'author_name',r.author_name,'text',r.body->>'tomorrow') order by r.author_name),'[]') into v_plans from jk_document_private.daily_reports r
 where r.report_date=p_date-1 and r.report_status='submitted' and trim(coalesce(r.body->>'tomorrow','')) not in ('','없음','없습니다','해당없음');
 select count(*) into v_consult_count from public.jk_consultations c where c.status in ('상담전','상담중','재연락','방문예정') and(c.next_contact_on=p_date or(p_date=v_today and c.next_contact_on<p_date));
 select coalesce(jsonb_agg(to_jsonb(c) order by c.next_contact_on,c.customer_name),'[]') into v_consults from(select id,customer_name,staff_name,next_contact_on,status,left(coalesce(consultation_note,customer_note,''),500) note from public.jk_consultations c
 where c.status in ('상담전','상담중','재연락','방문예정') and(c.next_contact_on=p_date or(p_date=v_today and c.next_contact_on<p_date)) order by next_contact_on,customer_name limit 100)c;
 return jsonb_build_object('month',p_month,'date',p_date,'user_id',auth.uid(),'can_manage',public.jk_business_can_manage(),'roster',v_roster,'days',v_days,'tasks',v_tasks,'task_count',v_task_count,'plans',v_plans,'consultations',v_consults,'consultation_count',v_consult_count);
end$$;
revoke all on function public.jk_team_calendar(date,date) from public,anon;
grant execute on function public.jk_team_calendar(date,date) to authenticated;
