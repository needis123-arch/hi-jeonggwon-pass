-- Approved employees may create a new internal consultation, but may not edit
-- existing consultations, ledger rows, payment records or settings.
create or replace function public.jk_staff_create_consultation(p_record jsonb,p_request_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_row public.jk_consultations%rowtype;v_id uuid;v_today date:=(now() at time zone 'Asia/Seoul')::date;v_fingerprint text:=md5(p_record::text);
begin
 if not jk_document_private.can_read() then raise exception '직원 승인이 필요합니다.' using errcode='42501';end if;
 if p_request_key is null or jsonb_typeof(p_record) is distinct from 'object' or length(p_record::text)>15000 then raise exception '상담 입력값을 확인하세요.';end if;
 if exists(select 1 from jsonb_object_keys(p_record) k where k not in ('customer_name','phone_digits','staff_name','services','contact_method','consulted_on','visited_on','followup_days','next_contact_on','status','consultation_note')) then raise exception '허용되지 않은 상담 입력값입니다.';end if;
 if jsonb_typeof(p_record->'services') is distinct from 'array' then raise exception '필요 서비스를 확인하세요.';end if;
 select * into v_row from jsonb_populate_record(null::public.jk_consultations,p_record);
 if nullif(trim(v_row.customer_name),'') is null or v_row.phone_digits is null or v_row.phone_digits !~ '^01[0-9]{8,9}$'
  or nullif(trim(v_row.consultation_note),'') is null or v_row.consulted_on is null or v_row.consulted_on>v_today or v_row.visited_on>v_today then raise exception '고객명·전화번호·상담일·상담내역을 확인하세요.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request_key::text,0));
 select id into v_id from public.jk_consultations where public_request_key=p_request_key;
 if found then
  if exists(select 1 from public.jk_consultation_history where consultation_id=v_id and created_by=auth.uid() and action='직원 상담 등록' and snapshot->>'request_fingerprint'=v_fingerprint) then return jsonb_build_object('id',v_id);end if;
  raise exception '이미 사용한 저장 요청입니다. 목록에서 저장 여부를 확인하세요.';
 end if;
 insert into public.jk_consultations(public_request_key,customer_name,phone_digits,staff_name,services,contact_method,consulted_on,visited_on,followup_days,next_contact_on,status,consultation_note,intake_source)
 values(p_request_key,trim(v_row.customer_name),v_row.phone_digits,nullif(v_row.staff_name,''),v_row.services,v_row.contact_method,v_row.consulted_on,v_row.visited_on,v_row.followup_days,v_row.next_contact_on,v_row.status,v_row.consultation_note,'직접기록') returning id into v_id;
 insert into public.jk_consultation_history(consultation_id,action,note,snapshot,created_by)
 values(v_id,'직원 상담 등록',v_row.consultation_note,jsonb_build_object('staff_name',v_row.staff_name,'status',v_row.status,'next_contact_on',v_row.next_contact_on,'request_fingerprint',v_fingerprint),auth.uid());
 return jsonb_build_object('id',v_id);
end$$;
revoke all on function public.jk_staff_create_consultation(jsonb,uuid) from public,anon;
grant execute on function public.jk_staff_create_consultation(jsonb,uuid) to authenticated;
