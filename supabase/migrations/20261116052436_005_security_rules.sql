-- Who is logged in, and what may they do
create or replace function public.my_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select s.role from public.staff s where s.user_id = auth.uid() and s.active
$$;

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.staff s where s.user_id = auth.uid() and s.active)
$$;

create or replace function public.can(p_area text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select true from public.staff s where s.user_id = auth.uid() and s.active and s.role = 'admin')
    or exists (
      select 1 from public.staff s
      join public.role_permissions rp on rp.role = s.role
      where s.user_id = auth.uid() and s.active and rp.area = p_area and rp.allowed
    ), false)
$$;

create or replace function public.has_role(p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select s.role = any(p_roles) from public.staff s where s.user_id = auth.uid() and s.active), false)
$$;

revoke all on function public.my_role() from public, anon;
revoke all on function public.is_staff() from public, anon;
revoke all on function public.can(text) from public, anon;
revoke all on function public.has_role(text[]) from public, anon;
grant execute on function public.my_role(), public.is_staff(), public.can(text), public.has_role(text[]) to authenticated;
revoke all on function public.norm_code(text) from anon;

-- Logged-out visitors get nothing at all
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke all on functions from anon;

-- Row-level security on every table
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Standard policies: (table, who can view, who can change). First cut; tuned on each module's build day.
do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('company_settings',     '(select public.is_staff())', '(select public.can(''adminhub''))'),
      ('staff',                '(select public.is_staff())', '(select public.can(''adminhub''))'),
      ('role_permissions',     '(select public.is_staff())', '(select public.can(''adminhub''))'),
      ('customers',            '(select public.is_staff())', '(select public.can(''poinbox'')) or (select public.can(''adminhub''))'),
      ('suppliers',            '(select public.is_staff())', '(select public.has_role(array[''admin'',''purchase'']))'),
      ('supplier_bank_details','(select public.has_role(array[''admin'',''purchase'']))', '(select public.has_role(array[''admin'',''purchase'']))'),
      ('stages_master',        '(select public.is_staff())', '(select public.can(''productdata''))'),
      ('products',             '(select public.is_staff())', '(select public.can(''productdata'')) or (select public.can(''poinbox''))'),
      ('bom_entries',          '(select public.is_staff())', '(select public.can(''productdata'')) or (select public.can(''poinbox''))'),
      ('routings',             '(select public.is_staff())', '(select public.can(''productdata'')) or (select public.can(''poinbox''))'),
      ('drawings',             '(select public.is_staff())', '(select public.can(''productdata'')) or (select public.can(''poinbox''))'),
      ('product_process_history','(select public.is_staff())', '(select public.can(''productdata'')) or (select public.can(''poinbox'')) or (select public.can(''prodqueue''))'),
      ('purchase_orders',      '(select public.can(''poinbox'')) or (select public.can(''proddash'')) or (select public.can(''prodqueue'')) or (select public.has_role(array[''dispatch'']))',
                               '(select public.can(''poinbox'')) or (select public.can(''prodqueue'')) or (select public.has_role(array[''dispatch'']))'),
      ('po_items',             '(select public.can(''poinbox'')) or (select public.can(''proddash'')) or (select public.can(''prodqueue'')) or (select public.has_role(array[''dispatch'']))',
                               '(select public.can(''poinbox'')) or (select public.can(''prodqueue'')) or (select public.has_role(array[''dispatch'']))'),
      ('orders',               '(select public.can(''poinbox'')) or (select public.can(''proddash'')) or (select public.can(''prodqueue'')) or (select public.can(''qc'')) or (select public.has_role(array[''dispatch'']))',
                               '(select public.can(''poinbox'')) or (select public.can(''prodqueue'')) or (select public.can(''qc'')) or (select public.has_role(array[''dispatch'']))'),
      ('rm_orders',            '(select public.can(''procurement'')) or (select public.can(''inward'')) or (select public.can(''rminv'')) or (select public.can(''prodqueue'')) or (select public.can(''qc''))',
                               '(select public.can(''procurement'')) or (select public.can(''inward'')) or (select public.can(''prodqueue'')) or (select public.can(''qc''))'),
      ('rm_stock',             '(select public.can(''rminv'')) or (select public.can(''procurement'')) or (select public.can(''inward'')) or (select public.can(''prodqueue'')) or (select public.can(''poinbox''))',
                               '(select public.can(''rminv'')) or (select public.can(''inward'')) or (select public.can(''prodqueue''))'),
      ('fg_inventory',         '(select public.can(''fgtools'')) or (select public.can(''poinbox'')) or (select public.can(''prodqueue'')) or (select public.has_role(array[''dispatch'']))',
                               '(select public.can(''fgtools'')) or (select public.can(''poinbox'')) or (select public.can(''prodqueue'')) or (select public.has_role(array[''dispatch'']))'),
      ('tools',                '(select public.can(''fgtools''))', '(select public.can(''fgtools''))'),
      ('rejected_items',       '(select public.can(''qc'')) or (select public.can(''failinsights'')) or (select public.can(''prodqueue''))',
                               '(select public.can(''qc'')) or (select public.can(''prodqueue'')) or (select public.can(''inward''))'),
      ('dispatch_queues',      '(select public.has_role(array[''admin'',''dispatch'',''prodmgr'']))', '(select public.has_role(array[''admin'',''dispatch'']))'),
      ('designation_role_map', '(select public.is_staff())', '(select public.can(''adminhub''))')
    ) as v(tbl, read_expr, write_expr)
  loop
    execute format('create policy %I on public.%I for select to authenticated using (%s)', 'view', r.tbl, r.read_expr);
    execute format('create policy %I on public.%I for insert to authenticated with check (%s)', 'add', r.tbl, r.write_expr);
    execute format('create policy %I on public.%I for update to authenticated using (%s) with check (%s)', 'change', r.tbl, r.write_expr, r.write_expr);
    execute format('create policy %I on public.%I for delete to authenticated using (%s)', 'remove', r.tbl, r.write_expr);
  end loop;
