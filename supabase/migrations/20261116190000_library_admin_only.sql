-- =============================================================================
-- Literature Library: only admins may add, rename or delete documents.
-- Everyone in the org can still view them. Also turns on live updates for the
-- library and proposal attachments so new documents appear for everyone instantly.
-- =============================================================================

-- Library rows: read = whole org (unchanged), write = admins only
drop policy if exists library_write on public.library_documents;
create policy library_write on public.library_documents for all to authenticated
  using (org_id = public.auth_org_id() and public.auth_app_role() = 'admin')
  with check (org_id = public.auth_org_id() and public.auth_app_role() = 'admin');

-- Library files (<org_id>/library/...): only admins may upload, replace or delete.
-- Other folders keep their existing rules.
drop policy if exists eco_files_insert on storage.objects;
create policy eco_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'eco-files'
              and (storage.foldername(name))[1] = public.auth_org_id()::text
              and public.auth_app_role() <> 'office'
              and (coalesce((storage.foldername(name))[2], '') <> 'library' or public.auth_app_role() = 'admin'));

drop policy if exists eco_files_update on storage.objects;
create policy eco_files_update on storage.objects for update to authenticated
  using (bucket_id = 'eco-files'
         and (storage.foldername(name))[1] = public.auth_org_id()::text
         and public.auth_app_role() <> 'office'
         and (coalesce((storage.foldername(name))[2], '') <> 'library' or public.auth_app_role() = 'admin'));

drop policy if exists eco_files_delete on storage.objects;
create policy eco_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'eco-files'
         and (storage.foldername(name))[1] = public.auth_org_id()::text
         and case when coalesce((storage.foldername(name))[2], '') = 'library'
                  then public.auth_app_role() = 'admin'
                  else public.auth_is_manager() end);

-- Live updates for the library and proposal attachments
alter publication supabase_realtime add table public.library_documents, public.proposal_documents;
