-- Generic stale-row message (some tables have no "id" column)
create or replace function public.set_row_meta()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.created_by := coalesce(auth.uid(), new.created_by);
    new.updated_at := now();
    new.updated_by := auth.uid();
    new.version := 1;
  else
    if new.version is distinct from old.version then
      raise exception 'stale_row: this % record was changed by someone else - reload and try again', tg_table_name
        using errcode = '40001';
    end if;
    new.version := old.version + 1;
    new.created_at := old.created_at;
    new.created_by := old.created_by;
    new.updated_at := now();
    new.updated_by := auth.uid();
  end if;
  return new;
end;
$$;

create table public.company_settings (
  id smallint primary key default 1 check (id = 1),
  name text not null default '',
  short_name text,
  tagline text,
  address text,
  gst text,
  pan text,
  phone text,
  email text,
  logo_path text,
  logo_light_path text,
  logo_dark_path text,
  brand_color text,
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);

create table public.staff (
  id text primary key,
  name text not null,
  role text not null check (role in ('admin','ppc','prodmgr','staff','store','purchase','qi','dispatch')),
  stages text[] not null default '{}',
  active boolean not null default true,
  user_id uuid unique references auth.users(id) on delete set null,
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);
comment on table public.staff is 'ERP users. PINs are NOT stored here - they are Supabase Auth passwords.';

create table public.role_permissions (
  role text not null check (role in ('admin','ppc','prodmgr','staff','store','purchase','qi','dispatch')),
  area text not null check (area in ('poinbox','proddash','prodqueue','qc','rminv','fgtools','procurement','inward','productdata','adminhub','history','failinsights')),
  allowed boolean not null default false,
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1,
  primary key (role, area)
);

create table public.customers (
  id text primary key,
  name text not null,
  gst text, pan text, address text, contact text, email text, phone text, terms text,
  credit_limit numeric,
  active boolean not null default true,
  address_history jsonb not null default '[]',
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);

create table public.suppliers (
  id text primary key,
  code text unique,
  name text not null,
  contact text, phone text, email text, city text,
  materials text,
  gst text, pan text, msme text, terms text,
  lead_days int,
  vendor_type text,
  active boolean not null default true,
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);

create table public.supplier_bank_details (
  supplier_id text primary key references public.suppliers(id) on delete cascade,
  bank text, account_no text, ifsc text,
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);
comment on table public.supplier_bank_details is 'Kept apart from suppliers so only Admin and Purchase can read it.';

create table public.stages_master (
  id text primary key,
  name text not null unique,
  category text not null check (category in ('rm','machining','outsource')),
  can_qc_after boolean not null default false,
  sort_order int not null default 0,
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);

create table public.products (
  id text primary key,
  part_no text not null,
  code_norm text generated always as (public.norm_code(part_no)) stored,
  name text,
  material text,
  type text,
  uom text,
  weight numeric,
  hsn text check (hsn is null or hsn = '' or hsn ~ '^[0-9]{4,8}$'),
  customer_drawing_no text,
  suru_drawing_no text,
  has_drawing boolean not null default false,
  has_bom boolean not null default false,
  routing_id text,
  status text,
  aliases jsonb not null default '[]',
  dims jsonb not null default '{}',
  documents jsonb not null default '[]',
  history jsonb not null default '[]',
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);
create unique index products_code_norm_key on public.products (code_norm);

create table public.bom_entries (
  id text primary key,
  part_no text not null,
  code_norm text generated always as (public.norm_code(part_no)) stored,
  name text, description text, part_type text, base_material text,
  revision text,
  wastage_pct numeric,
  rm_supply text, vendor text, rate numeric,
  finished_spec text, drawing text,
  route jsonb not null default '[]',
  components jsonb not null default '[]',
  consumables jsonb not null default '[]',
  materials jsonb not null default '[]',
  dimensions jsonb not null default '{}',
  revision_history jsonb not null default '[]',
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);
create index bom_entries_code_norm_idx on public.bom_entries (code_norm);

create table public.routings (
  id text primary key,
  product_code text not null,
  code_norm text generated always as (public.norm_code(product_code)) stored,
  product_name text,
  route_version int not null default 1,
  status text not null default 'active',
  stages jsonb not null default '[]',
  notes text,
  locked_at timestamptz,
  locked_by text,
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1,
  unique (code_norm, route_version)
);

create table public.drawings (
  id text primary key,
  item text,
  order_id text,
  type text,
  revision text,
  customer_ref text,
  suru_ref text,
  file_path text,
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);
