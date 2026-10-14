-- Admin Register with an existing IsdaSafe email (applied to the shared
-- IsdaSafe Supabase project on 2026-10-14).
--
-- Admins and farmers share auth.users, so signing up with an email that
-- already has an account (e.g. from the farmer app) fails with "User
-- already registered". The Register screen asks this first and, when the
-- email has an account, signs in to it instead and files an admin request.
--
-- It only says whether a login exists for the email, which Supabase's own
-- sign-up error (and the farmer app's is_email_taken) already reveal.
create or replace function public.email_has_account(p_email text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from auth.users
     where lower(email) = lower(trim(p_email))
  );
$$;

revoke all on function public.email_has_account(text) from public;
grant execute on function public.email_has_account(text) to anon, authenticated;
