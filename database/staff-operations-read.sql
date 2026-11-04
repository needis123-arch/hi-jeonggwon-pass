-- Additional read-only screens for the owner's existing approved employee group.
-- No table grants, write policies, admin membership or document credentials change.
create or replace function public.jk_staff_operations(p_screen text,p_month date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_start date;v_end date;v_rows jsonb;
begin
 if not jk_document_private.can_read() then raise exception 'Staff approval required' using errcode='42501';end if;
 if p_screen is null or p_screen not in ('used','payback','affiliate') then raise exception 'Invalid screen';end if;
 if p_month is null or p_month<date '2000-01-01' or p_month>=date '2100-01-01' then raise exception 'Invalid month';end if;
 v_start:=date_trunc('month',p_month)::date;v_end:=(v_start+interval '1 month')::date;
 if p_screen='used' then
  select coalesce(jsonb_agg(to_jsonb(r) order by r.activation_date desc,r.id),'[]'::jsonb) into v_rows from (
   select v.id,v.ledger_id,v.activation_date,v.customer_name,v.customer_phone,v.expected_model,v.expected_amount,v.assigned_staff,
    v.response_status,v.due_date,v.received_at,v.settled_at,v.note,v.workflow_status
   from public.jk_v_used_device_return_status v where v.activation_date>=v_start and v.activation_date<v_end
  )r;
 elsif p_screen='payback' then
  select coalesce(jsonb_agg(to_jsonb(r) order by r.due_date,r.ledger_id),'[]'::jsonb) into v_rows from (
   select v.ledger_id,v.customer_name,v.customer_phone,v.salesperson,v.promised_amount,v.paid_amount,v.outstanding_amount,v.due_date,
    v.bank_name,v.account_holder,v.account_number,v.payment_status,v.verification_status,v.verification_note
   from public.jk_v_payback_checklist v where v.due_date>=v_start and v.due_date<v_end
  )r;
 else
  select coalesce(jsonb_agg(to_jsonb(r) order by r.due_date,r.ledger_id),'[]'::jsonb) into v_rows from (
   select v.id,v.ledger_id,v.customer_name,v.customer_phone,v.activation_date,v.carrier,v.due_date,v.card_company,v.card_amount,
    v.status,v.registered_at,v.note,v.salesperson,v.alert_status,v.days_remaining
   from public.jk_v_affiliate_card_status v where v.due_date>=v_start and v.due_date<v_end
  )r;
 end if;
 return v_rows;
end $$;
revoke all on function public.jk_staff_operations(text,date) from public,anon;
grant execute on function public.jk_staff_operations(text,date) to authenticated;

create or replace function public.jk_staff_consultations(p_staff text default 'all',p_status text default 'active',p_search text default '',p_page integer default 1,p_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_rows jsonb;v_history jsonb:='[]'::jsonb;v_count bigint;v_today date:=(now() at time zone 'Asia/Seoul')::date;
 v_digits text:=regexp_replace(coalesce(p_search,''),'[^0-9]','','g');
begin
 if not jk_document_private.can_read() then raise exception 'Staff approval required' using errcode='42501';end if;
 if p_page is null or p_page<1 or p_page>100000 or length(coalesce(p_search,''))>100 or length(coalesce(p_staff,''))>80 then raise exception 'Invalid filters';end if;
 if p_status is null or p_status not in ('all','active','due','상담전','상담중','재연락','방문예정','계약완료','종료') then raise exception 'Invalid status';end if;
 with matched as materialized (
  select c.id,c.customer_name,c.phone_digits,c.staff_name,c.services,c.contact_method,c.customer_note,c.consultation_note,c.move_date,
   c.referral_code,c.intake_source,c.consulted_on,c.visited_on,c.followup_days,c.next_contact_on,c.status,c.last_contacted_on,
   c.last_contact_note,c.created_at,c.updated_at
  from public.jk_consultations c
  where (p_id is not null and c.id=p_id) or (p_id is null
   and (p_staff='all' or (p_staff='unassigned' and c.staff_name is null) or c.staff_name=p_staff)
   and (p_status='all' or (p_status='active' and c.status in ('상담전','상담중','재연락','방문예정'))
    or (p_status='due' and c.status in ('상담전','상담중','재연락','방문예정') and c.next_contact_on<=v_today) or c.status=p_status)
   and (coalesce(p_search,'')='' or (length(v_digits)>=3 and strpos(c.phone_digits,v_digits)>0)
    or (length(v_digits)<3 and strpos(lower(c.customer_name),lower(p_search))>0)))
 ),page_rows as (select * from matched order by next_contact_on asc nulls last,created_at desc,id limit 20 offset (p_page-1)*20)
 select (select count(*) from matched),(select coalesce(jsonb_agg(to_jsonb(r) order by r.next_contact_on asc nulls last,r.created_at desc,r.id),'[]'::jsonb) from page_rows r) into v_count,v_rows;
 if p_id is not null then
  select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id),'[]'::jsonb) into v_history from (
   select h.id,h.action,h.note,h.created_at,jsonb_build_object('staff_name',h.snapshot->>'staff_name','status',h.snapshot->>'status','next_contact_on',h.snapshot->>'next_contact_on') snapshot
   from public.jk_consultation_history h where h.consultation_id=p_id order by h.created_at desc,h.id limit 30
  )r;
 end if;
 return jsonb_build_object('rows',v_rows,'count',v_count,'history',v_history);
end $$;
revoke all on function public.jk_staff_consultations(text,text,text,integer,uuid) from public,anon;
grant execute on function public.jk_staff_consultations(text,text,text,integer,uuid) to authenticated;
comment on function public.jk_staff_operations(text,date) is 'Verified owner-approved employee read only: monthly used returns, customer payback and affiliate registration. Current approval checked on every call.';
comment on function public.jk_staff_consultations(text,text,text,integer,uuid) is 'Verified owner-approved employee read only: paginated consultation lists, details and limited history. No public submission key or author identity returned.';
