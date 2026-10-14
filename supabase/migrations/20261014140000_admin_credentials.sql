-- Admin Settings: change phone number and email (applied to the shared
-- IsdaSafe Supabase project on 2026-10-14).
--
-- Changing the number: admin_check_phone_available is asked before a code
-- is sent (via the farmer app's send-semaphore-otp, which stores the hashed
-- code and the number it went to in public.phone_otps), then
-- admin_change_phone checks the code and only then swaps the number in. The
-- current number stays verified until then, so a change that's abandoned
-- half-way never locks the admin out at the next login (AdminGate requires a
-- verified number).
--
-- Changing the email goes through Supabase Auth (a confirmation link); the
-- trigger below copies the confirmed address onto the admin row.

-- Raises when another verified admin already has p_phone. A farmer account
-- with the same number is fine.
create or replace function public.admin_check_phone_available(p_phone text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if p_phone is null or p_phone !~ '^\+639\d{9}$' then
    raise exception 'Enter a valid Philippine mobile number.' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.admins
     where phone = p_phone and phone_verified and user_id <> auth.uid()
  ) then
    raise exception 'Another admin already uses this number.' using errcode = 'P0001';
  end if;
end;
$$;

-- Checks a code sent to a new number and, if it's right, makes that number
-- the caller's (verified). Returns null on success, otherwise the message to
-- show (a wrong guess is recorded, so it can't be raised and rolled back).
create or replace function public.admin_change_phone(p_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_otp public.phone_otps%rowtype;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if not exists (select 1 from public.admins where user_id = v_uid) then
    raise exception 'Not an admin' using errcode = '42501';
  end if;
  if p_code is null or p_code !~ '^\d{4,8}$' then
    return 'Enter the verification code.';
  end if;
  select * into v_otp from public.phone_otps where user_id = v_uid for update;
  if not found then
    return 'Request a new code.';
  end if;
  if v_otp.locked then
    return 'Too many attempts, request a new code.';
  end if;
  if v_otp.expires_at < now() then
    return 'Code expired, request a new one.';
  end if;
  if encode(extensions.digest(p_code, 'sha256'), 'hex') <> v_otp.code_hash then
    update public.phone_otps
       set attempts = attempts + 1, locked = attempts + 1 >= 5
     where user_id = v_uid;
    return case when v_otp.attempts + 1 >= 5
                then 'Too many attempts, request a new code.'
                else 'Incorrect code.' end;
  end if;
  if exists (
    select 1 from public.admins
     where phone = v_otp.phone and phone_verified and user_id <> v_uid
  ) then
    return 'Another admin already uses this number.';
  end if;
  update public.admins
     set phone = v_otp.phone, phone_verified = true
   where user_id = v_uid;
  delete from public.phone_otps where user_id = v_uid;
  return null;
end;
$$;

-- Keeps admins.email in step with the login's email once a change is
-- confirmed (the login is shared with the farmer app).
create or replace function public.sync_admin_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.admins set email = new.email where user_id = new.id;
  return new;
end;
$$;

drop trigger if exists on_auth_email_change_sync_admin on auth.users;
create trigger on_auth_email_change_sync_admin
  after update of email on auth.users
  for each row
  when (old.email is distinct from new.email and new.email is not null)
  execute function public.sync_admin_email();

revoke all on function public.admin_check_phone_available(text) from public, anon;
revoke all on function public.admin_change_phone(text) from public, anon;
revoke all on function public.sync_admin_email() from public, anon, authenticated;
grant execute on function public.admin_check_phone_available(text) to authenticated;
grant execute on function public.admin_change_phone(text) to authenticated;
