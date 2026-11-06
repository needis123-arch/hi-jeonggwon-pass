-- Notification participation only. Does not grant access or submit/change reports.
create table jk_document_private.daily_report_assignments(
 author_id uuid primary key references auth.users(id),enabled boolean not null,
 revision integer not null default 1,updated_at timestamptz not null default now(),updated_by uuid not null references auth.users(id)
);
create table jk_document_private.daily_report_days_off(
 author_id uuid not null references auth.users(id),report_date date not null,day_off boolean not null,
 revision integer not null default 1,updated_at timestamptz not null default now(),updated_by uuid not null references auth.users(id),primary key(author_id,report_date)
);
alter table jk_document_private.daily_report_assignments enable row level security;
alter table jk_document_private.daily_report_days_off enable row level security;
revoke all on jk_document_private.daily_report_assignments,jk_document_private.daily_report_days_off from public,anon,authenticated;

create function jk_document_private.daily_report_targets(p_date date)
returns table(author_id uuid,author_name text,enabled boolean,day_off boolean,required boolean,enabled_revision integer,day_off_revision integer)
language sql stable security definer set search_path='' as $$
 select r.author_id,r.author_name,coalesce(a.enabled,lower(u.email)<>'needis123@gmail.com'),coalesce(d.day_off,false),
 coalesce(a.enabled,lower(u.email)<>'needis123@gmail.com') and not coalesce(d.day_off,false),coalesce(a.revision,0),coalesce(d.revision,0)
 from jk_document_private.daily_report_roster() r join auth.users u on u.id=r.author_id
 left join jk_document_private.daily_report_assignments a on a.author_id=r.author_id
 left join jk_document_private.daily_report_days_off d on d.author_id=r.author_id and d.report_date=p_date;
$$;
revoke all on function jk_document_private.daily_report_targets(date) from public,anon,authenticated;

create function public.jk_daily_report_assignments(p_date date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_rows jsonb;
begin
 if auth.uid() is null or not coalesce(jk_document_private.can_read(),false) or not coalesce(public.jk_business_can_manage(),false) then raise exception '관리자만 알림 대상을 설정할 수 있습니다.' using errcode='42501';end if;
 if p_date is null or p_date<date '2020-01-01' or p_date>(now() at time zone 'Asia/Seoul')::date+366 then raise exception '설정 날짜를 확인하세요.';end if;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.author_name),'[]') into v_rows from jk_document_private.daily_report_targets(p_date) t;
 return jsonb_build_object('report_date',p_date,'rows',v_rows);
end$$;
revoke all on function public.jk_daily_report_assignments(date) from public,anon;
grant execute on function public.jk_daily_report_assignments(date) to authenticated;

