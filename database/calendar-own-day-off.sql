-- Approved employees may change ONLY their own dated holidays. Manager settings stay private.
create function public.jk_set_own_day_off(p_date date,p_day_off boolean,p_expected_revision integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_revision integer;v_value boolean;
begin
 if auth.uid() is null or not coalesce(jk_document_private.can_read(),false) then raise exception '직원 승인이 필요합니다.' using errcode='42501';end if;
 if not exists(select 1 from jk_document_private.daily_report_roster() r where r.author_id=auth.uid()) then raise exception '승인된 담당자를 확인하세요.' using errcode='42501';end if;
 if p_date is null or p_date<date '2020-01-01' or p_date>(now() at time zone 'Asia/Seoul')::date+366 or p_day_off is null or p_expected_revision is null or p_expected_revision<0 then raise exception '휴무 날짜와 설정값을 확인하세요.';end if;
 -- Same lock as the manager endpoint, preventing conflicts between self and manager edits.
 perform pg_advisory_xact_lock(hashtextextended('closing-setting:'||auth.uid()::text||':day_off'||p_date::text,0));
 select revision,day_off into v_revision,v_value from jk_document_private.daily_report_days_off where author_id=auth.uid() and report_date=p_date for update;
 if coalesce(v_revision,0)<>p_expected_revision then
  if v_value=p_day_off then return jsonb_build_object('report_date',p_date,'author_id',auth.uid(),'day_off',v_value,'revision',v_revision);end if;
  raise exception '다른 화면에서 휴무를 변경했습니다. 새로고침 후 다시 확인하세요.' using errcode='40001';
 end if;
 insert into jk_document_private.daily_report_days_off(author_id,report_date,day_off,updated_by) values(auth.uid(),p_date,p_day_off,auth.uid())
 on conflict(author_id,report_date) do update set day_off=excluded.day_off,revision=jk_document_private.daily_report_days_off.revision+1,updated_at=now(),updated_by=auth.uid()
 returning revision into v_revision;
 return jsonb_build_object('report_date',p_date,'author_id',auth.uid(),'day_off',p_day_off,'revision',v_revision);
end$$;
revoke all on function public.jk_set_own_day_off(date,boolean,integer) from public,anon;
grant execute on function public.jk_set_own_day_off(date,boolean,integer) to authenticated;
