-- Customer document access only. No financial table grants or admin-user changes.
begin;
create schema jk_document_private;
revoke all on schema jk_document_private from public,anon,authenticated;
create table jk_document_private.access_requests (
 user_id uuid primary key references auth.users(id) on delete cascade,
 email text not null, display_name text not null check(length(display_name) between 1 and 80),
 status text not null check(status in ('pending','approved','rejected','revoked')),
 requested_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 decided_by uuid references auth.users(id), version integer not null default 1
);
create index jk_document_requests_decider_idx on jk_document_private.access_requests(decided_by);
create table jk_document_private.audit (
 id bigint generated always as identity primary key, actor_id uuid,
 target_user_id uuid, document_id uuid, action text not null, created_at timestamptz not null default now()
);
create table jk_document_private.drive_connection (
 singleton boolean primary key default true check(singleton),
 client_id text, client_secret_id uuid references vault.secrets(id),
 refresh_secret_id uuid references vault.secrets(id), folder_id text,
 connected_email text, connected_at timestamptz
);
insert into jk_document_private.drive_connection(singleton) values(true);
alter table jk_document_private.access_requests enable row level security;
alter table jk_document_private.audit enable row level security;
alter table jk_document_private.drive_connection enable row level security;
revoke all on all tables in schema jk_document_private from public,anon,authenticated;

-- Only inspect the authenticated caller's verified address; never expose Auth lists.
create function jk_document_private.verified_email() returns text language sql stable security definer set search_path='' as $$
 select lower(u.email) from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null
 and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
$$;
create function jk_document_private.is_owner() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and coalesce(public.is_admin(),false)
 and coalesce(jk_document_private.verified_email()='needis123@gmail.com',false)
$$;
create function jk_document_private.can_read() returns boolean language sql stable security definer set search_path='' as $$
 select jk_document_private.is_owner() or exists(select 1 from jk_document_private.access_requests r
 where r.user_id=auth.uid() and r.status='approved' and r.email=jk_document_private.verified_email())
$$;
revoke all on all functions in schema jk_document_private from public,anon,authenticated;

create function public.jk_document_access_state() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_email text:=jk_document_private.verified_email(); v_row jk_document_private.access_requests;
begin
 if auth.uid() is null or v_email is null then raise exception 'Verified login required' using errcode='42501'; end if;
 select * into v_row from jk_document_private.access_requests where user_id=auth.uid() and email=v_email;
 return jsonb_build_object('owner',jk_document_private.is_owner(),'status',coalesce(v_row.status,'none'),
 'email',v_email,'display_name',v_row.display_name,'version',v_row.version,
 'drive_connected',exists(select 1 from jk_document_private.drive_connection where refresh_secret_id is not null));
end $$;
create function public.jk_document_request_access(p_name text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_email text:=jk_document_private.verified_email(); v_status text;
begin
 if auth.uid() is null or v_email is null then raise exception 'Verified login required' using errcode='42501'; end if;
 if p_name is null or length(trim(p_name)) not between 1 and 80 then raise exception 'Name required'; end if;
 select status into v_status from jk_document_private.access_requests where user_id=auth.uid() and email=v_email for update;
 if v_status in ('pending','approved') then return public.jk_document_access_state(); end if;
 insert into jk_document_private.access_requests(user_id,email,display_name,status)
 values(auth.uid(),v_email,trim(p_name),'pending')
 on conflict(user_id) do update set email=excluded.email,display_name=excluded.display_name,status='pending',
 requested_at=now(),updated_at=now(),decided_by=null,version=jk_document_private.access_requests.version+1;
 insert into jk_document_private.audit(actor_id,target_user_id,action) values(auth.uid(),auth.uid(),'requested');
 return public.jk_document_access_state();
end $$;
create function public.jk_document_access_requests() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not jk_document_private.is_owner() then raise exception 'Owner only' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(r) order by r.requested_at desc) from jk_document_private.access_requests r),'[]'::jsonb);
end $$;
create function public.jk_document_decide_access(p_user_id uuid,p_action text,p_version integer) returns void language plpgsql security definer set search_path='' as $$
declare v_row jk_document_private.access_requests;
begin
 if not jk_document_private.is_owner() then raise exception 'Owner only' using errcode='42501'; end if;
 select * into v_row from jk_document_private.access_requests where user_id=p_user_id for update;
 if not found or p_version is null or v_row.version<>p_version then raise exception 'Request changed; refresh'; end if;
 if (p_action in ('approved','rejected') and v_row.status<>'pending') or (p_action='revoked' and v_row.status<>'approved')
 or p_action not in ('approved','rejected','revoked') or p_action is null then raise exception 'Invalid decision'; end if;
 update jk_document_private.access_requests set status=p_action,decided_by=auth.uid(),updated_at=now(),version=version+1 where user_id=p_user_id;
 insert into jk_document_private.audit(actor_id,target_user_id,action) values(auth.uid(),p_user_id,p_action);
