-- Admin map: a monitored pond's trend for the pond panel's charts (applied to
-- the shared IsdaSafe Supabase project on 2026-10-13).
--
-- Same grouping as the farmer app's pond_reading_trend (IsdaSafeV2
-- supabase/migrations/20261012120000_pond_reading_trend.sql), but that one
-- runs as the caller under the owner-only RLS on sensor_readings. This one
-- is security definer, approved admins only, and only for ponds with a
-- paired device — the same ponds admin_monitored_ponds shows.
create or replace function public.admin_pond_reading_trend(
  p_pond_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_step text
)
returns table (
  bucket timestamptz,
  metric text,
  readings bigint,
  avg_value real,
  min_value real,
  max_value real
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
  if not exists (select 1 from public.devices d where d.pond_id = p_pond_id) then
    raise exception 'Pond has no paired device' using errcode = '42501';
  end if;
  if p_step not in ('15min', 'hour', 'day', 'week', 'month', 'year') then
    raise exception 'unknown step %', p_step using errcode = '22023';
  end if;

  return query
  with src as (
    select
      case p_step
        when '15min' then date_bin(
          interval '15 minutes', r.created_at, timestamptz '2000-01-01 00:00+08')
        else date_trunc(p_step, r.created_at, 'Asia/Manila')
      end as step_start,
      r.dissolved_oxygen, r.ph, r.ammonia, r.water_temperature,
      r.air_temperature, r.humidity,
      public.free_ammonia(r.ammonia, r.ph, r.water_temperature) as free_nh3
    from public.sensor_readings r
    where r.pond_id = p_pond_id
      and r.created_at >= p_start
      and r.created_at <= p_end
  )
  select
    src.step_start,
    m.metric,
    count(m.v),
    avg(m.v)::real,
    min(m.v)::real,
    max(m.v)::real
  from src
  cross join lateral (values
    ('dissolved_oxygen', src.dissolved_oxygen),
    ('ph', src.ph),
    ('ammonia', src.ammonia),
    ('water_temperature', src.water_temperature),
    ('air_temperature', src.air_temperature),
    ('humidity', src.humidity),
    ('free_ammonia', src.free_nh3)
  ) as m(metric, v)
  where m.v is not null
  group by src.step_start, m.metric
  order by src.step_start;
end;
$$;

revoke all on function public.admin_pond_reading_trend(uuid, timestamptz, timestamptz, text)
  from public, anon;
grant execute on function public.admin_pond_reading_trend(uuid, timestamptz, timestamptz, text)
  to authenticated;
