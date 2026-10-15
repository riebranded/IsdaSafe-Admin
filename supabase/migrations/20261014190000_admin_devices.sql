-- Admin Devices tab (applied to the shared IsdaSafe Supabase project on
-- 2026-10-14). The admin take on the farmer app's Devices tab
-- (IsdaSafeV2 supabase/migrations/20261014120000_device_location_history.sql
-- and its follow-ups): the same device_locations stays and the same rules
-- for what a stay shows (a pond that still exists, at least one complete
-- reading there), but across every device and account. The farmer functions
-- only show devices the signed-in account itself paired; these are for
-- approved admins only and show them all.

-- Every device IsdaSafe knows about: manufactured (device_credentials),
-- paired now (devices) or with a location history (device_locations), with
-- its current owner and pond and how much it has measured. Most recently
-- active first.
create or replace function public.admin_device_list()
returns table (
  device_id       text,
  manufactured_at timestamptz,
  owner_id        uuid,
  owner_name      text,
  owner_email     text,
  pond_id         uuid,
  pond_name       text,
  paired_at       timestamptz,
  last_seen_at    timestamptz,
  place_count     bigint,
  reading_count   bigint,
  last_placed_at  timestamptz
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
  with ids as (
    select c.id as device_id from public.device_credentials c
    union
    select d.id from public.devices d
    union
    select s.device_id from public.device_locations s
  ),
  stays as (
    select s.device_id, s.pond_id, s.started_at,
           public.device_stay_complete_count(s) as readings
      from public.device_locations s
      join public.ponds p on p.id = s.pond_id
  )
  select i.device_id,
         c.created_at,
         d.user_id,
         pr.full_name,
         pr.email,
         d.pond_id,
         p.name,
         d.paired_at,
         d.last_seen_at,
         (select count(distinct st.pond_id) from stays st
           where st.device_id = i.device_id and st.readings > 0),
         (select coalesce(sum(st.readings), 0)::bigint from stays st
           where st.device_id = i.device_id),
         (select max(st.started_at) from stays st
           where st.device_id = i.device_id and st.readings > 0)
    from ids i
    left join public.device_credentials c on c.id = i.device_id
    left join public.devices d on d.id = i.device_id
    left join public.profiles pr on pr.id = d.user_id
    left join public.ponds p on p.id = d.pond_id
   order by greatest(d.last_seen_at, d.paired_at, c.created_at) desc nulls last,
            i.device_id;
end;
$$;

-- Every stay of one device at a pond that still exists, with complete
-- readings, under any account, newest first, with the account that had it.
create or replace function public.admin_device_location_history(p_device_id text)
returns table (
  id            bigint,
  pond_id       uuid,
  pond_name     text,
  owner_id      uuid,
  owner_name    text,
  owner_email   text,
  latitude      double precision,
  longitude     double precision,
  started_at    timestamptz,
  ended_at      timestamptz,
  reading_count bigint
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
  select stays.*
    from (
      select s.id, s.pond_id, p.name, s.user_id, pr.full_name, pr.email,
             s.latitude, s.longitude, s.started_at, s.ended_at,
             public.device_stay_complete_count(s) as reading_count
        from public.device_locations s
        join public.ponds p on p.id = s.pond_id
        left join public.profiles pr on pr.id = s.user_id
       where s.device_id = upper(p_device_id)
    ) stays
   where stays.reading_count > 0
   order by stays.started_at desc;
end;
$$;

-- One page of a stay's complete readings, newest first.
create or replace function public.admin_device_stay_readings(
  p_stay_id bigint,
  p_offset integer default 0,
  p_limit integer default 20
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
   order by r.created_at desc
   offset greatest(p_offset, 0)
   limit least(greatest(p_limit, 1), 200);
end;
$$;

revoke all on function public.admin_device_list() from public, anon;
revoke all on function public.admin_device_location_history(text) from public, anon;
revoke all on function public.admin_device_stay_readings(bigint, integer, integer) from public, anon;
grant execute on function public.admin_device_list() to authenticated;
grant execute on function public.admin_device_location_history(text) to authenticated;
grant execute on function public.admin_device_stay_readings(bigint, integer, integer) to authenticated;
