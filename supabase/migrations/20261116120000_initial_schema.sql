-- =============================================================================
-- EcoProposal — initial Supabase schema
-- Phase 1 of the cloud migration: tables, numbering, totals, record locking,
-- role-based security (RLS), file storage, realtime and audit log.
--
-- Roles
--   admin       everything, incl. users, settings, literature library
--   manager     view + edit everything in the org
--   sales_rep   view everything; create proposals/inspections; edit own (or where added as collaborator)
--   technician  view everything; create/edit own inspection reports
--   office      view everything; change proposal status only
--
-- Run once in Supabase: SQL Editor -> paste -> Run.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Types
-- -----------------------------------------------------------------------------
create type public.app_role        as enum ('admin', 'manager', 'sales_rep', 'technician', 'office');
create type public.division        as enum ('remodel', 'new_construction', 'service');
create type public.proposal_status as enum ('draft', 'sent', 'accepted', 'declined');
create type public.warranty_option as enum ('none', 'thirty_year', 'lifetime');

-- -----------------------------------------------------------------------------
-- 2. Organizations and user profiles
-- -----------------------------------------------------------------------------
create table public.organizations (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  street                text,
  city_state_zip        text,
  phone                 text,
  website               text,
  allowed_email_domain  text unique,          -- new sign-ins from this domain join the org
  bootstrap_admin_email text,                 -- this person becomes admin on first sign-in
  default_tax_rate      numeric(7,5) not null default 0,
  default_terms         text not null default '',
  down_payment_rate     numeric(5,4) not null default 0.20,
  timezone              text not null default 'America/New_York',
  created_at            timestamptz not null default now()
);

create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  org_id     uuid not null references public.organizations (id),
  full_name  text not null default '',
  email      text not null,
  role       public.app_role not null default 'sales_rep',
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
create index on public.profiles (org_id);

-- Helper functions used by every security policy. SECURITY DEFINER so they can
-- read profiles without recursing into profiles' own policies.
-- They return NULL for inactive users, which makes every policy fail closed.
create function public.auth_org_id() returns uuid
language sql stable security definer set search_path = public as $$
  select org_id from public.profiles where id = auth.uid() and active
$$;

create function public.auth_app_role() returns public.app_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid() and active
$$;

create function public.auth_is_manager() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.auth_app_role() in ('admin', 'manager'), false)
$$;

-- New sign-ins (e.g. Microsoft 365 via the Azure provider) get a profile only if
-- their email domain belongs to an organization. Everyone else can log in but sees nothing.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_org public.organizations%rowtype;
begin
  select * into v_org
  from public.organizations
  where allowed_email_domain = lower(split_part(new.email, '@', 2));

  if found then
    insert into public.profiles (id, org_id, email, full_name, role)
    values (
      new.id,
      v_org.id,
      lower(new.email),
      coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
      case when lower(new.email) = lower(v_org.bootstrap_admin_email) then 'admin'::public.app_role
           else 'sales_rep'::public.app_role end
    );
  end if;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Only admins may change role, org, active or email (SQL Editor / service role is unrestricted).
create function public.protect_profile_fields() returns trigger
language plpgsql set search_path = public as $$
begin
  if auth.uid() is not null and public.auth_app_role() is distinct from 'admin'
     and (new.role is distinct from old.role or new.org_id is distinct from old.org_id
          or new.active is distinct from old.active or new.email is distinct from old.email) then
    raise exception 'Only an admin can change role, organization, active status or email';
  end if;
  return new;
end $$;

create trigger profiles_protect before update on public.profiles
  for each row execute function public.protect_profile_fields();

-- -----------------------------------------------------------------------------
-- 3. Document numbering (P-2026-0001, SR-2026-0001), shared across all devices
-- -----------------------------------------------------------------------------
create table public.number_counters (
  org_id    uuid not null references public.organizations (id) on delete cascade,
  prefix    text not null,
  year      int  not null,
  last_used int  not null default 0,
  primary key (org_id, prefix, year)
);

create function public.next_document_number(p_org uuid, p_prefix text) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_year int;
  v_n    int;
begin
  select extract(year from now() at time zone timezone)::int into v_year
  from public.organizations where id = p_org;

  insert into public.number_counters (org_id, prefix, year, last_used)
  values (p_org, p_prefix, v_year, 1)
  on conflict (org_id, prefix, year)
  do update set last_used = public.number_counters.last_used + 1
  returning last_used into v_n;

  return format('%s-%s-%s', p_prefix, v_year, lpad(v_n::text, 4, '0'));
end $$;

