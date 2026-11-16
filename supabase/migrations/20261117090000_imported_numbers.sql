-- =============================================================================
-- Imported document numbers (Phase 3, session 3)
-- iPads numbered proposals on their own (P-2026-0001...). When those proposals
-- upload to the cloud they keep their number if it's free. If another iPad
-- already used it, the rep's initials are added (P-2026-0001-DY), then -2, -3...
-- The shared counter is moved past every imported number so new numbers from
-- the database can never collide with them.
-- =============================================================================

create function public.import_document_number(
  p_org uuid, p_prefix text, p_number text, p_owner uuid, p_table text
) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_match    text[];
  v_initials text;
  v_candidate text := p_number;
  v_try      int := 1;
  v_taken    boolean;
begin
  -- 1. Keep the shared counter ahead of imported numbers (P-YYYY-NNNN / SR-YYYY-NNNN)
  v_match := regexp_match(p_number, '^' || p_prefix || '-(\d{4})-(\d+)');
  if v_match is not null then
    insert into public.number_counters (org_id, prefix, year, last_used)
    values (p_org, p_prefix, v_match[1]::int, v_match[2]::int)
    on conflict (org_id, prefix, year)
    do update set last_used = greatest(public.number_counters.last_used, excluded.last_used);
  end if;

  -- 2. Find a free number
  loop
    if p_table = 'proposals' then
      select exists (select 1 from public.proposals where org_id = p_org and number = v_candidate) into v_taken;
    else
      select exists (select 1 from public.inspection_reports where org_id = p_org and number = v_candidate) into v_taken;
    end if;
    exit when not v_taken;

    if v_initials is null then
      select upper(string_agg(left(w, 1), '')) into v_initials
      from public.profiles pr, regexp_split_to_table(trim(pr.full_name), '\s+') w
      where pr.id = p_owner and w <> '';
      v_initials := coalesce(nullif(v_initials, ''), 'X');
      v_candidate := p_number || '-' || v_initials;
    else
      v_try := v_try + 1;
      v_candidate := p_number || '-' || v_initials || '-' || v_try;
    end if;
  end loop;

  return v_candidate;
end $$;

revoke execute on function public.import_document_number(uuid, text, text, uuid, text) from public, anon, authenticated;

-- Proposals: database number when none given, otherwise keep/adjust the imported one
create or replace function public.proposals_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_org public.organizations%rowtype;
begin
  select * into v_org from public.organizations where id = new.org_id;
  new.owner_id := coalesce(new.owner_id, auth.uid());
  if coalesce(new.number, '') = '' then
    new.number := public.next_document_number(new.org_id, 'P');
  else
    new.number := public.import_document_number(new.org_id, 'P', new.number, new.owner_id, 'proposals');
  end if;
  new.down_payment_rate := coalesce(new.down_payment_rate, v_org.down_payment_rate);
  new.updated_by := auth.uid();
  new.version    := 1;
  new.locked_at  := null;
  new.subtotal := 0; new.tax_amount := 0; new.total := 0; new.down_payment := 0; new.balance_due := 0;
  return new;
end $$;

-- Inspection reports: same rule for SR- numbers
create or replace function public.inspections_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.owner_id := coalesce(new.owner_id, auth.uid());
  if coalesce(new.number, '') = '' then
    new.number := public.next_document_number(new.org_id, 'SR');
  else
    new.number := public.import_document_number(new.org_id, 'SR', new.number, new.owner_id, 'inspection_reports');
  end if;
  new.updated_by := auth.uid();
  return new;
end $$;