end $$;

-- Activity log: anyone logged in can add; viewing follows History / production areas; never edited or deleted
create policy "view" on public.activity_log for select to authenticated
  using ((select public.can('history')) or (select public.can('proddash')) or (select public.can('prodqueue')));
create policy "add" on public.activity_log for insert to authenticated
  with check ((select public.is_staff()) and user_id = (select auth.uid()));
revoke update, delete on public.activity_log from authenticated;

-- HRMS-owned tables: ERP reads only (HRMS writes through its own service connection)
create policy "view" on public.employees for select to authenticated using ((select public.is_staff()));
create policy "view" on public.leave_records for select to authenticated using ((select public.is_staff()));
revoke insert, update, delete on public.employees, public.leave_records from authenticated;

-- Attendance: everyone logged in can read (capacity strip); each user may add only their own check-in
create policy "view" on public.attendance for select to authenticated using ((select public.is_staff()));
create policy "add own check-in" on public.attendance for insert to authenticated
  with check (employee_id in (
    select e.id from public.employees e join public.staff s on s.id = e.staff_id where s.user_id = (select auth.uid())
  ));
revoke update, delete on public.attendance from authenticated;

-- id_counters: RLS on, no policies -> reachable only through next_id()
revoke all on public.id_counters from authenticated;

-- Private file storage for drawings, photos, logos, dispatch documents
insert into storage.buckets (id, name, public, file_size_limit)
values ('erp-files', 'erp-files', false, 20971520)
on conflict (id) do nothing;

create policy "erp staff read files" on storage.objects for select to authenticated
  using (bucket_id = 'erp-files' and (select public.is_staff()));
create policy "erp staff add files" on storage.objects for insert to authenticated
  with check (bucket_id = 'erp-files' and (select public.is_staff()));
create policy "erp staff change files" on storage.objects for update to authenticated
  using (bucket_id = 'erp-files' and (select public.is_staff()));
create policy "erp admin remove files" on storage.objects for delete to authenticated
  using (bucket_id = 'erp-files' and (select public.can('adminhub')));