-- -----------------------------------------------------------------------------
-- 4. Customers and jobs
-- -----------------------------------------------------------------------------
create table public.customers (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations (id),
  owner_id     uuid references public.profiles (id),
  name         text not null default '',
  company_name text,
  email        text,
  phone        text,
  street       text,
  city         text,
  state        text,
  zip          text,
  version      int not null default 1,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   uuid
);
create index on public.customers (org_id);

create table public.jobs (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations (id),
  customer_id uuid references public.customers (id) on delete set null,
  owner_id    uuid references public.profiles (id),
  title       text not null default '',
  site_street text,
  site_city   text,
  site_state  text,
  site_zip    text,
  notes       text,
  version     int not null default 1,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);
create index on public.jobs (org_id);
create index on public.jobs (customer_id);

-- -----------------------------------------------------------------------------
-- 5. Proposals and everything attached to them
-- -----------------------------------------------------------------------------
create table public.proposals (
  id                        uuid primary key default gen_random_uuid(),
  org_id                    uuid not null references public.organizations (id),
  job_id                    uuid references public.jobs (id) on delete set null,
  owner_id                  uuid references public.profiles (id),
  collaborator_ids          uuid[] not null default '{}',
  number                    text,                         -- assigned by trigger
  proposal_date             date not null default current_date,
  division                  public.division not null default 'remodel',
  status                    public.proposal_status not null default 'draft',
  tax_rate                  numeric(7,5) not null default 0,
  down_payment_rate         numeric(5,4),                 -- copied from org on insert
  terms                     text not null default '',
  scope_text                text not null default '',     -- plain-text mirror for search
  scope_html                text,                         -- rich notes (replaces RTF)
  scope_checklist           jsonb not null default '{}',  -- exterior / interior / service checkboxes
  warranty                  public.warranty_option not null default 'none',
  inspector                 text not null default '',
  referral                  text not null default '',
  permit_required           boolean not null default false,
  pdf_options               jsonb not null default '{"show_line_items": true, "show_pricing": true, "show_permit": true}',
  auto_attached_library_ids uuid[] not null default '{}',
  is_archived               boolean not null default false,
  supersedes_id             uuid references public.proposals (id),
  locked_at                 timestamptz,                  -- set when customer + rep have both signed
  -- Totals: maintained by the database, never written by the apps
  subtotal                  numeric(12,2) not null default 0,
  tax_amount                numeric(12,2) not null default 0,
  total                     numeric(12,2) not null default 0,
  down_payment              numeric(12,2) not null default 0,
  balance_due               numeric(12,2) not null default 0,
  version                   int not null default 1,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  updated_by                uuid,
  unique (org_id, number)
);
create index on public.proposals (org_id, status);
create index on public.proposals (job_id);
create index on public.proposals (owner_id);

