-- Devices tab: a visit's readings can be averaged per day, week, month or
-- year (applied to the shared IsdaSafe Supabase project on 2026-10-15).
-- p_step is null for single readings, else 'day' | 'week' | 'month' | 'year':
-- one row per period (created_at is the period's start, in the caller's time
-- zone, given as its UTC offset in p_utc_offset_minutes; weeks start Monday)
-- with each metric averaged over the period's complete readings.

drop function if exists public.admin_device_stay_readings(bigint, integer, integer, timestamptz, timestamptz);

create or replace function public.admin_device_stay_readings(
  p_stay_id bigint,
  p_offset integer default 0,
  p_limit integer default 20,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_step text default null,
  p_utc_offset_minutes integer default 0
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
declare
  v_shift interval := make_interval(mins => coalesce(p_utc_offset_minutes, 0));
begin
  if not public.is_approved_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  if p_step is not null and p_step not in ('day', 'week', 'month', 'year') then
    raise exception 'Unknown step %', p_step using errcode = '22023';
  end if;

  if p_step is null then
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
  else
    return query
    select (date_trunc(p_step, r.created_at + v_shift) - v_shift)::timestamptz,
           avg(r.dissolved_oxygen)::real,
           avg(r.ph)::real,
           avg(r.ammonia)::real,
           avg(coalesce(r.free_ammonia,
                        public.free_ammonia(r.ammonia, r.ph, r.water_temperature)))::real,
           avg(r.water_temperature)::real,
           avg(r.air_temperature)::real,
           avg(r.humidity)::real
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
     group by 1
     order by 1 desc
     offset greatest(p_offset, 0)
     limit least(greatest(p_limit, 1), 200);
  end if;
end;
$$;

revoke all on function public.admin_device_stay_readings(bigint, integer, integer, timestamptz, timestamptz, text, integer) from public, anon;
grant execute on function public.admin_device_stay_readings(bigint, integer, integer, timestamptz, timestamptz, text, integer) to authenticated;
