-- Scope: encrypted customer scans only. No sales, settlement or payroll changes.
begin;
create table public.jk_ledger_documents (
 id uuid primary key,
 ledger_id uuid not null references public.jk_sales_ledger(id) on delete restrict,
 storage_path text not null unique,
 doc_kind text not null check (doc_kind in ('가입 서류','신분증 사본','기타 서류')),
 byte_size bigint not null check (byte_size between 1 and 20971520),
 created_at timestamptz not null default now(),
 created_by uuid not null default auth.uid(),
 constraint jk_document_path check (storage_path=ledger_id::text||'/'||id::text||'.jkdoc')
);
create index jk_ledger_documents_ledger_date_idx on public.jk_ledger_documents(ledger_id,created_at);
alter table public.jk_ledger_documents enable row level security;
revoke all on public.jk_ledger_documents from public,anon,authenticated;
grant select,insert,delete on public.jk_ledger_documents to authenticated;
create policy jk_documents_select on public.jk_ledger_documents for select to authenticated using ((select public.is_admin()));
create policy jk_documents_insert on public.jk_ledger_documents for insert to authenticated with check ((select public.is_admin()) and created_by=(select auth.uid()));
create policy jk_documents_delete on public.jk_ledger_documents for delete to authenticated using ((select public.is_admin()));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values ('jk-ledger-documents','jk-ledger-documents',false,20975616,array['application/octet-stream']);
-- Even a future broad storage policy must not make this bucket public.
create policy jk_documents_storage_guard on storage.objects as restrictive for all to public
 using (bucket_id<>'jk-ledger-documents' or (select public.is_admin()))
 with check (bucket_id<>'jk-ledger-documents' or (select public.is_admin()));
create policy jk_documents_storage_select on storage.objects for select to authenticated
 using (bucket_id='jk-ledger-documents' and (select public.is_admin()));
create policy jk_documents_storage_insert on storage.objects for insert to authenticated
 with check (bucket_id='jk-ledger-documents' and (select public.is_admin())
  and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jkdoc$'
  and exists(select 1 from public.jk_sales_ledger l where l.id::text=(storage.foldername(name))[1]));
create policy jk_documents_storage_delete on storage.objects for delete to authenticated
 using (bucket_id='jk-ledger-documents' and (select public.is_admin()));
comment on table public.jk_ledger_documents is 'Admin-only metadata for client-side AES-GCM encrypted scans. No password, original filename, image or ID data in metadata.';
commit;