create table public.line_items (
  id          uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.proposals (id) on delete cascade,
  description text not null default '',
  quantity    numeric(12,3) not null default 1,
  unit        text not null default 'ea',
  unit_price  numeric(12,2) not null default 0,
  line_total  numeric(14,2) generated always as (round(quantity * unit_price, 2)) stored,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index on public.line_items (proposal_id, sort_order);

create table public.sketches (
  id           uuid primary key default gen_random_uuid(),
  proposal_id  uuid not null references public.proposals (id) on delete cascade,
  page_number  int not null default 1,
  drawing_path text,                   -- PencilKit data (iPad editing)
  png_path     text,                   -- rendered image (web viewing, PDF)
  annotations  jsonb not null default '[]',
  segments     jsonb not null default '[]',
  cracks       jsonb not null default '[]',
  updated_at   timestamptz not null default now()
);
create index on public.sketches (proposal_id);

create table public.blueprints (
  id                      uuid primary key default gen_random_uuid(),
  proposal_id             uuid not null references public.proposals (id) on delete cascade,
  caption                 text not null default '',
  sort_order              int not null default 0,
  pixels_per_foot         double precision,
  detected_pdf_scale      text,
  pdf_rasterization_scale double precision,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
create index on public.blueprints (proposal_id);

create table public.blueprint_pages (
  id           uuid primary key default gen_random_uuid(),
  blueprint_id uuid not null references public.blueprints (id) on delete cascade,
  sort_order   int not null default 0,
  image_path   text not null,
  measurements jsonb not null default '[]',
  updated_at   timestamptz not null default now()
);
create index on public.blueprint_pages (blueprint_id);

create table public.library_documents (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null references public.organizations (id),
  title            text not null,
  file_path        text not null,
  auto_attach_rule text,              -- e.g. 'line_item_contains:Fortress'
  created_at       timestamptz not null default now()
);
create index on public.library_documents (org_id);

create table public.proposal_documents (
  id          uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.proposals (id) on delete cascade,
  title       text not null,
  file_path   text not null,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);
create index on public.proposal_documents (proposal_id);

-- -----------------------------------------------------------------------------
-- 6. Inspection (GMX service) reports
-- -----------------------------------------------------------------------------
create table public.inspection_reports (
  id                  uuid primary key default gen_random_uuid(),
  org_id              uuid not null references public.organizations (id),
  job_id              uuid references public.jobs (id) on delete set null,
  owner_id            uuid references public.profiles (id),
  number              text,                       -- assigned by trigger
  visit_date          date not null default current_date,
  homeowner           text not null default '',
  builder             text not null default '',
  street              text not null default '',
  city                text not null default '',
  state               text not null default '',
  zip                 text not null default '',
  gmx_warranty_number text not null default '',
  warranty_term       text not null default 'unset',
  determination       text not null default 'unset',
  checklist           jsonb not null default '[]', -- 20 item statuses, same order as the app
  form_data           jsonb not null default '{}', -- remaining form sections (present on site, testing, notes...)
  findings            text not null default '',
  action_taken        text not null default '',
  version             int not null default 1,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  updated_by          uuid,
  unique (org_id, number)
);
create index on public.inspection_reports (org_id);

-- Photos belong to exactly one proposal or one inspection
create table public.photos (
  id                  uuid primary key default gen_random_uuid(),
  proposal_id         uuid references public.proposals (id) on delete cascade,
  inspection_id       uuid references public.inspection_reports (id) on delete cascade,
  image_path          text not null,
  markup_drawing_path text,
  markup_png_path     text,
  caption             text not null default '',
  sort_order          int not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (num_nonnulls(proposal_id, inspection_id) = 1)
);
create index on public.photos (proposal_id);
create index on public.photos (inspection_id);

-- Signatures for proposals (customer, sales_rep) and inspections (technician, homeowner)
create table public.signatures (
  id            uuid primary key default gen_random_uuid(),
  proposal_id   uuid references public.proposals (id) on delete cascade,
  inspection_id uuid references public.inspection_reports (id) on delete cascade,
  party         text not null check (party in ('customer', 'sales_rep', 'technician', 'homeowner')),
  signer_name   text not null default '',
  signed_at     timestamptz not null default now(),
  drawing_path  text,
  png_path      text,
  ip_address    inet,
  check (num_nonnulls(proposal_id, inspection_id) = 1)
);
create unique index on public.signatures (proposal_id, party) where proposal_id is not null;
create unique index on public.signatures (inspection_id, party) where inspection_id is not null;

-- -----------------------------------------------------------------------------
-- 7. Customer share links and audit log
-- -----------------------------------------------------------------------------
create table public.share_links (
  id          uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.proposals (id) on delete cascade,
  token_hash  text not null unique,     -- sha256 of the token; the raw token is never stored
  created_by  uuid default auth.uid(),
  expires_at  timestamptz not null default now() + interval '30 days',
  viewed_at   timestamptz,
  revoked     boolean not null default false,
  created_at  timestamptz not null default now()
);
create index on public.share_links (proposal_id);

create table public.activity_log (
  id        bigint generated always as identity primary key,
  org_id    uuid not null,
  entity    text not null,
  entity_id uuid not null,
  actor_id  uuid,
  action    text not null,
  diff      jsonb,
  at        timestamptz not null default now()
);
create index on public.activity_log (org_id, entity, entity_id, at desc);

-- =============================================================================
-- 8. Business rules (triggers)
-- =============================================================================

-- Access helpers for child tables
create function public.can_view_proposal(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.proposals p
                 where p.id = p_id and p.org_id = public.auth_org_id())
$$;

create function public.can_edit_proposal(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.proposals p
    where p.id = p_id
      and p.org_id = public.auth_org_id()
      and (public.auth_is_manager()
           or (public.auth_app_role() = 'sales_rep'
               and (p.owner_id = auth.uid() or auth.uid() = any (p.collaborator_ids))))
  )
$$;

create function public.can_view_inspection(i_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.inspection_reports r
                 where r.id = i_id and r.org_id = public.auth_org_id())
$$;

create function public.can_edit_inspection(i_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.inspection_reports r
    where r.id = i_id
      and r.org_id = public.auth_org_id()
      and (public.auth_is_manager()
           or (public.auth_app_role() in ('sales_rep', 'technician') and r.owner_id = auth.uid()))
  )
$$;

-- Bookkeeping for customers, jobs, inspections: version + updated_at/by
create function public.touch_row() returns trigger
language plpgsql set search_path = public as $$
begin
  if (to_jsonb(new) - array['version','updated_at','updated_by'])
     is distinct from (to_jsonb(old) - array['version','updated_at','updated_by']) then
    new.version    := old.version + 1;
    new.updated_at := now();
    new.updated_by := auth.uid();
  end if;
  return new;
end $$;

create trigger customers_touch  before update on public.customers          for each row execute function public.touch_row();
create trigger jobs_touch       before update on public.jobs               for each row execute function public.touch_row();
create trigger inspection_touch before update on public.inspection_reports for each row execute function public.touch_row();

-- Proposal / inspection numbering + defaults on insert
create function public.proposals_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_org public.organizations%rowtype;
begin
  select * into v_org from public.organizations where id = new.org_id;
  if coalesce(new.number, '') = '' then
    new.number := public.next_document_number(new.org_id, 'P');
  end if;
  new.down_payment_rate := coalesce(new.down_payment_rate, v_org.down_payment_rate);
  new.owner_id   := coalesce(new.owner_id, auth.uid());
  new.updated_by := auth.uid();
  new.version    := 1;
  new.locked_at  := null;
  new.subtotal := 0; new.tax_amount := 0; new.total := 0; new.down_payment := 0; new.balance_due := 0;
  return new;
end $$;

create trigger proposals_insert before insert on public.proposals
  for each row execute function public.proposals_before_insert();

create function public.inspections_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.number, '') = '' then
    new.number := public.next_document_number(new.org_id, 'SR');
  end if;
  new.owner_id   := coalesce(new.owner_id, auth.uid());
  new.updated_by := auth.uid();
  return new;
end $$;

create trigger inspections_insert before insert on public.inspection_reports
  for each row execute function public.inspections_before_insert();

-- One place for every proposal update rule:
--   1. recompute totals from line items (subtotal, tax, total, 20% deposit, balance)
--   2. signed (locked) proposals: only status and archive flag may change
--   3. office role: only status may change
--   4. bump version when real content changed (used to detect edit collisions)
create function public.proposals_before_update() returns trigger
language plpgsql set search_path = public as $$
declare
  v_meta    text[] := array['subtotal','tax_amount','total','down_payment','balance_due',
                            'version','updated_at','updated_by','locked_at'];
  v_changed jsonb;
  v_key     text;
begin
  -- 1. Totals
  select coalesce(sum(line_total), 0) into new.subtotal
  from public.line_items where proposal_id = new.id;
  new.tax_amount   := round(new.subtotal * new.tax_rate, 2);
  new.total        := new.subtotal + new.tax_amount;
  new.down_payment := round(new.total * coalesce(new.down_payment_rate, 0), 2);
  new.balance_due  := greatest(new.total - new.down_payment, 0);

  -- Which user-editable columns changed?
  select coalesce(jsonb_object_agg(n.key, n.value), '{}') into v_changed
  from jsonb_each(to_jsonb(new) - v_meta) n
  where n.value is distinct from (to_jsonb(old) -> n.key);

  if v_changed = '{}' then
    return new;  -- totals-only refresh: no version bump
  end if;

  -- 2. Locked (fully signed) proposals
  if old.locked_at is not null and auth.uid() is not null then
    for v_key in select jsonb_object_keys(v_changed) loop
      if v_key not in ('status', 'is_archived') then
        raise exception 'Proposal % is signed and locked. Create a new version to make changes.', old.number;
      end if;
    end loop;
  end if;

  -- 3. Office role
  if public.auth_app_role() = 'office' then
    for v_key in select jsonb_object_keys(v_changed) loop
      if v_key <> 'status' then
        raise exception 'Office users can only change a proposal''s status';
      end if;
    end loop;
  end if;

  -- 4. Version / audit fields
  new.version    := old.version + 1;
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;

create trigger proposals_update before update on public.proposals
  for each row execute function public.proposals_before_update();

-- Signed proposals cannot be deleted from the apps
create function public.proposals_before_delete() returns trigger
language plpgsql set search_path = public as $$
begin
  if old.locked_at is not null and auth.uid() is not null then
    raise exception 'Proposal % is signed and cannot be deleted', old.number;
  end if;
  return old;
end $$;

create trigger proposals_delete before delete on public.proposals
  for each row execute function public.proposals_before_delete();

-- Children of a locked proposal are read-only
create function public.assert_proposal_unlocked() returns trigger
language plpgsql set search_path = public as $$
declare
  v_row    jsonb := to_jsonb(coalesce(new, old));
  v_pid    uuid;
  v_locked timestamptz;
begin
  if auth.uid() is null then return coalesce(new, old); end if;

  if tg_table_name = 'blueprint_pages' then
    select b.proposal_id into v_pid from public.blueprints b where b.id = (v_row->>'blueprint_id')::uuid;
  else
    v_pid := (v_row->>'proposal_id')::uuid;
  end if;

  if v_pid is not null then
    select locked_at into v_locked from public.proposals where id = v_pid;
    if v_locked is not null then
      raise exception 'This proposal is signed and locked. Create a new version to make changes.';
    end if;
  end if;
  return coalesce(new, old);
end $$;

create trigger line_items_lock         before insert or update or delete on public.line_items         for each row execute function public.assert_proposal_unlocked();
create trigger sketches_lock           before insert or update or delete on public.sketches           for each row execute function public.assert_proposal_unlocked();
create trigger blueprints_lock         before insert or update or delete on public.blueprints         for each row execute function public.assert_proposal_unlocked();
create trigger blueprint_pages_lock    before insert or update or delete on public.blueprint_pages    for each row execute function public.assert_proposal_unlocked();
create trigger proposal_documents_lock before insert or update or delete on public.proposal_documents for each row execute function public.assert_proposal_unlocked();
create trigger photos_lock             before insert or update or delete on public.photos             for each row execute function public.assert_proposal_unlocked();

-- Signatures: lock the proposal once customer AND rep have signed; never remove a signature from a locked proposal
create function public.signatures_after_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.proposal_id is not null then
    if (select count(distinct party) from public.signatures
        where proposal_id = new.proposal_id and party in ('customer', 'sales_rep')) = 2 then
      update public.proposals set locked_at = now()
      where id = new.proposal_id and locked_at is null;
    end if;
  end if;
  return null;
end $$;

create trigger signatures_lock_proposal after insert on public.signatures
  for each row execute function public.signatures_after_change();

create function public.signatures_before_change() returns trigger
language plpgsql set search_path = public as $$
begin
  if auth.uid() is not null and old.proposal_id is not null
     and exists (select 1 from public.proposals where id = old.proposal_id and locked_at is not null) then
    raise exception 'Signatures on a locked proposal cannot be changed';
  end if;
  return coalesce(new, old);
end $$;

create trigger signatures_protect before update or delete on public.signatures
  for each row execute function public.signatures_before_change();

-- Line item changes refresh the proposal totals (security definer: a totals refresh
-- is not a user edit and must not be blocked by the office/lock rules)
create function public.refresh_proposal_totals() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.proposals set subtotal = subtotal
  where id = coalesce(new.proposal_id, old.proposal_id);
  if tg_op = 'UPDATE' and new.proposal_id is distinct from old.proposal_id then
    update public.proposals set subtotal = subtotal where id = old.proposal_id;
  end if;
  return null;
end $$;

create trigger line_items_totals after insert or update or delete on public.line_items
  for each row execute function public.refresh_proposal_totals();

-- Audit log: who changed what, field by field
create function public.log_activity() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_new  jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  v_old  jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_row  jsonb := coalesce(v_new, v_old);
  v_org  uuid  := (v_row->>'org_id')::uuid;
  v_diff jsonb;
  v_noise text[] := array['subtotal','tax_amount','total','down_payment','balance_due',
                          'version','updated_at','updated_by','line_total'];
begin
  if v_org is null and v_row ? 'proposal_id' and v_row->>'proposal_id' is not null then
    select org_id into v_org from public.proposals where id = (v_row->>'proposal_id')::uuid;
  end if;
  if v_org is null and v_row ? 'inspection_id' and v_row->>'inspection_id' is not null then
    select org_id into v_org from public.inspection_reports where id = (v_row->>'inspection_id')::uuid;
  end if;
  if v_org is null then return null; end if;  -- parent already deleted (cascade)

  if tg_op = 'UPDATE' then
    select jsonb_object_agg(n.key, n.value) into v_diff
    from jsonb_each(v_new - v_noise) n
    where n.value is distinct from v_old -> n.key;
    if v_diff is null then return null; end if;
  elsif tg_op = 'INSERT' then
    v_diff := v_new - v_noise;
  end if;

  insert into public.activity_log (org_id, entity, entity_id, actor_id, action, diff)
  values (v_org, tg_table_name, (v_row->>'id')::uuid, auth.uid(), lower(tg_op), v_diff);
  return null;
end $$;

create trigger customers_log          after insert or update or delete on public.customers          for each row execute function public.log_activity();
create trigger jobs_log               after insert or update or delete on public.jobs               for each row execute function public.log_activity();
create trigger proposals_log          after insert or update or delete on public.proposals          for each row execute function public.log_activity();
create trigger line_items_log         after insert or update or delete on public.line_items         for each row execute function public.log_activity();
create trigger inspection_reports_log after insert or update or delete on public.inspection_reports for each row execute function public.log_activity();
create trigger signatures_log         after insert or update or delete on public.signatures         for each row execute function public.log_activity();
create trigger share_links_log        after insert or update on public.share_links                  for each row execute function public.log_activity();

-- =============================================================================
-- 9. New version of a signed proposal (mirrors Proposal.createNewVersion in the iOS app)
--    Copies header, line items, sketches, photos, documents and plan sets; archives
--    the original; signatures are NOT copied. Runs with the caller's permissions.
-- =============================================================================
create function public.create_proposal_version(p_id uuid) returns uuid
language plpgsql set search_path = public as $$
declare
  v_old public.proposals%rowtype;
  v_new uuid := gen_random_uuid();
  v_bp  record;
  v_nbp uuid;
begin
  select * into v_old from public.proposals where id = p_id;
  if not found then raise exception 'Proposal not found'; end if;
  if not (public.can_edit_proposal(p_id) or auth.uid() is null) then
    raise exception 'You do not have permission to version this proposal';
  end if;

  insert into public.proposals (
    id, org_id, job_id, owner_id, collaborator_ids, division, status, tax_rate, down_payment_rate,
    terms, scope_text, scope_html, scope_checklist, warranty, inspector, referral, permit_required,
    pdf_options, auto_attached_library_ids, supersedes_id)
  values (
    v_new, v_old.org_id, v_old.job_id, v_old.owner_id, v_old.collaborator_ids, v_old.division, 'draft',
    v_old.tax_rate, v_old.down_payment_rate, v_old.terms, v_old.scope_text, v_old.scope_html,
    v_old.scope_checklist, v_old.warranty, v_old.inspector, v_old.referral, v_old.permit_required,
    v_old.pdf_options, v_old.auto_attached_library_ids, v_old.id);

  insert into public.line_items (proposal_id, description, quantity, unit, unit_price, sort_order)
  select v_new, description, quantity, unit, unit_price, sort_order
  from public.line_items where proposal_id = p_id;

  insert into public.sketches (proposal_id, page_number, drawing_path, png_path, annotations, segments, cracks)
  select v_new, page_number, drawing_path, png_path, annotations, segments, cracks
  from public.sketches where proposal_id = p_id;

  insert into public.photos (proposal_id, image_path, markup_drawing_path, markup_png_path, caption, sort_order)
  select v_new, image_path, markup_drawing_path, markup_png_path, caption, sort_order
  from public.photos where proposal_id = p_id;

  insert into public.proposal_documents (proposal_id, title, file_path, sort_order)
  select v_new, title, file_path, sort_order
  from public.proposal_documents where proposal_id = p_id;

  for v_bp in select * from public.blueprints where proposal_id = p_id loop
    insert into public.blueprints (proposal_id, caption, sort_order, pixels_per_foot, detected_pdf_scale, pdf_rasterization_scale)
    values (v_new, v_bp.caption, v_bp.sort_order, v_bp.pixels_per_foot, v_bp.detected_pdf_scale, v_bp.pdf_rasterization_scale)
    returning id into v_nbp;
    insert into public.blueprint_pages (blueprint_id, sort_order, image_path, measurements)
    select v_nbp, sort_order, image_path, measurements
    from public.blueprint_pages where blueprint_id = v_bp.id;
  end loop;

  update public.proposals set is_archived = true where id = p_id;
  return v_new;
end $$;

-- =============================================================================
-- 10. Row Level Security
-- =============================================================================
alter table public.organizations      enable row level security;
alter table public.profiles           enable row level security;
alter table public.number_counters    enable row level security;  -- no policies: functions only
alter table public.customers          enable row level security;
alter table public.jobs               enable row level security;
alter table public.proposals          enable row level security;
alter table public.line_items         enable row level security;
alter table public.sketches           enable row level security;
alter table public.blueprints         enable row level security;
alter table public.blueprint_pages    enable row level security;
alter table public.library_documents  enable row level security;
alter table public.proposal_documents enable row level security;
alter table public.inspection_reports enable row level security;
alter table public.photos             enable row level security;
alter table public.signatures         enable row level security;
alter table public.share_links        enable row level security;
alter table public.activity_log       enable row level security;

-- Organizations
create policy org_select on public.organizations for select to authenticated
  using (id = public.auth_org_id());
create policy org_update on public.organizations for update to authenticated
  using (id = public.auth_org_id() and public.auth_app_role() = 'admin')
  with check (id = public.auth_org_id());

-- Profiles: everyone in the org can see the team; you can edit your own name; admins edit anyone
create policy profiles_select on public.profiles for select to authenticated
  using (org_id = public.auth_org_id() or id = auth.uid());
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid() or (org_id = public.auth_org_id() and public.auth_app_role() = 'admin'))
  with check (org_id = public.auth_org_id());

