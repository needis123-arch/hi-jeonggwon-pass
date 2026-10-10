-- Add Google Drive linkage only; all existing admin-only policies remain.
begin;
alter table public.jk_ledger_documents
 add column storage_provider text not null default 'supabase' check(storage_provider in ('supabase','google_drive')),
 add column drive_file_id text;
alter table public.jk_ledger_documents add constraint jk_document_provider_link
 check ((storage_provider='supabase' and drive_file_id is null)
     or (storage_provider='google_drive' and drive_file_id is not null and drive_file_id ~ '^[A-Za-z0-9_-]{10,200}$'));
create unique index jk_ledger_documents_drive_file_idx on public.jk_ledger_documents(drive_file_id) where drive_file_id is not null;
comment on column public.jk_ledger_documents.drive_file_id is 'Opaque private Google Drive ID. Ciphertext remains in owner Drive, never in database.';
commit;
