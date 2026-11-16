-- Product Code normalisation: mirrors normCode() in the ERP exactly
create or replace function public.norm_code(s text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when s is null or s = '' then ''
    else coalesce(nullif(regexp_replace(regexp_replace(lower(s), '[\s\-_]+', '', 'g'), '^0+', ''), ''), '0')
  end
$$;

-- Central ID counters (replaces rmC, partC, cusC ... and batchCounters)
create table public.id_counters (
  prefix text primary key,
  next_value bigint not null default 1,
  pad int not null default 4,
  updated_at timestamptz not null default now()
);
alter table public.id_counters enable row level security;
comment on table public.id_counters is 'Server-side ID counters. Read only through public.next_id(). No direct access.';

create or replace function public.next_id(p_prefix text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n bigint;
  v_pad int;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  insert into public.id_counters as c (prefix) values (p_prefix)
  on conflict (prefix) do update set next_value = c.next_value + 1, updated_at = now()
  returning c.next_value, c.pad into v_n, v_pad;
  return p_prefix || '-' || lpad(v_n::text, v_pad, '0');
end;
$$;
revoke all on function public.next_id(text) from public, anon;
grant execute on function public.next_id(text) to authenticated;

-- Row metadata + optimistic locking: a save carrying an old version is refused
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
      raise exception 'stale_row: % % was changed by someone else - reload and try again', tg_table_name, old.id
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
