-- =============================================================================
-- EcoProposal — permission and business-rule smoke test
-- Run in the Supabase SQL Editor AFTER the initial schema migration.
--
-- All tests run inside one database function and everything they create
-- (test users, customers, proposals) is undone automatically at the end.
-- Success = the results panel shows one row: ALL TESTS PASSED
-- Failure = a red error naming the test (T1..T12) that failed.
-- =============================================================================

create or replace function public.eco_run_tests() returns text
language plpgsql as $$
declare
  u_admin   constant uuid := '00000000-0000-0000-0000-0000000000a1';
  u_rep1    constant uuid := '00000000-0000-0000-0000-0000000000a2';
  u_rep2    constant uuid := '00000000-0000-0000-0000-0000000000a3';
  u_office  constant uuid := '00000000-0000-0000-0000-0000000000a4';
  u_manager constant uuid := '00000000-0000-0000-0000-0000000000a5';
  u_outside constant uuid := '00000000-0000-0000-0000-0000000000a6';
  v_org  uuid;
  v_c    uuid;
  v_j    uuid;
  v_p    uuid;
  v_p2   uuid;
  v_new  uuid;
  v_num  text;
  v_num2 text;
  v_rows int;
  v_v    int;
  r      public.proposals%rowtype;
begin
  begin  -- everything in this block is rolled back at the end

    -- ------------------------------------------------------------ T1 sign-up rules
    -- (open sign-up on for this test only; everything here is rolled back)
    update public.organizations set open_signup = true;
    insert into auth.users (id, email, raw_user_meta_data) values
      (u_admin,   'test.admin@ecosealsolutions.com',   '{"full_name":"Test Admin"}'),
      (u_rep1,    'test.rep1@ecosealsolutions.com',    '{"full_name":"Rep One"}'),
      (u_rep2,    'test.rep2@ecosealsolutions.com',    '{"full_name":"Rep Two"}'),
      (u_office,  'test.office@ecosealsolutions.com',  '{"full_name":"Office"}'),
      (u_manager, 'test.manager@ecosealsolutions.com', '{"full_name":"Manager"}'),
      (u_outside, 'someone@gmail.com',                 '{"full_name":"Outsider"}');

    update public.profiles set role = 'admin'   where id = u_admin;
    update public.profiles set role = 'office'  where id = u_office;
    update public.profiles set role = 'manager' where id = u_manager;

    assert (select count(*) from public.profiles where email like 'test.%@ecosealsolutions.com') = 5,
      'T1: company sign-ins should get profiles';
    assert not exists (select 1 from public.profiles where email = 'someone@gmail.com'),
      'T1: outside email must NOT get a profile';

    -- ------------------------------------------------------------ T2 Rep One creates
    perform set_config('request.jwt.claims', json_build_object('sub', u_rep1, 'role', 'authenticated')::text, true);
    set local role authenticated;

    v_org := public.auth_org_id();
    assert v_org is not null, 'T2: rep one should belong to the org';
    insert into public.customers (org_id, owner_id, name) values (v_org, u_rep1, 'Test Homeowner') returning id into v_c;
    insert into public.jobs (org_id, customer_id, owner_id, title) values (v_org, v_c, u_rep1, 'Basement') returning id into v_j;
    insert into public.proposals (org_id, job_id, owner_id, tax_rate) values (v_org, v_j, u_rep1, 0.0725)
      returning id, number into v_p, v_num;
    assert v_num ~ '^P-\d{4}-\d{4}$', 'T2: proposal number format, got ' || coalesce(v_num, 'null');

    insert into public.proposals (org_id, owner_id) values (v_org, u_rep1) returning id, number into v_p2, v_num2;
    assert v_num2 <> v_num, 'T2: proposal numbers must be unique';
    delete from public.proposals where id = v_p2;
    get diagnostics v_rows = row_count;
    assert v_rows = 1, 'T2: reps may delete their own drafts';

    insert into public.line_items (proposal_id, description, quantity, unit, unit_price, sort_order) values
      (v_p, 'Exterior waterproofing', 45, 'lin ft', 120.00, 1),
      (v_p, 'Sump pump',               1, 'ea',     850.00, 2);

    -- ------------------------------------------------------------ T3 totals
    -- 45*120 + 850 = 6250.00; tax 7.25% = 453.13; total 6703.13; 20% = 1340.63; balance 5362.50
    select * into r from public.proposals where id = v_p;
    assert r.subtotal = 6250.00,     'T3: subtotal, got ' || r.subtotal;
    assert r.tax_amount = 453.13,    'T3: tax, got ' || r.tax_amount;
    assert r.total = 6703.13,        'T3: total, got ' || r.total;
    assert r.down_payment = 1340.63, 'T3: 20% deposit, got ' || r.down_payment;
    assert r.balance_due = 5362.50,  'T3: balance, got ' || r.balance_due;
    assert r.version = 1,            'T3: line-item changes should not bump version, got ' || r.version;

    -- ------------------------------------------------------------ T4 Rep Two: sees, cannot edit
    reset role;
    perform set_config('request.jwt.claims', json_build_object('sub', u_rep2, 'role', 'authenticated')::text, true);
    set local role authenticated;

    assert exists (select 1 from public.proposals where id = v_p), 'T4: rep two should SEE the proposal';
    update public.proposals set terms = 'hacked' where id = v_p;
    get diagnostics v_rows = row_count;
    assert v_rows = 0, 'T4: rep two must not edit another rep''s proposal';
    begin
      insert into public.line_items (proposal_id, description) values (v_p, 'sneaky');
      raise exception 'T4: rep two must not add line items';
    exception when insufficient_privilege then null;
    end;
    delete from public.proposals where id = v_p;
    get diagnostics v_rows = row_count;
    assert v_rows = 0, 'T4: rep two must not delete it';

    -- ------------------------------------------------------------ T5 Office: status only
    reset role;
    perform set_config('request.jwt.claims', json_build_object('sub', u_office, 'role', 'authenticated')::text, true);
    set local role authenticated;

    update public.proposals set status = 'sent' where id = v_p;
    assert (select status from public.proposals where id = v_p) = 'sent', 'T5: office can change status';
    begin
      update public.proposals set tax_rate = 0 where id = v_p;
      raise exception 'T5: office must not change tax rate';
    exception when raise_exception then
      if sqlerrm like 'T5:%' then raise; end if;
    end;

    -- ------------------------------------------------------------ T6 Manager edits anything
    reset role;
    perform set_config('request.jwt.claims', json_build_object('sub', u_manager, 'role', 'authenticated')::text, true);
    set local role authenticated;

    select version into v_v from public.proposals where id = v_p;
    update public.proposals set terms = 'Net 30' where id = v_p;
    assert (select terms from public.proposals where id = v_p) = 'Net 30', 'T6: manager can edit';
    assert (select version from public.proposals where id = v_p) = v_v + 1, 'T6: edit bumps version';

    -- ------------------------------------------------------------ T7 Sign, lock, new version
    reset role;
    perform set_config('request.jwt.claims', json_build_object('sub', u_rep1, 'role', 'authenticated')::text, true);
    set local role authenticated;

    insert into public.signatures (proposal_id, party, signer_name) values (v_p, 'customer', 'Test Homeowner');
    assert (select locked_at from public.proposals where id = v_p) is null, 'T7: one signature should not lock';
    insert into public.signatures (proposal_id, party, signer_name) values (v_p, 'sales_rep', 'Rep One');
    assert (select locked_at from public.proposals where id = v_p) is not null, 'T7: both signatures should lock';

    begin
      update public.line_items set unit_price = 1 where proposal_id = v_p;
      raise exception 'T7: locked line items must not change';
    exception when raise_exception then if sqlerrm like 'T7:%' then raise; end if;
    end;
    begin
      update public.proposals set tax_rate = 0 where id = v_p;
      raise exception 'T7: locked proposal header must not change';
    exception when raise_exception then if sqlerrm like 'T7:%' then raise; end if;
    end;
    update public.proposals set status = 'accepted' where id = v_p;   -- allowed on a locked proposal

    v_new := public.create_proposal_version(v_p);
    select * into r from public.proposals where id = v_new;
    assert r.supersedes_id = v_p and r.status = 'draft' and r.locked_at is null, 'T7: new version is an unlocked draft';
    assert r.total = 6703.13, 'T7: new version keeps line items + totals, got ' || r.total;
    assert (select count(*) from public.signatures where proposal_id = v_new) = 0, 'T7: signatures not copied';
    assert (select is_archived from public.proposals where id = v_p), 'T7: original archived';

    -- ------------------------------------------------------------ T8 Admin rules
    reset role;
    perform set_config('request.jwt.claims', json_build_object('sub', u_admin, 'role', 'authenticated')::text, true);
    set local role authenticated;

    begin
      delete from public.proposals where id = v_p;
      raise exception 'T8: signed proposal must not be deletable';
    exception when raise_exception then if sqlerrm like 'T8:%' then raise; end if;
    end;
    update public.profiles set role = 'technician' where id = u_rep2;
    assert (select role from public.profiles where id = u_rep2) = 'technician', 'T8: admin can change roles';

    -- ------------------------------------------------------------ T9 No self-promotion
    reset role;
    perform set_config('request.jwt.claims', json_build_object('sub', u_rep1, 'role', 'authenticated')::text, true);
    set local role authenticated;

    begin
      update public.profiles set role = 'admin' where id = u_rep1;
      raise exception 'T9: rep must not change own role';
    exception when raise_exception then if sqlerrm like 'T9:%' then raise; end if;
    end;
    update public.profiles set full_name = 'Rep 1' where id = u_rep1;   -- own name is fine

    -- ------------------------------------------------------------ T10 Outsider sees nothing
    reset role;
    perform set_config('request.jwt.claims', json_build_object('sub', u_outside, 'role', 'authenticated')::text, true);
    set local role authenticated;

    assert (select count(*) from public.proposals) = 0, 'T10: outsider must see no proposals';
    assert (select count(*) from public.customers) = 0, 'T10: outsider must see no customers';

    -- ------------------------------------------------------------ T11 Anonymous blocked
    reset role;
    perform set_config('request.jwt.claims', '{}', true);
    set local role anon;
    begin
      perform 1 from public.proposals limit 1;
      raise exception 'T11: anonymous must not read proposals';
    exception when insufficient_privilege then null;
    end;

    -- ------------------------------------------------------------ T12 Audit log
    reset role;
    assert (select count(*) from public.activity_log where entity = 'proposals' and entity_id = v_p) >= 4,
      'T12: proposal changes are logged';
    assert exists (select 1 from public.activity_log where entity_id = v_p and diff ? 'terms'),
      'T12: field-level diff recorded';

    -- All passed: throw a private signal so every test row above is rolled back
    raise exception using errcode = 'ECO00', message = 'rollback test data';
  exception
    when sqlstate 'ECO00' then
      return 'ALL TESTS PASSED';
  end;
end $$;

select public.eco_run_tests() as result;

drop function public.eco_run_tests();