-- Customers and jobs: org sees all; reps/technicians create; owner or manager edits; manager deletes
create policy customers_select on public.customers for select to authenticated
  using (org_id = public.auth_org_id());
create policy customers_insert on public.customers for insert to authenticated
  with check (org_id = public.auth_org_id() and public.auth_app_role() in ('admin','manager','sales_rep','technician'));
create policy customers_update on public.customers for update to authenticated
  using (org_id = public.auth_org_id() and (public.auth_is_manager() or owner_id = auth.uid()))
  with check (org_id = public.auth_org_id());
create policy customers_delete on public.customers for delete to authenticated
  using (org_id = public.auth_org_id() and public.auth_is_manager());

create policy jobs_select on public.jobs for select to authenticated
  using (org_id = public.auth_org_id());
create policy jobs_insert on public.jobs for insert to authenticated
  with check (org_id = public.auth_org_id() and public.auth_app_role() in ('admin','manager','sales_rep','technician'));
create policy jobs_update on public.jobs for update to authenticated
  using (org_id = public.auth_org_id() and (public.auth_is_manager() or owner_id = auth.uid()))
  with check (org_id = public.auth_org_id());
create policy jobs_delete on public.jobs for delete to authenticated
  using (org_id = public.auth_org_id() and public.auth_is_manager());

