create or replace function public.jk_save_daily_report(p_date date,p_body jsonb,p_status text,p_expected_version integer,p_author_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_author uuid:=coalesce(p_author_id,auth.uid());v_name text;v_old jk_document_private.daily_reports;v_saved jk_document_private.daily_reports;
 v_body jsonb;v_key text;v_n integer;v_item jsonb;v_followups jsonb:='[]';v_when timestamp;
begin
 if auth.uid() is null or not coalesce(jk_document_private.can_read(),false) then raise exception '직원 승인이 필요합니다.' using errcode='42501';end if;
 if v_author<>auth.uid() and not public.jk_business_can_manage() then raise exception '본인의 마감보고만 수정할 수 있습니다.' using errcode='42501';end if;
 if p_date is null or p_date<date '2020-01-01' or p_date>(now() at time zone 'Asia/Seoul')::date then raise exception '오늘 또는 지난 날짜를 선택하세요.';end if;
 if p_status is null or p_status not in ('draft','submitted') or p_expected_version is null or p_expected_version<0 then raise exception '저장 상태를 확인하세요.';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>120000 then raise exception '보고 내용을 확인하세요.';end if;
 if exists(select 1 from jsonb_object_keys(p_body) k where k not in ('visit','phone','online','flyers','flyers_done','reels_filmed','reels_uploaded','completed','tomorrow','shared','followups')) then raise exception '허용되지 않은 입력항목입니다.';end if;
 v_body:='{}';
 foreach v_key in array array['visit','phone','online','reels_filmed','reels_uploaded'] loop
  if jsonb_typeof(p_body->v_key) is distinct from 'number' or (p_body->>v_key)!~'^[0-9]{1,5}$' then raise exception '팀 수와 업무 수량은 0 이상의 정수로 입력하세요.';end if;
  v_n:=(p_body->>v_key)::integer;if v_n>10000 then raise exception '입력 수량을 확인하세요.';end if;
  v_body:=v_body||jsonb_build_object(v_key,v_n);
 end loop;

 -- Keep old clients readable while new clients record a yes/no choice only.
 if p_body ? 'flyers_done' then
  if jsonb_typeof(p_body->'flyers_done') not in ('boolean','null') then raise exception '전단지 배포 여부를 선택하세요.';end if;
  v_body:=v_body||jsonb_build_object('flyers_done',p_body->'flyers_done');
 elsif jsonb_typeof(p_body->'flyers')='number' and (p_body->>'flyers')~'^[0-9]{1,5}$' and (p_body->>'flyers')::integer<=10000 then
  v_body:=v_body||jsonb_build_object('flyers',(p_body->>'flyers')::integer,'flyers_done',(p_body->>'flyers')::integer>0);
 else raise exception '전단지 배포 여부를 선택하세요.';
 end if;
 if p_status='submitted' and jsonb_typeof(v_body->'flyers_done')='null' then raise exception '전단지 배포함 또는 배포 안 함을 선택하세요.';end if;
 foreach v_key in array array['completed','tomorrow','shared'] loop
  if jsonb_typeof(p_body->v_key) is distinct from 'string' or length(p_body->>v_key)>10000 then raise exception '업무 메모는 항목당 10,000자 이하로 입력하세요.';end if;
  v_body:=v_body||jsonb_build_object(v_key,trim(p_body->>v_key));
 end loop;
 if p_status='submitted' and (v_body->>'completed'='' or v_body->>'tomorrow'='') then raise exception '오늘 완료한 업무와 내일 할 일을 적어 주세요. 없으면 없음으로 입력하세요.';end if;
 if jsonb_typeof(p_body->'followups') is distinct from 'array' or jsonb_array_length(p_body->'followups')>50 then raise exception '재연락 고객은 보고당 50명까지 입력할 수 있습니다.';end if;
 for v_item in select value from jsonb_array_elements(p_body->'followups') loop
  if jsonb_typeof(v_item) is distinct from 'object' then raise exception '재연락 내용을 확인하세요.';end if;
  if exists(select 1 from jsonb_object_keys(v_item) k where k not in ('customer','content','pending','contact_at')) then raise exception '재연락 입력항목을 확인하세요.';end if;
  foreach v_key in array array['customer','content','pending','contact_at'] loop
   if jsonb_typeof(v_item->v_key) is distinct from 'string' or length(v_item->>v_key)>1000 then raise exception '재연락 내용을 확인하세요.';end if;
   v_item:=jsonb_set(v_item,array[v_key],to_jsonb(trim(v_item->>v_key)));
   if p_status='submitted' and v_item->>v_key='' then raise exception '재연락 고객의 구분·상담 내용·남은 일·연락 예정 시간을 모두 입력하세요.';end if;
  end loop;
  if v_item->>'contact_at'<>'' then
   if v_item->>'contact_at'!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$' then raise exception '연락 예정 시간을 확인하세요.';end if;
   v_when:=(v_item->>'contact_at')::timestamp;
   if to_char(v_when,'YYYY-MM-DD"T"HH24:MI')<>v_item->>'contact_at' then raise exception '연락 예정 시간을 확인하세요.';end if;
  end if;
  v_followups:=v_followups||jsonb_build_array(v_item);
 end loop;
 v_body:=v_body||jsonb_build_object('followups',v_followups);
 perform pg_advisory_xact_lock(hashtextextended(p_date::text||':'||v_author::text,0));
 select * into v_old from jk_document_private.daily_reports where report_date=p_date and author_id=v_author for update;
 select r.author_name into v_name from jk_document_private.daily_report_roster() r where r.author_id=v_author;
 if v_name is null then v_name:=v_old.author_name;end if;
 if v_name is null then raise exception '승인된 작성자를 확인하세요.' using errcode='42501';end if;
 if coalesce(v_old.version,0)<>p_expected_version then
  if v_old.body=v_body and v_old.report_status=p_status then return to_jsonb(v_old);end if;
  raise exception '다른 화면에서 보고가 변경됐습니다. 새로고침 후 다시 확인하세요. 작성 중인 내용은 복사해 두세요.' using errcode='40001';
 end if;
 insert into jk_document_private.daily_reports(report_date,author_id,author_name,body,report_status,updated_by,submitted_at)
 values(p_date,v_author,v_name,v_body,p_status,auth.uid(),case when p_status='submitted' then now() end)
 on conflict(report_date,author_id) do update set author_name=excluded.author_name,body=excluded.body,report_status=excluded.report_status,
 version=jk_document_private.daily_reports.version+1,updated_at=now(),updated_by=auth.uid(),submitted_at=excluded.submitted_at
 returning * into v_saved;
 return to_jsonb(v_saved);
end$$;
revoke all on function public.jk_save_daily_report(date,jsonb,text,integer,uuid) from public,anon;
grant execute on function public.jk_save_daily_report(date,jsonb,text,integer,uuid) to authenticated;


create function public.jk_daily_report_reminder() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_date date:=(now() at time zone 'Asia/Seoul')::date;v_status text;v_pending jsonb:='[]';v_manage boolean;
begin
 if auth.uid() is null or not coalesce(jk_document_private.can_read(),false) then raise exception '직원 승인이 필요합니다.' using errcode='42501';end if;
 v_manage:=public.jk_business_can_manage();
 select report_status into v_status from jk_document_private.daily_reports where report_date=v_date and author_id=auth.uid();
 if v_manage then
  select coalesce(jsonb_agg(jsonb_build_object('author_id',p.author_id,'author_name',p.author_name,'status',coalesce(r.report_status,'missing')) order by p.author_name),'[]') into v_pending
  from jk_document_private.daily_report_roster() p left join jk_document_private.daily_reports r on r.author_id=p.author_id and r.report_date=v_date
  where r.report_status is distinct from 'submitted';
 end if;
 return jsonb_build_object('report_date',v_date,'user_id',auth.uid(),'own_status',coalesce(v_status,'missing'),'can_manage',v_manage,'pending',v_pending);
end$$;
revoke all on function public.jk_daily_report_reminder() from public,anon;
grant execute on function public.jk_daily_report_reminder() to authenticated;