end $$;
create function public.jk_document_staff_customers(p_search text default '',p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_search text:=left(trim(coalesce(p_search,'')),100);
begin
 if not jk_document_private.can_read() then raise exception 'Document approval required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(r)) from (
 select l.id,l.customer_name_snapshot,l.customer_phone_snapshot,l.activation_date,l.vendor
 from public.jk_sales_ledger l where exists(select 1 from public.jk_ledger_documents d where d.ledger_id=l.id and d.storage_provider='google_drive')
 and (v_search='' or position(lower(v_search) in lower(coalesce(l.customer_name_snapshot,'')))>0
 or (regexp_replace(v_search,'[^0-9]','','g')<>'' and position(regexp_replace(v_search,'[^0-9]','','g') in regexp_replace(coalesce(l.customer_phone_snapshot,''),'[^0-9]','','g'))>0))
 order by l.activation_date desc,l.id limit 50 offset greatest(0,least(coalesce(p_offset,0),100000))
 )r),'[]'::jsonb);
end $$;
create function public.jk_document_staff_files(p_ledger_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not jk_document_private.can_read() then raise exception 'Document approval required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'ledger_id',d.ledger_id,'doc_kind',d.doc_kind,'byte_size',d.byte_size,'created_at',d.created_at) order by d.created_at)
 from public.jk_ledger_documents d where d.ledger_id=p_ledger_id and d.storage_provider='google_drive'),'[]'::jsonb);
end $$;

-- These RPCs are executable by the Edge Function's server role only.
create function public.jk_document_server_credentials() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('client_id',c.client_id,'client_secret',(select decrypted_secret from vault.decrypted_secrets where id=c.client_secret_id),
 'refresh_token',(select decrypted_secret from vault.decrypted_secrets where id=c.refresh_secret_id),'folder_id',c.folder_id)
 from jk_document_private.drive_connection c where singleton
$$;
create function public.jk_document_server_save_connection(p_refresh_token text,p_folder_id text,p_email text) returns void language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if p_email is null or p_email<>'needis123@gmail.com' or p_refresh_token is null or length(p_refresh_token)<10 or p_folder_id is null or p_folder_id !~ '^[A-Za-z0-9_-]{10,200}$' then raise exception 'Invalid connection'; end if;
 select refresh_secret_id into v_id from jk_document_private.drive_connection where singleton for update;
 if v_id is null then select vault.create_secret(p_refresh_token,'jk_document_drive_refresh','Document app owner refresh token') into v_id;
 else perform vault.update_secret(v_id,p_refresh_token); end if;
 update jk_document_private.drive_connection set refresh_secret_id=v_id,folder_id=p_folder_id,connected_email=p_email,connected_at=now() where singleton;
end $$;
create function public.jk_document_server_read_record(p_user_id uuid,p_document_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_doc public.jk_ledger_documents;
begin
 -- Check approval and current verified identity on every download, including after revocation.
 if not exists(select 1 from jk_document_private.access_requests r join auth.users u on u.id=r.user_id
 where r.user_id=p_user_id and r.status='approved' and lower(u.email)=r.email and u.email_confirmed_at is not null)
 then raise exception 'Document approval required' using errcode='42501'; end if;
 select * into v_doc from public.jk_ledger_documents where id=p_document_id and storage_provider='google_drive';
 if not found then raise exception 'Document not found' using errcode='P0002'; end if;
 return jsonb_build_object('drive_file_id',v_doc.drive_file_id,'byte_size',v_doc.byte_size);
end $$;
create function public.jk_document_server_log_read(p_user_id uuid,p_document_id uuid) returns void language sql security definer set search_path='' as $$
 insert into jk_document_private.audit(actor_id,document_id,action) values(p_user_id,p_document_id,'viewed_ciphertext')
$$;
revoke all on function public.jk_document_server_credentials(),public.jk_document_server_save_connection(text,text,text),public.jk_document_server_read_record(uuid,uuid),public.jk_document_server_log_read(uuid,uuid) from public,anon,authenticated;
grant execute on function public.jk_document_server_credentials(),public.jk_document_server_save_connection(text,text,text),public.jk_document_server_read_record(uuid,uuid),public.jk_document_server_log_read(uuid,uuid) to service_role;
revoke all on function public.jk_document_access_state(),public.jk_document_request_access(text),public.jk_document_access_requests(),public.jk_document_decide_access(uuid,text,integer),public.jk_document_staff_customers(text,integer),public.jk_document_staff_files(uuid) from public,anon;
grant execute on function public.jk_document_access_state(),public.jk_document_request_access(text),public.jk_document_access_requests(),public.jk_document_decide_access(uuid,text,integer),public.jk_document_staff_customers(text,integer),public.jk_document_staff_files(uuid) to authenticated;
comment on schema jk_document_private is 'Private document approval/audit and Vault links. No financial privileges are granted to staff.';
commit;
