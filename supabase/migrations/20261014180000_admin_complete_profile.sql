-- Existing admins and date of birth (applied to the shared IsdaSafe Supabase
-- project on 2026-10-14). Admins from before birth dates were asked have
-- none on file: AdminGate asks for it at login (admin_set_own_birth_date),
-- and registering again with the same account fills it in
-- (request_admin_access now completes a row that's missing it, or a name).

create or replace function public.admin_set_own_birth_date(p_birth_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if p_birth_date is null then
    raise exception 'Enter your date of birth.' using errcode = 'P0001';
  end if;
  if p_birth_date > (now() at time zone 'Asia/Manila')::date then
    raise exception 'Your date of birth can''t be in the future.' using errcode = 'P0001';
  end if;
  if not public.is_adult(p_birth_date) then
    raise exception 'Admins must be at least 18 years old.' using errcode = 'P0001';
  end if;
  update public.admins set birth_date = p_birth_date where user_id = auth.uid();
end;
$$;

-- Same as before, except an existing row that's missing its date of birth
-- or name gets them from this request (nothing already on file changes).
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
    update public.admins
       set birth_date = coalesce(birth_date, p_birth_date),
           first_name = coalesce(first_name, v_first),
           last_name  = coalesce(last_name, v_last),
           full_name  = case when first_name is null or last_name is null
                             then coalesce(first_name, v_first) || ' ' ||
                                  coalesce(last_name, v_last)
                             else full_name end
     where user_id = v_uid;
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

revoke all on function public.admin_set_own_birth_date(date) from public, anon;
grant execute on function public.admin_set_own_birth_date(date) to authenticated;
