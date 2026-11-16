-- 17 Nov module (built 16 Nov): staff logins with 4-digit PINs.
-- Each staff row gets a Supabase Auth user. Login identifier: <staff id>@staff.suruerp.invalid (never emailed).
-- Password: 'Suru#' || PIN (the ERP adds the prefix; Supabase needs >= 6 characters). Stored bcrypt-hashed by Supabase.

create or replace function public._staff_login_email(p_staff_id text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(p_staff_id) || '@staff.suruerp.invalid'
$$;

-- Internal: create or update the login for one staff row. Not callable through the API.
create or replace function public._set_login_password(p_staff_id text, p_pin text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_email text := public._staff_login_email(p_staff_id);
  v_hash text;
begin
  if p_pin !~ '^[0-9]{4}$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;
  v_hash := extensions.crypt('Suru#' || p_pin, extensions.gen_salt('bf'));
  select user_id into v_uid from public.staff where id = p_staff_id;
  if not found then
    raise exception 'Staff % not found', p_staff_id;
  end if;

  if v_uid is null then
    v_uid := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      email_change_token_current, phone_change, phone_change_token, reauthentication_token
    ) values (
      '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated', v_email, v_hash, now(),
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'), 'staff_id', p_staff_id),
      jsonb_build_object('staff_id', p_staff_id), now(), now(),
      '', '', '', '', '', '', '', ''
    );
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, created_at, updated_at)
    values (gen_random_uuid(), v_uid, v_uid::text,
            jsonb_build_object('sub', v_uid::text, 'email', v_email, 'email_verified', true, 'phone_verified', false),
            'email', now(), now());
    update public.staff set user_id = v_uid, version = version where id = p_staff_id;
  else
    update auth.users set encrypted_password = v_hash, updated_at = now() where id = v_uid;
  end if;
end;
$$;
revoke all on function public._set_login_password(text, text) from public, anon, authenticated;

-- Login screen: names only, so the dropdowns work before anyone signs in. No PINs, no other fields.
create or replace function public.login_directory()
returns table (id text, name text, role text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, s.name, s.role from public.staff s
  where s.active and s.user_id is not null
  order by s.id
$$;

create or replace function public.login_branding()
returns table (name text, short_name text, tagline text, brand_color text)
language sql
stable
security definer
set search_path = ''
as $$
  select c.name, c.short_name, c.tagline, c.brand_color from public.company_settings c where c.id = 1
$$;
revoke all on function public.login_directory(), public.login_branding() from public;
grant execute on function public.login_directory(), public.login_branding() to anon, authenticated;

-- Set or reset a PIN.
--   Admin (adminhub): any staff, no current PIN needed (used for new staff and "forgot PIN").
--   Anyone else: only their own login, and only with the correct current PIN.
create or replace function public.set_staff_pin(p_staff_id text, p_new_pin text, p_current_pin text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_self text;
  v_hash text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  select s.id into v_self from public.staff s where s.user_id = auth.uid() and s.active;
  if v_self is null then
    raise exception 'not_staff';
  end if;
  if p_new_pin !~ '^[0-9]{4}$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;

  if v_self = p_staff_id then
    select u.encrypted_password into v_hash from auth.users u where u.id = auth.uid();
    if p_current_pin is null or v_hash is distinct from extensions.crypt('Suru#' || p_current_pin, v_hash) then
      raise exception 'Current PIN is incorrect';
    end if;
  elsif not public.can('adminhub') then
    raise exception 'Only Admin can set another person''s PIN';
  end if;

  perform public._set_login_password(p_staff_id, p_new_pin);
end;
$$;
revoke all on function public.set_staff_pin(text, text, text) from public, anon;
grant execute on function public.set_staff_pin(text, text, text) to authenticated;

-- Add a staff member and their login in one step (Admin only). Returns the new staff ID.
create or replace function public.create_staff(p_name text, p_role text, p_stages text[], p_pin text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare v_id text;
begin
  if not public.can('adminhub') then
    raise exception 'Only Admin can add staff';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'Name is required';
  end if;
  if p_pin !~ '^[0-9]{4}$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;
  v_id := public._issue_id('ST');
  insert into public.staff (id, name, role, stages, active)
  values (v_id, trim(p_name), p_role, coalesce(p_stages, '{}'), true);
  perform public._set_login_password(v_id, p_pin);
  return v_id;
end;
$$;
revoke all on function public.create_staff(text, text, text[], text) from public, anon;
grant execute on function public.create_staff(text, text, text[], text) to authenticated;

-- Who am I (one call after sign-in): my staff row plus my role's permission areas.
create or replace function public.my_session()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s.id, 'name', s.name, 'role', s.role, 'stages', to_jsonb(s.stages), 'active', s.active
  )
  from public.staff s where s.user_id = auth.uid()
$$;
revoke all on function public.my_session() from public, anon;
grant execute on function public.my_session() to authenticated;