-- Proposals
create policy proposals_select on public.proposals for select to authenticated
  using (org_id = public.auth_org_id());
create policy proposals_insert on public.proposals for insert to authenticated
  with check (org_id = public.auth_org_id()
              and (public.auth_is_manager()
                   or (public.auth_app_role() = 'sales_rep' and owner_id = auth.uid())));
create policy proposals_update on public.proposals for update to authenticated
  using (org_id = public.auth_org_id()
         and (public.auth_is_manager()
              or public.auth_app_role() = 'office'
              or (public.auth_app_role() = 'sales_rep'
                  and (owner_id = auth.uid() or auth.uid() = any (collaborator_ids)))))
  with check (org_id = public.auth_org_id());
create policy proposals_delete on public.proposals for delete to authenticated
  using (org_id = public.auth_org_id()
         and (public.auth_is_manager()
              or (owner_id = auth.uid() and status = 'draft')));

-- Proposal children: view if you can see the proposal, write if you can edit it
create policy line_items_select on public.line_items for select to authenticated using (public.can_view_proposal(proposal_id));
create policy line_items_write  on public.line_items for all    to authenticated using (public.can_edit_proposal(proposal_id)) with check (public.can_edit_proposal(proposal_id));

create policy sketches_select on public.sketches for select to authenticated using (public.can_view_proposal(proposal_id));
create policy sketches_write  on public.sketches for all    to authenticated using (public.can_edit_proposal(proposal_id)) with check (public.can_edit_proposal(proposal_id));

