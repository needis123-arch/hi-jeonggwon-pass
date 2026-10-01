-- BUSINESS CENTER V3.42: consultations and a write-only public intake form.
-- All management data is protected by the existing server-side admin membership check.
create table public.jk_consultations (
 id uuid primary key default gen_random_uuid(),
 public_request_key uuid not null unique default gen_random_uuid(),
 customer_name text not null check (length(trim(customer_name)) between 1 and 80),
 phone_digits text not null check (phone_digits ~ '^01[0-9]{8,9}$'),
 staff_name text check (staff_name in ('송훈','인성')),
 services text[] not null default '{}' check (cardinality(services) between 0 and 5 and services <@ array['휴대폰','인터넷','TV','결합상품','통신비 무료진단']::text[]),
 contact_method text not null default '전화' check (contact_method in ('전화','방문','카카오톡')),
 customer_note text not null default '' check (length(customer_note)<=5000),
 consultation_note text not null default '' check (length(consultation_note)<=10000),
 move_date date,
 referral_code text not null default '' check (length(referral_code)<=80),
 intake_source text not null default '직접기록' check (intake_source in ('직접기록','고객신청')),
 consulted_on date not null default ((now() at time zone 'Asia/Seoul')::date),
 visited_on date,
 followup_days integer not null default 3 check (followup_days between 3 and 5),
 next_contact_on date default ((now() at time zone 'Asia/Seoul')::date),
 status text not null default '상담전' check (status in ('상담전','상담중','재연락','방문예정','계약완료','종료')),
 last_contacted_on date,
 last_contacted_at timestamptz,
 last_contact_note text not null default '' check (length(last_contact_note)<=5000),
 privacy_consent boolean not null default false,
 consent_version text,
 consented_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint jk_consultation_closed_check check ((status in ('계약완료','종료') and next_contact_on is null) or (status not in ('계약완료','종료') and next_contact_on is not null))
);
create index jk_consultation_staff_due_idx on public.jk_consultations(staff_name,next_contact_on);
create index jk_consultation_pending_due_idx on public.jk_consultations(next_contact_on) where status not in ('계약완료','종료');
create index jk_consultation_phone_idx on public.jk_consultations(phone_digits);

create table public.jk_consultation_history (
 id uuid primary key default gen_random_uuid(),
 consultation_id uuid not null references public.jk_consultations(id) on delete cascade,
 action text not null,
 note text not null default '',
 snapshot jsonb not null default '{}',
 created_by uuid,
 created_at timestamptz not null default now()
);
create index jk_consultation_history_parent_idx on public.jk_consultation_history(consultation_id,created_at desc);
alter table public.jk_consultations enable row level security;
alter table public.jk_consultation_history enable row level security;
revoke all on public.jk_consultations,public.jk_consultation_history from public,anon,authenticated;
grant select,insert,update,delete on public.jk_consultations to authenticated;
grant select,insert on public.jk_consultation_history to authenticated;
-- Public applicants can supply only intake fields and cannot return, read, edit or delete records.
grant insert (public_request_key,customer_name,phone_digits,staff_name,services,contact_method,customer_note,move_date,referral_code,intake_source,privacy_consent,consent_version) on public.jk_consultations to anon;
create policy jk_consultation_admin_select on public.jk_consultations for select to authenticated using ((select public.is_admin()));
create policy jk_consultation_admin_insert on public.jk_consultations for insert to authenticated with check ((select public.is_admin()));
create policy jk_consultation_admin_update on public.jk_consultations for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy jk_consultation_admin_delete on public.jk_consultations for delete to authenticated using ((select public.is_admin()));
create policy jk_consultation_public_intake on public.jk_consultations for insert to anon,authenticated with check (
 intake_source='고객신청' and privacy_consent and consent_version='2026-10-consult-v1'
 and status='상담전' and cardinality(services)>0 and followup_days=3
 and consulted_on=(now() at time zone 'Asia/Seoul')::date
 and next_contact_on=(now() at time zone 'Asia/Seoul')::date
 and visited_on is null and consultation_note='' and last_contacted_on is null and last_contacted_at is null and last_contact_note=''
);
create policy jk_consultation_history_select on public.jk_consultation_history for select to authenticated using ((select public.is_admin()));
create policy jk_consultation_history_insert on public.jk_consultation_history for insert to authenticated with check ((select public.is_admin()) and created_by=(select auth.uid()));

create function public.jk_prepare_consultation() returns trigger language plpgsql security invoker set search_path=public as $$
begin
 new.customer_name:=trim(new.customer_name);
 new.phone_digits:=regexp_replace(new.phone_digits,'\D','','g');
 new.updated_at:=now();
 if tg_op='INSERT' then
   new.created_at:=now();
   if new.intake_source='고객신청' and new.privacy_consent then new.consented_at:=now(); end if;
 end if;
 if new.status in ('계약완료','종료') then new.next_contact_on:=null;
 elsif new.next_contact_on is null then new.next_contact_on:=coalesce(new.visited_on,new.consulted_on)+new.followup_days; end if;
 return new;
end $$;
create trigger jk_prepare_consultation before insert or update on public.jk_consultations for each row execute function public.jk_prepare_consultation();

create function public.jk_log_consultation() returns trigger language plpgsql security invoker set search_path=public as $$
declare v_action text; v_note text;
begin
 -- Public writes do not acquire access to history; intake details remain on the parent record.
 if not public.is_admin() then return new; end if;
 if tg_op='INSERT' then v_action:='상담 등록';v_note:=new.consultation_note;
 elsif (to_jsonb(new)-'updated_at')=(to_jsonb(old)-'updated_at') then return new;
 elsif new.last_contacted_at is distinct from old.last_contacted_at or new.last_contacted_on is distinct from old.last_contacted_on or new.last_contact_note is distinct from old.last_contact_note then v_action:='재연락 기록';v_note:=new.last_contact_note;
 else v_action:='상담 정보 수정';v_note:=new.consultation_note; end if;
 insert into public.jk_consultation_history(consultation_id,action,note,snapshot,created_by)
 values(new.id,v_action,coalesce(v_note,''),jsonb_build_object('staff_name',new.staff_name,'status',new.status,'visited_on',new.visited_on,'next_contact_on',new.next_contact_on,'last_contacted_on',new.last_contacted_on),auth.uid());
 return new;
end $$;
create trigger jk_log_consultation after insert or update on public.jk_consultations for each row execute function public.jk_log_consultation();
revoke all on function public.jk_prepare_consultation(),public.jk_log_consultation() from public;
grant execute on function public.jk_prepare_consultation(),public.jk_log_consultation() to anon,authenticated;
notify pgrst,'reload schema';
