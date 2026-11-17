-- 18 Nov module (built 17 Nov): master data 1 - company settings, customers, suppliers, stages.

-- Stages added on the fly from the routing / hold / QC-result screens use category 'custom'.
alter table public.stages_master drop constraint stages_master_category_check;
alter table public.stages_master add constraint stages_master_category_check
  check (category in ('rm','machining','outsource','custom'));

-- Stage IDs from the database (the 12 built-in stages are STG-001..STG-012).
insert into public.id_counters (prefix, next_value, pad) values ('STG', 12, 3)
on conflict (prefix) do nothing;

-- next_id() is used by the ERP for customers (CUS), suppliers (SUP) and stages (STG) from this build on.