create policy blueprints_select on public.blueprints for select to authenticated using (public.can_view_proposal(proposal_id));
create policy blueprints_write  on public.blueprints for all    to authenticated using (public.can_edit_proposal(proposal_id)) with check (public.can_edit_proposal(proposal_id));

create policy blueprint_pages_select on public.blueprint_pages for select to authenticated
  using (exists (select 1 from public.blueprints b where b.id = blueprint_id and public.can_view_proposal(b.proposal_id)));
create policy blueprint_pages_write on public.blueprint_pages for all to authenticated
  using (exists (select 1 from public.blueprints b where b.id = blueprint_id and public.can_edit_proposal(b.proposal_id)))
  with check (exists (select 1 from public.blueprints b where b.id = blueprint_id and public.can_edit_proposal(b.proposal_id)));

create policy proposal_documents_select on public.proposal_documents for select to authenticated using (public.can_view_proposal(proposal_id));
create policy proposal_documents_write  on public.proposal_documents for all    to authenticated using (public.can_edit_proposal(proposal_id)) with check (public.can_edit_proposal(proposal_id));

create policy share_links_select on public.share_links for select to authenticated using (public.can_view_proposal(proposal_id));
create policy share_links_insert on public.share_links for insert to authenticated with check (public.can_edit_proposal(proposal_id));
create policy share_links_update on public.share_links for update to authenticated using (public.can_edit_proposal(proposal_id)) with check (public.can_edit_proposal(proposal_id));

