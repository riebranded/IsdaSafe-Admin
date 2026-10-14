-- Admin panel Settings (applied to the shared IsdaSafe Supabase project on
-- 2026-10-13): an admin can rename themselves and give up their own
-- admin access (the panel's "data deletion" option). Leaving only deletes the
-- public.admins row: the auth account is shared with the farmer app, so it
-- may still own ponds and is left alone.

create or replace function public.admin_update_own_name(p_full_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := trim(coalesce(p_full_name, ''));
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if v_name = '' or length(v_name) > 100 then
    raise exception 'Enter a name of 1 to 100 characters';
  end if;
  update public.admins set full_name = v_name where user_id = auth.uid();
end;
$$;

-- Removes the caller's admin row. The last approved admin can't leave, so
-- the panel always has someone who can approve new requests.
create or replace function public.admin_leave()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtext('public.admins bootstrap'));
  if public.is_approved_admin() and not exists (
    select 1 from public.admins
     where status = 'approved' and user_id <> auth.uid()
  ) then
    raise exception 'You are the only approved admin. Approve another admin before leaving.'
      using errcode = 'P0001';
  end if;
  -- A declined request stays on record, so it can't be cleared and refiled
  -- through request_admin_access.
  delete from public.admins
   where user_id = auth.uid() and status <> 'rejected';
end;
$$;

revoke all on function public.admin_update_own_name(text) from public, anon;
revoke all on function public.admin_leave() from public, anon;
grant execute on function public.admin_update_own_name(text) to authenticated;
grant execute on function public.admin_leave() to authenticated;
