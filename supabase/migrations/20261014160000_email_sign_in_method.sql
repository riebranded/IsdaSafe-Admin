-- Admin Register: tell an existing password login apart from a Google-only
-- one (applied to the shared IsdaSafe Supabase project on 2026-10-14).
--
-- A Google-only account has no password, so signing in to it with a
-- password always fails; Register uses this to point to "Continue with
-- Google" straight away instead of a "wrong password" message.
--
-- Returns null when the email has no login, 'password' when it has a
-- password, and 'oauth' when it only signs in through a provider (Google).
create or replace function public.email_sign_in_method(p_email text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
           when u.encrypted_password is not null and u.encrypted_password <> ''
           then 'password'
           else 'oauth'
         end
    from auth.users u
   where lower(u.email) = lower(trim(p_email))
   limit 1;
$$;

revoke all on function public.email_sign_in_method(text) from public;
grant execute on function public.email_sign_in_method(text) to anon, authenticated;