-- Literature library: everyone reads, managers maintain
create policy library_select on public.library_documents for select to authenticated using (org_id = public.auth_org_id());
create policy library_write  on public.library_documents for all    to authenticated
  using (org_id = public.auth_org_id() and public.auth_is_manager())
  with check (org_id = public.auth_org_id() and public.auth_is_manager());

-- Inspection reports
create policy inspections_select on public.inspection_reports for select to authenticated
  using (org_id = public.auth_org_id());
create policy inspections_insert on public.inspection_reports for insert to authenticated
  with check (org_id = public.auth_org_id()
              and (public.auth_is_manager()
                   or (public.auth_app_role() in ('sales_rep','technician') and owner_id = auth.uid())));
create policy inspections_update on public.inspection_reports for update to authenticated
  using (public.can_edit_inspection(id)) with check (org_id = public.auth_org_id());
create policy inspections_delete on public.inspection_reports for delete to authenticated
  using (org_id = public.auth_org_id() and public.auth_is_manager());

-- Photos and signatures attach to a proposal OR an inspection
create policy photos_select on public.photos for select to authenticated
  using (case when proposal_id is not null then public.can_view_proposal(proposal_id) else public.can_view_inspection(inspection_id) end);
create policy photos_write on public.photos for all to authenticated
  using (case when proposal_id is not null then public.can_edit_proposal(proposal_id) else public.can_edit_inspection(inspection_id) end)
  with check (case when proposal_id is not null then public.can_edit_proposal(proposal_id) else public.can_edit_inspection(inspection_id) end);

