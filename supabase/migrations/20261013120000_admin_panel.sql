-- Admin panel accounts and monitoring access (applied to the shared IsdaSafe
-- Supabase project on 2026-10-13).
--
-- Admins live in auth.users like farmers, but are only admins once they have
-- an approved row in public.admins. Nothing here widens the farmer tables'
-- RLS: the panel reads through security-definer functions that check
-- is_approved_admin() first.

create table if not exists public.admins (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null,
  email       text not null,
  status      text not null default 'pending'
              check (status in ('pending', 'approved', 'rejected')),
  created_at  timestamptz not null default now(),
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz
);

alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;
grant select on public.admins to authenticated;

create policy "admins: read own row"
  on public.admins for select to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.is_approved_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admins
    where user_id = auth.uid() and status = 'approved'
  );
$$;

-- A sign-up from the admin panel (user_metadata.admin_signup = true) becomes
-- a pending admin request. The very first admin is approved outright so the
-- panel can be bootstrapped; every later one needs an approved admin.
create or replace function public.handle_admin_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(new.raw_user_meta_data ->> 'admin_signup', '') <> 'true' then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtext('public.admins bootstrap'));
  insert into public.admins (user_id, full_name, email, status)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), new.email),
    new.email,
    case when exists (select 1 from public.admins where status = 'approved')
         then 'pending' else 'approved' end
  );
  return new;
end;
$$;

drop trigger if exists on_admin_signup on auth.users;
create trigger on_admin_signup
  after insert on auth.users
  for each row execute function public.handle_admin_signup();

-- Admin requests, newest first (approved admins only).
create or replace function public.admin_list_admins()
returns setof public.admins
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_approved_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  return query select * from public.admins order by created_at desc;
end;
$$;

create or replace function public.admin_set_status(p_user_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_approved_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  if p_status not in ('approved', 'rejected') then
    raise exception 'Invalid status';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'You cannot change your own access';
  end if;
  update public.admins
     set status = p_status, reviewed_by = auth.uid(), reviewed_at = now()
   where user_id = p_user_id;
end;
$$;

-- Every pond with a paired device, its owner, the device's last upload and
-- the latest reading (approved admins only).
create or replace function public.admin_monitored_ponds()
returns table (
  pond_id           uuid,
  pond_name         text,
  latitude          double precision,
  longitude         double precision,
  species_names     text[],
  verification_status text,
  owner_id          uuid,
  owner_name        text,
  owner_email       text,
  owner_phone       text,
  device_id         text,
  paired_at         timestamptz,
  last_seen_at      timestamptz,
  reading_at        timestamptz,
  water_temperature real,
  air_temperature   real,
  humidity          real,
  dissolved_oxygen  real,
  ph                real,
  ammonia           real,
  free_ammonia      real
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
  select p.id, p.name, p.latitude, p.longitude, p.species_names,
         p.verification_status,
         p.user_id, pr.full_name, pr.email, pr.phone,
         d.id, d.paired_at, d.last_seen_at,
         r.created_at, r.water_temperature, r.air_temperature, r.humidity,
         r.dissolved_oxygen, r.ph, r.ammonia, r.free_ammonia
    from public.devices d
    join public.ponds p on p.id = d.pond_id
    left join public.profiles pr on pr.id = p.user_id
    left join lateral (
      select * from public.sensor_readings s
       where s.pond_id = p.id
       order by s.created_at desc
       limit 1
    ) r on true
   order by p.name;
end;
$$;

revoke all on function public.is_approved_admin() from public, anon;
revoke all on function public.handle_admin_signup() from public, anon, authenticated;
revoke all on function public.admin_list_admins() from public, anon;
revoke all on function public.admin_set_status(uuid, text) from public, anon;
revoke all on function public.admin_monitored_ponds() from public, anon;
grant execute on function public.is_approved_admin() to authenticated;
grant execute on function public.admin_list_admins() to authenticated;
grant execute on function public.admin_set_status(uuid, text) to authenticated;
grant execute on function public.admin_monitored_ponds() to authenticated;
