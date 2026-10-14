-- Admin phone numbers for OTP (applied to the shared IsdaSafe Supabase
-- project on 2026-10-14).
--
-- The number lives on public.admins, not auth.users.phone: auth.users.phone
-- is unique across every account, and an admin may use the same number as a
-- farmer account in the IsdaSafe app. It only has to be unique among
-- verified admins.
--
-- Codes are sent by the farmer app's `send-semaphore-otp` Edge Function
-- (which only stores a hashed code in public.phone_otps for the caller) and
-- checked here by admin_verify_phone_otp, which — unlike the farmer app's
-- `verify-semaphore-otp` — never writes auth.users.phone.

alter table public.admins
  add column if not exists phone text
    check (phone is null or phone ~ '^\+639\d{9}$'),
  add column if not exists phone_verified boolean not null default false;

create unique index if not exists admins_verified_phone_key
  on public.admins (phone) where phone_verified;

-- Same as before, plus the phone typed on the Register form (admin_phone).
create or replace function public.handle_admin_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := new.raw_user_meta_data ->> 'admin_phone';
begin
  if coalesce(new.raw_user_meta_data ->> 'admin_signup', '') <> 'true' then
    return new;
  end if;
  if v_phone !~ '^\+639\d{9}$' then
    v_phone := null;
  end if;
  perform pg_advisory_xact_lock(hashtext('public.admins bootstrap'));
  insert into public.admins (user_id, full_name, email, phone, status)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), new.email),
    new.email,
    v_phone,
    case when exists (select 1 from public.admins where status = 'approved')
         then 'pending' else 'approved' end
  );
  return new;
end;
$$;

drop function if exists public.request_admin_access(text);

create or replace function public.request_admin_access(
  p_full_name text,
  p_phone text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_email  text;
  v_status text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = '42501';
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
  insert into public.admins (user_id, full_name, email, phone, status)
  values (
    v_uid,
    coalesce(nullif(trim(p_full_name), ''), v_email),
    v_email,
    p_phone,
    v_status
  );
  return v_status;
end;
$$;

-- Sets (or changes) the caller's number, unverified, before a code is sent.
-- Refused when another verified admin already has it; a farmer account
-- with the same number doesn't matter.
create or replace function public.admin_set_own_phone(p_phone text)
returns void
language plpgsql
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
  update public.admins
     set phone = p_phone, phone_verified = false
   where user_id = auth.uid()
     and phone is distinct from p_phone;
end;
$$;

-- Checks a code sent by send-semaphore-otp for the caller's number. Returns
-- null on success, otherwise the message to show: a wrong guess has to be
-- recorded (5 locks the code), so it can't be raised and rolled back.
create or replace function public.admin_verify_phone_otp(p_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_phone text;
  v_otp   public.phone_otps%rowtype;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if p_code is null or p_code !~ '^\d{4,8}$' then
    return 'Enter the verification code.';
  end if;
  select phone into v_phone from public.admins where user_id = v_uid;
  select * into v_otp from public.phone_otps where user_id = v_uid for update;
  if not found or v_phone is null or v_otp.phone <> v_phone then
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
     where phone = v_phone and phone_verified and user_id <> v_uid
  ) then
    return 'Another admin already uses this number.';
  end if;
  update public.admins set phone_verified = true where user_id = v_uid;
  delete from public.phone_otps where user_id = v_uid;
  return null;
end;
$$;

revoke all on function public.request_admin_access(text, text) from public, anon;
revoke all on function public.admin_set_own_phone(text) from public, anon;
revoke all on function public.admin_verify_phone_otp(text) from public, anon;
grant execute on function public.request_admin_access(text, text) to authenticated;
grant execute on function public.admin_set_own_phone(text) to authenticated;
grant execute on function public.admin_verify_phone_otp(text) to authenticated;
