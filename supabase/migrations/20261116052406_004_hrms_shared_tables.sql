-- Internal ID issuer (no login check) for use inside triggers; not callable by API users
create or replace function public._issue_id(p_prefix text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare v_n bigint; v_pad int;
begin
  insert into public.id_counters as c (prefix) values (p_prefix)
  on conflict (prefix) do update set next_value = c.next_value + 1, updated_at = now()
  returning c.next_value, c.pad into v_n, v_pad;
  return p_prefix || '-' || lpad(v_n::text, v_pad, '0');
end;
$$;
revoke all on function public._issue_id(text) from public, anon, authenticated;

create table public.designation_role_map (
  designation text primary key,
  erp_role text not null check (erp_role in ('admin','ppc','prodmgr','staff','store','purchase','qi','dispatch')),
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);

create table public.employees (
  id text primary key,
  name text not null,
  designation text references public.designation_role_map(designation),
  phone text,
  email text,
  active boolean not null default true,
  staff_id text unique references public.staff(id) on delete set null,
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);
comment on table public.employees is 'Owned by HRMS (writes via its service connection). ERP reads only.';

create table public.attendance (
  id bigint generated always as identity primary key,
  employee_id text not null references public.employees(id) on delete cascade,
  work_date date not null default (now() at time zone 'Asia/Kolkata')::date,
  check_in timestamptz not null default now(),
  location text not null default 'ERP Login',
  created_at timestamptz not null default now()
);
create index attendance_employee_date_idx on public.attendance (employee_id, work_date);

create table public.leave_records (
  id text primary key,
  employee_id text not null references public.employees(id) on delete cascade,
  from_date date not null,
  to_date date not null,
  leave_type text,
  status text,
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1,
  check (to_date >= from_date)
);
create index leave_records_employee_idx on public.leave_records (employee_id, from_date);

create trigger set_row_meta before insert or update on public.designation_role_map for each row execute function public.set_row_meta();
create trigger set_row_meta before insert or update on public.employees for each row execute function public.set_row_meta();
create trigger set_row_meta before insert or update on public.leave_records for each row execute function public.set_row_meta();

-- Auto role-provisioning: an HRMS employee with a mapped designation gets / keeps a matching ERP staff row.
-- (The Supabase login itself is created by the login Edge Function on 17 Nov.)
create or replace function public.provision_staff_from_employee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_role text;
begin
  select m.erp_role into v_role from public.designation_role_map m where m.designation = new.designation;
  if v_role is null then
    if new.staff_id is not null then
      update public.staff set active = false, version = version where id = new.staff_id;
    end if;
    return new;
  end if;
  if new.staff_id is null then
    new.staff_id := public._issue_id('ST');
    insert into public.staff (id, name, role, active) values (new.staff_id, new.name, v_role, new.active);
  else
    update public.staff set name = new.name, role = v_role, active = new.active, version = version
    where id = new.staff_id;
  end if;
  return new;
end;
$$;
create trigger provision_staff before insert or update of name, designation, active on public.employees
  for each row execute function public.provision_staff_from_employee();
