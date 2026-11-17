-- Master data 1 checks (17 Nov 2026): customers, suppliers + bank details, stages, company settings.
-- Run in the Supabase SQL editor. Needs the demo logins. Ends with RAISE EXCEPTION on purpose:
-- the report is in the error message and every change is rolled back. Expected: 12 lines, all PASS.
do $$
declare rep text := ''; u_admin uuid; u_pm uuid; u_qc uuid; v text; n int; ver int;
begin
  select user_id into u_admin from public.staff where id='ST-001';
  select user_id into u_pm from public.staff where id='ST-002';
  select user_id into u_qc from public.staff where id='ST-004';

  perform set_config('request.jwt.claims', json_build_object('sub', u_admin, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  v := public.next_id('CUS');
  insert into public.customers (id, name, credit_limit, extra) values (v, 'Demo Customer 3', 500000, '{"shipAddress":"x"}');
  rep := rep || E'\nD1 Admin adds customer with server ID ' || v || case when v='CUS-003' then ': PASS' else ': FAIL' end;
  update public.customers set name='Demo Customer 3A', version=1 where id=v;
  select version into ver from public.customers where id=v;
  rep := rep || E'\nD2 customer edit bumps version to ' || ver || case when ver=2 then ': PASS' else ': FAIL' end;
  insert into public.suppliers (id, code, name) values ('SUP-003','SUP-DEMO-003','Demo Supplier 3');
  insert into public.supplier_bank_details (supplier_id, bank, account_no, ifsc) values ('SUP-003','Demo Bank','000111222333','ABCD0123456');
  v := public.next_id('STG');
  insert into public.stages_master (id, name, category, sort_order) values (v, 'Custom From Routing', 'custom', 13);
  rep := rep || E'\nD3 custom stage accepted as ' || v || case when v='STG-013' then ': PASS' else ': FAIL' end;
  update public.company_settings set name='Suru Industries Pvt Ltd', version=1 where id=1;
  rep := rep || E'\nD4 Admin changes company settings: PASS';
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', u_pm, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  update public.company_settings set name='Hacked', version=2 where id=1;
  get diagnostics n = row_count;
  rep := rep || E'\nD5 Prod. Manager company-settings edit changed ' || n || ' rows' || case when n=0 then ': PASS' else ': FAIL' end;
  update public.suppliers set city='Hacked' where id='SUP-001';
  get diagnostics n = row_count;
  rep := rep || E'\nD6 Prod. Manager supplier edit changed ' || n || ' rows' || case when n=0 then ': PASS' else ': FAIL' end;
  select count(*) into n from public.suppliers;
  rep := rep || E'\nD7 Prod. Manager can read suppliers (' || n || ')' || case when n=3 then ': PASS' else ': FAIL' end;
  select count(*) into n from public.supplier_bank_details;
  rep := rep || E'\nD8 Prod. Manager sees ' || n || ' bank rows' || case when n=0 then ': PASS' else ': FAIL' end;
  begin
    insert into public.customers (id, name) values ('CUS-998','x');
    rep := rep || E'\nD9 Prod. Manager (has PO Inbox) adds customer: PASS';
  exception when insufficient_privilege then rep := rep || E'\nD9 Prod. Manager adds customer: FAIL (refused)'; end;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', u_qc, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.supplier_bank_details;
  rep := rep || E'\nD10 QC sees ' || n || ' bank rows' || case when n=0 then ': PASS' else ': FAIL' end;
  begin
    insert into public.stages_master (id, name, category) values ('STG-999','x','custom');
    rep := rep || E'\nD11 QC adds stage: FAIL (allowed)';
  exception when insufficient_privilege then rep := rep || E'\nD11 QC cannot add stages: PASS'; end;
  execute 'reset role';
  select name into v from public.company_settings where id=1;
  rep := rep || E'\nD12 company name after all attempts: ' || v || case when v='Suru Industries Pvt Ltd' then ' PASS' else ' FAIL' end;

  raise exception 'MASTER DATA TEST REPORT (all changes rolled back):%', rep;
end $$;