create function public.jk_set_daily_report_assignment(p_author_id uuid,p_kind text,p_value boolean,p_date date,p_expected_revision integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_revision integer;v_value boolean;
begin
 if auth.uid() is null or not coalesce(jk_document_private.can_read(),false) or not coalesce(public.jk_business_can_manage(),false) then raise exception '관리자만 알림 대상을 설정할 수 있습니다.' using errcode='42501';end if;
 if p_author_id is null or not exists(select 1 from jk_document_private.daily_report_roster() r where r.author_id=p_author_id) then raise exception '승인된 담당자를 확인하세요.';end if;
 if p_kind is null or p_kind not in ('enabled','day_off') or p_value is null or p_expected_revision is null or p_expected_revision<0 then raise exception '설정값을 확인하세요.';end if;
 if p_date is null or p_date<date '2020-01-01' or p_date>(now() at time zone 'Asia/Seoul')::date+366 then raise exception '설정 날짜를 확인하세요.';end if;
 perform pg_advisory_xact_lock(hashtextextended('closing-setting:'||p_author_id::text||':'||p_kind||case when p_kind='day_off' then p_date::text else '' end,0));
 if p_kind='enabled' then
  select revision,enabled into v_revision,v_value from jk_document_private.daily_report_assignments where author_id=p_author_id for update;
 else
  select revision,day_off into v_revision,v_value from jk_document_private.daily_report_days_off where author_id=p_author_id and report_date=p_date for update;
 end if;
 if coalesce(v_revision,0)<>p_expected_revision then
  if v_value=p_value then return public.jk_daily_report_assignments(p_date);end if;
  raise exception '다른 화면에서 알림 설정을 변경했습니다. 새로고침 후 다시 확인하세요.' using errcode='40001';
 end if;
 if p_kind='enabled' then
  insert into jk_document_private.daily_report_assignments(author_id,enabled,updated_by) values(p_author_id,p_value,auth.uid())
  on conflict(author_id) do update set enabled=excluded.enabled,revision=jk_document_private.daily_report_assignments.revision+1,updated_at=now(),updated_by=auth.uid();
 else
  insert into jk_document_private.daily_report_days_off(author_id,report_date,day_off,updated_by) values(p_author_id,p_date,p_value,auth.uid())
  on conflict(author_id,report_date) do update set day_off=excluded.day_off,revision=jk_document_private.daily_report_days_off.revision+1,updated_at=now(),updated_by=auth.uid();
 end if;
 return public.jk_daily_report_assignments(p_date);
end$$;
revoke all on function public.jk_set_daily_report_assignment(uuid,text,boolean,date,integer) from public,anon;
grant execute on function public.jk_set_daily_report_assignment(uuid,text,boolean,date,integer) to authenticated;

create or replace function public.jk_daily_report_data(p_date date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_roster jsonb;v_reports jsonb;
begin
 if auth.uid() is null or not coalesce(jk_document_private.can_read(),false) then raise exception '직원 승인이 필요합니다.' using errcode='42501';end if;
 if p_date is null or p_date<date '2020-01-01' or p_date>(now() at time zone 'Asia/Seoul')::date then raise exception '오늘 또는 지난 날짜를 선택하세요.';end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.author_name),'[]') into v_roster from jk_document_private.daily_report_targets(p_date) r;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.author_name),'[]') into v_reports from jk_document_private.daily_reports r where r.report_date=p_date;
 return jsonb_build_object('report_date',p_date,'user_id',auth.uid(),'can_manage',public.jk_business_can_manage(),'roster',v_roster,'reports',v_reports);
end$$;

create or replace function public.jk_daily_report_reminder() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_date date:=(now() at time zone 'Asia/Seoul')::date;v_status text;v_pending jsonb:='[]';v_manage boolean;v_own record;
begin
 if auth.uid() is null or not coalesce(jk_document_private.can_read(),false) then raise exception '직원 승인이 필요합니다.' using errcode='42501';end if;
 v_manage:=public.jk_business_can_manage();
 select * into v_own from jk_document_private.daily_report_targets(v_date) where author_id=auth.uid();
 select report_status into v_status from jk_document_private.daily_reports where report_date=v_date and author_id=auth.uid();
 if v_manage then
  select coalesce(jsonb_agg(jsonb_build_object('author_id',p.author_id,'author_name',p.author_name,'status',coalesce(r.report_status,'missing')) order by p.author_name),'[]') into v_pending
  from jk_document_private.daily_report_targets(v_date) p left join jk_document_private.daily_reports r on r.author_id=p.author_id and r.report_date=v_date
  where p.required and r.report_status is distinct from 'submitted';
 end if;
 -- own_status remains the effective reminder status for older installed clients;
 -- no report is created/submitted when an author is exempt.
 return jsonb_build_object('report_date',v_date,'user_id',auth.uid(),'own_status',case when coalesce(v_own.required,false) then coalesce(v_status,'missing') else 'submitted' end,
 'own_report_status',coalesce(v_status,'missing'),'own_required',coalesce(v_own.required,false),'own_day_off',coalesce(v_own.day_off,false),'own_enabled',coalesce(v_own.enabled,false),'can_manage',v_manage,'pending',v_pending);
end$$;
