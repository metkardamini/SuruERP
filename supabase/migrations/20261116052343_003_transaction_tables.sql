create table public.purchase_orders (
  id text primary key,
  po_no text not null,
  customer_id text references public.customers(id),
  customer_name text,
  po_date date,
  due_date date,
  plant_no text,
  source text,
  status text,
  is_re_received boolean not null default false,
  re_received_from_id text,
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);
create index purchase_orders_po_no_idx on public.purchase_orders (po_no);
create index purchase_orders_customer_idx on public.purchase_orders (customer_id);

create table public.po_items (
  id text primary key,
  po_id text not null references public.purchase_orders(id) on delete cascade,
  line_no int,
  item_code text,
  code_norm text generated always as (public.norm_code(item_code)) stored,
  material text,
  description text,
  qty numeric not null default 0,
  unit text,
  value numeric,
  delivery_date date,
  status text,
  qty_dispatched numeric not null default 0,
  order_id text,
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);
create index po_items_po_idx on public.po_items (po_id);
create index po_items_code_norm_idx on public.po_items (code_norm);

create table public.orders (
  id text primary key,
  process_order_id text,
  po_id text references public.purchase_orders(id),
  po_item_id text references public.po_items(id),
  po_no text,
  customer text,
  customer_item_no text,
  code_norm text generated always as (public.norm_code(customer_item_no)) stored,
  description text,
  part_type text,
  qty numeric not null default 0,
  unit text,
  fg_qty numeric not null default 0,
  fg_qty_released numeric not null default 0,
  mfg_qty numeric not null default 0,
  mfg_type text,
  vendor text,
  rm_supply text,
  batch_id text,
  delivery_date date,
  due_date date,
  express boolean not null default false,
  prod_started boolean not null default false,
  qty_dispatched numeric not null default 0,
  fg_override boolean not null default false,
  fg_override_reason text,
  waiting_on_rm boolean not null default false,
  linked_from_order text,
  linked_shortfall_order text,
  status text,
  stages jsonb not null default '[]',
  fulfilment_plan jsonb not null default '{}',
  assembly_components jsonb not null default '[]',
  acceptance_criteria jsonb not null default '{}',
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);
create index orders_po_idx on public.orders (po_id);
create index orders_po_item_idx on public.orders (po_item_id);
create index orders_code_norm_idx on public.orders (code_norm);
create index orders_status_idx on public.orders (status);

create table public.rm_orders (
  id text primary key,
  supplier_id text references public.suppliers(id),
  supplier_name text,
  part_no text,
  code_norm text generated always as (public.norm_code(part_no)) stored,
  material text, grade text, shape text,
  size text, size_unit text,
  piece_len numeric, piece_len_unit text, pieces int,
  qty numeric, unit text, price numeric, min_qty numeric,
  ordered_on date, expected_date date, grn_date date,
  heat_no text, tc_status text,
  ins_date date, ins_result text, ins_notes text,
  route text,
  status text,
  linked_order text,
  linked_orders text[] not null default '{}',
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);
create index rm_orders_supplier_idx on public.rm_orders (supplier_id);
create index rm_orders_code_norm_idx on public.rm_orders (code_norm);
create index rm_orders_status_idx on public.rm_orders (status);

create table public.rm_stock (
  id text primary key,
  part_no text,
  code_norm text generated always as (public.norm_code(part_no)) stored,
  name text, material text, grade text, shape text,
  size text, size_unit text, standard text,
  hsn text check (hsn is null or hsn = '' or hsn ~ '^[0-9]{4,8}$'),
  uom text,
  length_per_kg numeric,
  min_qty numeric, max_qty numeric,
  location text, rack text,
  allocated numeric not null default 0,
  pending_qc_qty numeric not null default 0,
  needs_testing boolean not null default false,
  test_done boolean not null default false,
  qc_queued_at timestamptz,
  supplier text, heat_no text, rate numeric,
  batches jsonb not null default '[]',
  movements jsonb not null default '[]',
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);
create index rm_stock_code_norm_idx on public.rm_stock (code_norm);

create table public.fg_inventory (
  id text primary key,
  part_no text,
  code_norm text generated always as (public.norm_code(part_no)) stored,
  name text, material text, uom text,
  type text not null default 'fg',
  min_qty numeric, max_qty numeric,
  location text,
  opening_stock numeric not null default 0,
  allocated numeric not null default 0,
  batches jsonb not null default '[]',
  movements jsonb not null default '[]',
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);
create index fg_inventory_code_norm_idx on public.fg_inventory (code_norm);

create table public.rejected_items (
  id text primary key,
  order_id text references public.orders(id),
  item_code text,
  description text,
  stage_name text,
  qty numeric not null default 0,
  unit text,
  reason text,
  party text, vendor text, customer text,
  heat_no text,
  rm_order_id text,
  stock_item_id text,
  fg_batch_id text,
  photo_path text,
  notes text,
  rejected_on date,
  rm_batch_summary text,
  rm_batches jsonb not null default '[]',
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);
create index rejected_items_order_idx on public.rejected_items (order_id);

create table public.dispatch_queues (
  id text primary key,
  name text,
  customer_id text references public.customers(id),
  customer_name text,
  ship_to text,
  planned_dispatch_date date,
  shipped boolean not null default false,
  frozen boolean not null default false,
  single_dispatch boolean not null default false,
  items jsonb not null default '[]',
  documents jsonb not null default '[]',
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);
create index dispatch_queues_customer_idx on public.dispatch_queues (customer_id);

create table public.tools (
  id text primary key,
  name text not null,
  qty numeric not null default 0,
  inducted_on date,
  holders jsonb not null default '[]',
  history jsonb not null default '[]',
  calibration jsonb not null default '{}',
  extra jsonb not null default '{}',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);

create table public.activity_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  user_id uuid default auth.uid(),
  by_name text,
  order_id text,
  stage text,
  status text,
  notes text
);
comment on table public.activity_log is 'Append-only audit trail. No update or delete is allowed.';
create index activity_log_order_idx on public.activity_log (order_id);

create table public.product_process_history (
  code_norm text primary key,
  history jsonb not null default '[]',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(), updated_by uuid, version int not null default 1
);

-- Attach row metadata / optimistic locking trigger to every table that carries a version column
do $$
declare t text;
begin
  for t in
    select c.table_name from information_schema.columns c
    where c.table_schema = 'public' and c.column_name = 'version'
  loop
    execute format('create trigger set_row_meta before insert or update on public.%I for each row execute function public.set_row_meta()', t);
  end loop;
end $$;
