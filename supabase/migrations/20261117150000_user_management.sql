-- =============================================================================
-- User management (admins add users from the website)
--
-- • Admins add a person (name, email, role) before they ever sign in. When that
--   person first signs in with Microsoft, they get exactly that role.
-- • "Open sign-up" setting: when OFF (default), only people an admin has added
--   (plus the bootstrap admin) get access. When ON, anyone with an
--   @ecosealsolutions.com account joins automatically as a Sales Rep.
-- • People who already signed in are unaffected.
-- • The last active admin can't be demoted or deactivated (no lock-outs).
-- =============================================================================

alter table public.organizations
  add column open_signup boolean not null default false;

create table public.user_invitations (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations (id) on delete cascade,
  email       text not null check (email = lower(trim(email)) and email like '%@%'),
  full_name   text not null default '',
  role        public.app_role not null default 'sales_rep',
  invited_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  accepted_at timestamptz,
  unique (org_id, email)
);
create index on public.user_invitations (email) where accepted_at is null;

alter table public.user_invitations enable row level security;

-- Everyone in the org can see the list (the iPad rep picker uses the names);
-- only admins can add, change or remove.
create policy invitations_select on public.user_invitations for select to authenticated
  using (org_id = public.auth_org_id());
create policy invitations_write on public.user_invitations for all to authenticated
  using (org_id = public.auth_org_id() and public.auth_app_role() = 'admin')
  with check (org_id = public.auth_org_id() and public.auth_app_role() = 'admin');

revoke all on public.user_invitations from anon;

-- Can't add someone who already has an account
create function public.invitation_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.email := lower(trim(new.email));
  if exists (select 1 from public.profiles where lower(email) = new.email) then
    raise exception '% already has an EcoPRO account. Change their role in the user list instead.', new.email;
  end if;
  return new;
end $$;

create trigger invitations_before_insert before insert on public.user_invitations
  for each row execute function public.invitation_before_insert();

-- New sign-in: an invitation decides org, role and name; otherwise open sign-up
-- (if on) or the bootstrap admin; otherwise no profile = no access.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_email text := lower(new.email);
  v_inv   public.user_invitations%rowtype;
  v_org   public.organizations%rowtype;
  v_name  text := coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1));
begin
  select * into v_inv from public.user_invitations
  where email = v_email and accepted_at is null
  order by created_at limit 1;

  if found then
    insert into public.profiles (id, org_id, email, full_name, role)
    values (new.id, v_inv.org_id, v_email, coalesce(nullif(v_inv.full_name, ''), v_name), v_inv.role);
    update public.user_invitations set accepted_at = now() where id = v_inv.id;
    return new;
  end if;

  select * into v_org from public.organizations
  where allowed_email_domain = split_part(v_email, '@', 2);

  if found and v_email = lower(coalesce(v_org.bootstrap_admin_email, '')) then
    insert into public.profiles (id, org_id, email, full_name, role)
    values (new.id, v_org.id, v_email, v_name, 'admin');
  elsif found and v_org.open_signup then
    insert into public.profiles (id, org_id, email, full_name, role)
    values (new.id, v_org.id, v_email, v_name, 'sales_rep');
  end if;
  return new;
end $$;

-- Never leave the org without an active admin
create function public.protect_last_admin() returns trigger
language plpgsql set search_path = public as $$
begin
  if old.role = 'admin' and old.active
     and (new.role <> 'admin' or not new.active)
     and not exists (
       select 1 from public.profiles
       where org_id = old.org_id and role = 'admin' and active and id <> old.id
     ) then
    raise exception 'You can''t remove the last active admin. Make someone else an admin first.';
  end if;
  return new;
end $$;

create trigger profiles_last_admin before update on public.profiles
  for each row execute function public.protect_last_admin();

-- Admin page shows changes live
alter publication supabase_realtime add table public.profiles, public.user_invitations;
