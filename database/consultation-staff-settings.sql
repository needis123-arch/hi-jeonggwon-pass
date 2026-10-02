-- Settings is the single source of staff names. The public directory contains
-- only display names and availability; auth identifiers remain private.
create table public.jk_consultation_staff_directory (
 staff_id uuid primary key references public.jk_staff(id) on delete cascade,
 name text not null unique,
 active boolean not null
);
alter table public.jk_consultation_staff_directory enable row level security;
revoke all on public.jk_consultation_staff_directory from public,anon,authenticated;
grant select(name,active) on public.jk_consultation_staff_directory to anon;
grant select on public.jk_consultation_staff_directory to authenticated;
grant insert,update,delete on public.jk_consultation_staff_directory to authenticated;
create policy jk_consult_staff_public_names on public.jk_consultation_staff_directory
 for select to anon,authenticated using (active or (select public.is_admin()));
create policy jk_consult_staff_admin_write on public.jk_consultation_staff_directory
 for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
insert into public.jk_consultation_staff_directory(staff_id,name,active)
 select id,name,active from public.jk_staff;

create function public.jk_sync_consultation_staff_directory() returns trigger
language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 insert into public.jk_consultation_staff_directory(staff_id,name,active)
 values(new.id,new.name,new.active)
 on conflict(staff_id) do update set name=excluded.name,active=excluded.active;
 return new;
end $$;
revoke all on function public.jk_sync_consultation_staff_directory() from public,anon;
grant execute on function public.jk_sync_consultation_staff_directory() to authenticated;
create trigger jk_sync_consultation_staff_directory
 after insert or update of name,active on public.jk_staff
 for each row execute function public.jk_sync_consultation_staff_directory();

alter table public.jk_consultations drop constraint jk_consultations_staff_name_check;
alter table public.jk_consultations add constraint jk_consultations_staff_name_check
 check(staff_name is null or length(trim(staff_name)) between 1 and 80);
create function public.jk_validate_consultation_staff() returns trigger
language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 -- Existing assignments remain editable after staff is deactivated.
 if new.staff_name is null then return new;end if;
 if tg_op='UPDATE' then
  if new.staff_name is not distinct from old.staff_name then return new;end if;
 end if;
 if not exists(select 1 from public.jk_consultation_staff_directory
  where name=new.staff_name and active) then
  raise exception '담당자가 변경되었습니다. 새로고침 후 담당자를 다시 선택해 주세요.' using errcode='23514';
 end if;
 return new;
end $$;
revoke all on function public.jk_validate_consultation_staff() from public;
grant execute on function public.jk_validate_consultation_staff() to anon,authenticated;
create trigger jk_validate_consultation_staff before insert or update of staff_name
 on public.jk_consultations for each row execute function public.jk_validate_consultation_staff();
notify pgrst,'reload schema';
