-- Devices tab: a visit's complete readings can be limited to a timeframe
-- (applied to the shared IsdaSafe Supabase project on 2026-10-15).
-- p_from / p_to narrow the visit's readings; null keeps that end of the
-- visit open, so (null, null) is the whole visit as before.

drop function if exists public.admin_device_stay_readings(bigint, integer, integer);

create or replace function public.admin_device_stay_readings(
  p_stay_id bigint,
  p_offset integer default 0,
  p_limit integer default 20,
  p_from timestamptz default null,
  p_to timestamptz default null
) returns table (
  created_at        timestamptz,
  dissolved_oxygen  real,
  ph                real,
  ammonia           real,
  free_ammonia      real,
  water_temperature real,
  air_temperature   real,
  humidity          real
)
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
  select r.created_at, r.dissolved_oxygen, r.ph, r.ammonia,
         coalesce(r.free_ammonia,
                  public.free_ammonia(r.ammonia, r.ph, r.water_temperature)),
         r.water_temperature, r.air_temperature, r.humidity
    from public.device_locations s
    join public.ponds p on p.id = s.pond_id
    join public.sensor_readings r
      on r.device_id = s.device_id
     and r.user_id = s.user_id
     and r.created_at >= s.started_at
     and (s.ended_at is null or r.created_at < s.ended_at)
   where s.id = p_stay_id
     and public.sensor_reading_is_complete(r)
     and (p_from is null or r.created_at >= p_from)
     and (p_to is null or r.created_at <= p_to)
   order by r.created_at desc
   offset greatest(p_offset, 0)
   limit least(greatest(p_limit, 1), 200);
end;
$$;

revoke all on function public.admin_device_stay_readings(bigint, integer, integer, timestamptz, timestamptz) from public, anon;
grant execute on function public.admin_device_stay_readings(bigint, integer, integer, timestamptz, timestamptz) to authenticated;
