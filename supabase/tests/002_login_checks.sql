-- Login & PIN checks (16 Nov 2026). Run in the Supabase SQL editor.
-- Needs the demo logins (Demo Staff 1 = 1111, Demo Staff 4 = 4444). Ends with RAISE EXCEPTION on purpose:
-- the report is in the error message and every change is rolled back. Expected: 11 lines, all PASS.
do $$
declare rep text := ''; u_admin uuid; u_qc uuid; v text; n int; j jsonb;
begin
  select user_id into u_admin from public.staff where id='ST-001';
  select user_id into u_qc from public.staff where id='ST-004';
  select count(*) into n from auth.users u where u.id=u_admin and u.encrypted_password = extensions.crypt('Suru#1111', u.encrypted_password);
  rep := rep || E'\nL1 PIN 1111 matches Demo Staff 1 login: ' || case when n=1 then 'PASS' else 'FAIL' end;

  execute 'set local role anon';
  select count(*) into n from public.login_directory();
  rep := rep || E'\nL2 logged-out login list shows ' || n || ' names: ' || case when n=4 then 'PASS' else 'FAIL' end;
  select name into v from public.login_branding();
  rep := rep || E'\nL3 logged-out branding: ' || coalesce(v,'none') || case when v='Suru Industries' then ' PASS' else ' FAIL' end;
  begin perform public.set_staff_pin('ST-001','9999');
    rep := rep || E'\nL4 logged-out PIN change: FAIL (allowed)';
  exception when insufficient_privilege then rep := rep || E'\nL4 logged-out cannot change PINs: PASS'; end;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', u_qc, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  j := public.my_session();
  rep := rep || E'\nL5 my_session as QC: ' || (j->>'id') || ' ' || (j->>'role') || case when j->>'id'='ST-004' and j->>'role'='qi' then ' PASS' else ' FAIL' end;
  begin perform public.set_staff_pin('ST-004','5555','0000');
    rep := rep || E'\nL6 own PIN with wrong current: FAIL (allowed)';
  exception when others then rep := rep || E'\nL6 own PIN change with wrong current PIN refused: PASS'; end;
  begin perform public.set_staff_pin('ST-001','5555');
    rep := rep || E'\nL7 QC sets Admin PIN: FAIL (allowed)';
  exception when others then rep := rep || E'\nL7 QC cannot set someone else''s PIN: PASS'; end;
  begin perform public.create_staff('Hacker','admin','{}','1234');
    rep := rep || E'\nL8 QC adds staff: FAIL (allowed)';
  exception when others then rep := rep || E'\nL8 QC cannot add staff: PASS'; end;
  perform public.set_staff_pin('ST-004','5555','4444');
  execute 'reset role';
  select count(*) into n from auth.users u where u.id=u_qc and u.encrypted_password = extensions.crypt('Suru#5555', u.encrypted_password);
  rep := rep || E'\nL9 own PIN change with correct current PIN: ' || case when n=1 then 'PASS' else 'FAIL' end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_admin, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  v := public.create_staff('Demo Staff 5','store','{}','5050');
  perform public.set_staff_pin('ST-003','7777');
  execute 'reset role';
  select count(*) into n from public.staff s join auth.users u on u.id=s.user_id where s.id=v and s.role='store'
     and u.encrypted_password = extensions.crypt('Suru#5050', u.encrypted_password);
  rep := rep || E'\nL10 Admin adds staff with login: ' || v || case when v='ST-005' and n=1 then ' PASS' else ' FAIL' end;
  select count(*) into n from public.staff s join auth.users u on u.id=s.user_id where s.id='ST-003'
     and u.encrypted_password = extensions.crypt('Suru#7777', u.encrypted_password);
  rep := rep || E'\nL11 Admin resets a forgotten PIN: ' || case when n=1 then 'PASS' else 'FAIL' end;

  raise exception 'LOGIN TEST REPORT (all changes rolled back):%', rep;
end $$;
