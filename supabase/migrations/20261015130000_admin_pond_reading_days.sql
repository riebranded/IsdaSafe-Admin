-- Custom timeframes only allow days a pond has readings: the days (in the
-- caller's time zone, given as its UTC offset) with at least one reading in
-- the last two years, newest first. p_device_id limits it to one device's
-- readings and p_complete_only to complete ones (the Devices tab).
-- (applied to the shared IsdaSafe Supabase project on 2026-10-15)

create or replace function public.admin_pond_reading_days(
  p_pond_id uuid,
  p_device_id text default null,
  p_complete_only boolean default false,
  p_utc_offset_minutes integer default 0
) returns table (day date)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_approved_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  return query
  select distinct (r.created_at + make_interval(mins => coalesce(p_utc_offset_minutes, 0)))::date as d
    from public.sensor_readings r
   where r.pond_id = p_pond_id
     and r.created_at >= now() - interval '2 years 2 days'
     and (p_device_id is null or r.device_id = p_device_id)
     and (not p_complete_only or public.sensor_reading_is_complete(r))
   order by d desc;
end;
$$;

revoke all on function public.admin_pond_reading_days(uuid, text, boolean, integer) from public, anon;
grant execute on function public.admin_pond_reading_days(uuid, text, boolean, integer) to authenticated;
