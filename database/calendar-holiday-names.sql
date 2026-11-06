CREATE OR REPLACE FUNCTION public.jk_team_calendar(p_month date, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_today date:=(now() at time zone 'Asia/Seoul')::date;v_end date;v_roster jsonb;v_days jsonb;v_tasks jsonb;v_plans jsonb;v_consults jsonb;v_task_count integer;v_consult_count integer;
begin
 if auth.uid() is null or not coalesce(jk_document_private.can_read(),false) then raise exception '직원 승인이 필요합니다.' using errcode='42501';end if;
 if p_month is null or p_date is null or p_month<>date_trunc('month',p_month)::date or p_month<date '2020-01-01' or p_date<p_month or p_date>=(p_month+interval '1 month')::date or p_date>v_today+366 then raise exception '일정 날짜를 확인하세요.';end if;
 v_end:=(p_month+interval '1 month')::date;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.author_name),'[]') into v_roster from jk_document_private.daily_report_targets(p_date) r;
 select coalesce(jsonb_agg(jsonb_build_object('date',d.dt,'holiday_count',(select count(*) from jk_document_private.daily_report_days_off o join jk_document_private.daily_report_roster() r on r.author_id=o.author_id where o.report_date=d.dt and o.day_off),
 'holiday_names',(select coalesce(jsonb_agg(r.author_name order by r.author_name),'[]'::jsonb) from jk_document_private.daily_report_days_off o join jk_document_private.daily_report_roster() r on r.author_id=o.author_id where o.report_date=d.dt and o.day_off),
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
end$function$
