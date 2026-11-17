-- =============================================================================
-- My Profile: everyone can edit their own contact info and profile photo.
-- Email stays tied to the Microsoft sign-in and can't be edited here.
-- Photos live at <org_id>/avatars/<user_id>.jpg in the private eco-files bucket.
-- =============================================================================

alter table public.profiles
  add column phone       text,
  add column job_title   text,
  add column avatar_path text;

-- Everyone (office users too) may upload/replace/delete their OWN avatar.
-- Other folders keep their existing rules.
drop policy if exists eco_files_insert on storage.objects;
create policy eco_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'eco-files'
              and (storage.foldername(name))[1] = public.auth_org_id()::text
              and (
                ((storage.foldername(name))[2] = 'avatars' and name like '%/avatars/' || auth.uid()::text || '.%')
                or ( coalesce((storage.foldername(name))[2], '') <> 'avatars'
                     and public.auth_app_role() <> 'office'
                     and (coalesce((storage.foldername(name))[2], '') <> 'library' or public.auth_app_role() = 'admin'))
              ));

drop policy if exists eco_files_update on storage.objects;
create policy eco_files_update on storage.objects for update to authenticated
  using (bucket_id = 'eco-files'
         and (storage.foldername(name))[1] = public.auth_org_id()::text
         and (
           ((storage.foldername(name))[2] = 'avatars' and name like '%/avatars/' || auth.uid()::text || '.%')
           or ( coalesce((storage.foldername(name))[2], '') <> 'avatars'
                and public.auth_app_role() <> 'office'
                and (coalesce((storage.foldername(name))[2], '') <> 'library' or public.auth_app_role() = 'admin'))
         ));

drop policy if exists eco_files_delete on storage.objects;
create policy eco_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'eco-files'
         and (storage.foldername(name))[1] = public.auth_org_id()::text
         and case
               when (storage.foldername(name))[2] = 'avatars'
                 then name like '%/avatars/' || auth.uid()::text || '.%' or public.auth_app_role() = 'admin'
               when (storage.foldername(name))[2] = 'library'
                 then public.auth_app_role() = 'admin'
               else public.auth_is_manager()
             end);
