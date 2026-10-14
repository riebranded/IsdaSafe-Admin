-- Lets a signed-in account with no admin row (e.g. a first-time Google
-- sign-in on the admin panel, which never carries admin_signup metadata)
-- file an admin request. Same bootstrap rule as handle_admin_signup: the
-- very first admin is approved outright, everyone after waits for approval.
create or replace function public.request_admin_access(p_full_name text)
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
  select status into v_status from public.admins where user_id = v_uid;
  if found then
    return v_status;
  end if;
  select email into v_email from auth.users where id = v_uid;
  perform pg_advisory_xact_lock(hashtext('public.admins bootstrap'));
  v_status := case
    when exists (select 1 from public.admins where status = 'approved')
    then 'pending' else 'approved' end;
  insert into public.admins (user_id, full_name, email, status)
  values (
    v_uid,
    coalesce(nullif(trim(p_full_name), ''), v_email),
    v_email,
    v_status
  );
  return v_status;
end;
$$;

revoke all on function public.request_admin_access(text) from public, anon;
grant execute on function public.request_admin_access(text) to authenticated;