create policy signatures_select on public.signatures for select to authenticated
  using (case when proposal_id is not null then public.can_view_proposal(proposal_id) else public.can_view_inspection(inspection_id) end);
create policy signatures_write on public.signatures for all to authenticated
  using (case when proposal_id is not null then public.can_edit_proposal(proposal_id) else public.can_edit_inspection(inspection_id) end)
  with check (case when proposal_id is not null then public.can_edit_proposal(proposal_id) else public.can_edit_inspection(inspection_id) end);

-- Audit log: read-only for the org
create policy activity_select on public.activity_log for select to authenticated using (org_id = public.auth_org_id());

-- Nothing is reachable without signing in. Customers reach shared proposals only through
-- an Edge Function that checks the share token (Phase 4).
revoke all on all tables in schema public from anon;
revoke all on public.number_counters from anon, authenticated;
revoke insert, update, delete on public.activity_log from authenticated;
revoke execute on function public.next_document_number(uuid, text) from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- =============================================================================
-- 11. File storage
--     One private bucket. Paths start with the org id:
--       <org_id>/proposals/<proposal_id>/photos/<file>.jpg
--       <org_id>/inspections/<inspection_id>/...
--       <org_id>/library/<file>.pdf
-- =============================================================================
insert into storage.buckets (id, name, public, file_size_limit)
values ('eco-files', 'eco-files', false, 52428800)  -- 50 MB per file
on conflict (id) do nothing;

create policy eco_files_select on storage.objects for select to authenticated
  using (bucket_id = 'eco-files' and (storage.foldername(name))[1] = public.auth_org_id()::text);
create policy eco_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'eco-files' and (storage.foldername(name))[1] = public.auth_org_id()::text
              and public.auth_app_role() <> 'office');
create policy eco_files_update on storage.objects for update to authenticated
  using (bucket_id = 'eco-files' and (storage.foldername(name))[1] = public.auth_org_id()::text
         and public.auth_app_role() <> 'office');
create policy eco_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'eco-files' and (storage.foldername(name))[1] = public.auth_org_id()::text
         and public.auth_is_manager());

-- =============================================================================
-- 12. Realtime: these tables push live changes to open screens
-- =============================================================================
alter publication supabase_realtime add table
  public.customers, public.jobs, public.proposals, public.line_items, public.sketches,
  public.photos, public.signatures, public.inspection_reports;

-- =============================================================================
-- 13. Seed: Eco-Seal organization (values from CompanyInfo.swift)
-- =============================================================================
insert into public.organizations
  (name, street, city_state_zip, phone, website, allowed_email_domain, bootstrap_admin_email, default_tax_rate, default_terms)
values
  ('Eco-Seal Home Solutions', '3530 County Road 58', 'Millersburg, OH 44654', '330.893.7325',
   'ecosealsolutions.com', 'ecosealsolutions.com', 'mike@ecosealsolutions.com', 0,
   '20% deposit due upon acceptance. Balance due upon project completion. Prices valid for 30 days from proposal date.');
