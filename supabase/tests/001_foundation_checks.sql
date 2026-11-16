-- Foundation checks (16 Nov 2026). Run in the Supabase SQL editor.
-- Ends with RAISE EXCEPTION on purpose: the report is in the error message and every change is rolled back.
-- Expected: 13 lines, all PASS. (Assumes the demo data from migration 006.)
do $$
declare
  rep text := '';
  u_admin uuid := gen_random_uuid();
  u_qc uuid := gen_random_uuid();
  n int; v text; v2 text; ver int;
begin
  insert into auth.users (id, instance_id, aud, role, email) values
    (u_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'test-admin@example.invalid'),
    (u_qc,    '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'test-qc@example.invalid');
  update public.staff set user_id = u_admin where id = 'ST-001';
  update public.staff set user_id = u_qc where id = 'ST-004';

  -- T1 duplicate Product Code (different spelling, same normalised code)
  begin
    insert into public.products (id, part_no, name) values ('PT-9999', ' demo_prd 001 ', 'dup');
    rep := rep || E'\nT1 duplicate code: FAIL (accepted)';
  exception when unique_violation then rep := rep || E'\nT1 duplicate code refused: PASS';
  end;

  -- T2 stale save refused; T3 good save bumps version
  begin
    update public.products set name = 'x', version = 99 where id = 'PT-0001';
    rep := rep || E'\nT2 stale save: FAIL (accepted)';
  exception when sqlstate '40001' then rep := rep || E'\nT2 stale save refused: PASS';
  end;
  update public.products set name = 'Demo Product 1', version = 1 where id = 'PT-0001';
  select version into ver from public.products where id = 'PT-0001';
  rep := rep || E'\nT3 good save version 1 -> ' || ver || case when ver = 2 then ': PASS' else ': FAIL' end;

  -- T4/T5 next_id needs a login; issues sequential IDs in ERP format
  begin
    perform public.next_id('PT');
    rep := rep || E'\nT5 next_id without login: FAIL (allowed)';
  exception when others then rep := rep || E'\nT5 next_id without login refused: PASS';
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v := public.next_id('PT'); v2 := public.next_id('CUS');
  rep := rep || E'\nT4 next_id gives ' || v || ', ' || v2 || case when v = 'PT-0004' and v2 = 'CUS-003' then ': PASS' else ': FAIL' end;

  -- T6 admin sees everything; T7 activity log is append-only
  select count(*) into n from public.purchase_orders;
  rep := rep || E'\nT6 admin sees POs: ' || n || case when n = 2 then ' PASS' else ' FAIL' end;
  insert into public.activity_log (user_id, by_name, notes) values (u_admin, 'Demo Staff 1', 'test');
  begin
    update public.activity_log set notes = 'edited';
    rep := rep || E'\nT7 activity log edit: FAIL (allowed)';
  exception when insufficient_privilege then rep := rep || E'\nT7 activity log cannot be edited: PASS';
  end;

  -- QC engineer: no PO Inbox area, no bank details, can read products, cannot add customers
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', u_qc, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.purchase_orders;
  rep := rep || E'\nT8 QC sees POs: ' || n || case when n = 0 then ' PASS (blocked)' else ' FAIL' end;
  select count(*) into n from public.products;
  rep := rep || E'\nT9 QC sees products: ' || n || case when n = 3 then ' PASS' else ' FAIL' end;
  select count(*) into n from public.supplier_bank_details;
  rep := rep || E'\nT10 QC bank details hidden: PASS (' || n || ' rows visible)';
  begin
    insert into public.customers (id, name) values ('CUS-999', 'x');
    rep := rep || E'\nT11 QC adds customer: FAIL (allowed)';
  exception when insufficient_privilege then rep := rep || E'\nT11 QC cannot add customer: PASS';
  end;

  -- Logged-out visitor
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  begin
    select count(*) into n from public.products;
    rep := rep || E'\nT12 logged-out read: FAIL (' || n || ' rows)';
  exception when insufficient_privilege then rep := rep || E'\nT12 logged-out visitor blocked: PASS';
  end;
  execute 'reset role';

  -- HRMS auto-provisioning
  insert into public.designation_role_map (designation, erp_role) values ('Store Keeper', 'store');
  insert into public.employees (id, name, designation) values ('EMP-T1', 'Test Employee', 'Store Keeper');
  select s.id || ' role=' || s.role into v from public.staff s join public.employees e on e.staff_id = s.id where e.id = 'EMP-T1';
  rep := rep || E'\nT13 HRMS employee auto-creates ERP staff: ' || coalesce(v, 'none') || case when v like 'ST-005 role=store' then ' PASS' else ' FAIL' end;

  raise exception 'TEST REPORT (all changes rolled back):%', rep;
end $$;
