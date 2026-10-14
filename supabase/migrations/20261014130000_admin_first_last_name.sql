-- Admin first and last names (applied to the shared IsdaSafe Supabase project
-- on 2026-10-14). full_name stays, kept as "first last", so everything that
-- shows a name keeps working. Admins from before this have null names and
-- are asked for them by the panel at their next login.

alter table public.admins
  add column if not exists first_name text,
  add column if not exists last_name text;

-- Same as before, plus first_name/last_name from the Register form.
create or replace function public.handle_admin_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := new.raw_user_meta_data ->> 'admin_phone';
  v_first text := nullif(trim(new.raw_user_meta_data ->> 'first_name'), '');
  v_last  text := nullif(trim(new.raw_user_meta_data ->> 'last_name'), '');
begin
  if coalesce(new.raw_user_meta_data ->> 'admin_signup', '') <> 'true' then
    return new;
  end if;
  if v_phone !~ '^\+639\d{9}$' then
    v_phone := null;
  end if;
  perform pg_advisory_xact_lock(hashtext('public.admins bootstrap'));
  insert into public.admins
    (user_id, full_name, first_name, last_name, email, phone, status)
  values (
    new.id,
    coalesce(
      nullif(trim(concat_ws(' ', v_first, v_last)), ''),
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      new.email
    ),
    v_first,
    v_last,
    new.email,
    v_phone,
    case when exists (select 1 from public.admins where status = 'approved')
         then 'pending' else 'approved' end
  );
  return new;
end;
$$;

drop function if exists public.request_admin_access(text, text);

create or replace function public.request_admin_access(
  p_first_name text,
  p_last_name text,
  p_phone text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_first  text := nullif(trim(p_first_name), '');
  v_last   text := nullif(trim(p_last_name), '');
  v_email  text;
  v_status text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if v_first is null or v_last is null
     or length(v_first) > 50 or length(v_last) > 50 then
    raise exception 'Enter a first and last name of up to 50 characters each.'
      using errcode = 'P0001';
  end if;
  if p_phone is not null and p_phone !~ '^\+639\d{9}$' then
    raise exception 'Enter a valid Philippine mobile number.' using errcode = 'P0001';
  end if;
  select status into v_status from public.admins where user_id = v_uid;
  if found then
    return v_status;
  end if;
  select email into v_email from auth.users where id = v_uid;
  perform pg_advisory_xact_lock(hashtext('public.admins bootstrap'));
  v_status := case
    when exists (select 1 from public.admins where status = 'approved')
    then 'pending' else 'approved' end;
  insert into public.admins
    (user_id, full_name, first_name, last_name, email, phone, status)
  values (
    v_uid, v_first || ' ' || v_last, v_first, v_last, v_email, p_phone, v_status
  );
  return v_status;
end;
$$;

-- Sets the caller's first and last name (and full_name to match).
create or replace function public.admin_set_own_name(
  p_first_name text,
  p_last_name text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_first text := nullif(trim(p_first_name), '');
  v_last  text := nullif(trim(p_last_name), '');
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if v_first is null or v_last is null
     or length(v_first) > 50 or length(v_last) > 50 then
    raise exception 'Enter a first and last name of up to 50 characters each.'
      using errcode = 'P0001';
  end if;
  update public.admins
     set first_name = v_first,
         last_name = v_last,
         full_name = v_first || ' ' || v_last
   where user_id = auth.uid();
end;
$$;

revoke all on function public.request_admin_access(text, text, text) from public, anon;
revoke all on function public.admin_set_own_name(text, text) from public, anon;
grant execute on function public.request_admin_access(text, text, text) to authenticated;
grant execute on function public.admin_set_own_name(text, text) to authenticated;
