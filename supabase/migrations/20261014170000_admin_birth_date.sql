-- Admin date of birth (applied to the shared IsdaSafe Supabase project on
-- 2026-10-14). Admins must be at least 18. The panel checks it as the date is
-- picked; these functions refuse it too, so it can't be skipped. (A CHECK
-- constraint can't use current_date, so it's enforced here instead.)
-- Admins from before this have no date on file.

alter table public.admins add column if not exists birth_date date;

-- Whether someone born on p_birth_date is at least 18 today (Manila time).
create or replace function public.is_adult(p_birth_date date)
returns boolean
language sql
stable
set search_path = ''
as $$
  select p_birth_date is not null
     and p_birth_date <= ((now() at time zone 'Asia/Manila')::date - interval '18 years')::date;
$$;

-- Same as before, plus birth_date from the Register form (refused under 18).
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
  v_birth date;
begin
  if coalesce(new.raw_user_meta_data ->> 'admin_signup', '') <> 'true' then
    return new;
  end if;
  if v_phone !~ '^\+639\d{9}$' then
    v_phone := null;
  end if;
  begin
    v_birth := (new.raw_user_meta_data ->> 'birth_date')::date;
  exception when others then
    v_birth := null;
  end;
  if v_birth is not null and not public.is_adult(v_birth) then
    raise exception 'Admins must be at least 18 years old.' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('public.admins bootstrap'));
  insert into public.admins
    (user_id, full_name, first_name, last_name, email, phone, birth_date, status)
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
    v_birth,
    case when exists (select 1 from public.admins where status = 'approved')
         then 'pending' else 'approved' end
  );
  return new;
end;
$$;

drop function if exists public.request_admin_access(text, text, text);

create or replace function public.request_admin_access(
  p_first_name text,
  p_last_name text,
  p_phone text default null,
  p_birth_date date default null
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
  if p_birth_date is not null and not public.is_adult(p_birth_date) then
    raise exception 'Admins must be at least 18 years old.' using errcode = 'P0001';
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
    (user_id, full_name, first_name, last_name, email, phone, birth_date, status)
  values (
    v_uid, v_first || ' ' || v_last, v_first, v_last, v_email, p_phone,
    p_birth_date, v_status
  );
  return v_status;
end;
$$;

revoke all on function public.request_admin_access(text, text, text, date) from public, anon;
grant execute on function public.request_admin_access(text, text, text, date) to authenticated;
grant execute on function public.is_adult(date) to anon, authenticated;
