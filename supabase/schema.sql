-- MediFind LK v0.1: safe pilot schema for a NEW Supabase project.
-- Review before use with real patient data. This prototype does not store prescriptions.
-- Run in Supabase SQL Editor as an administrator; do not put service_role keys in the browser.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  role text not null default 'patient' check (role in ('patient','admin')),
  created_at timestamptz not null default now()
);

create or replace function public.is_medifind_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin');
$$;

create or replace function public.new_medifind_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id,display_name,role)
  values(new.id,left(coalesce(new.raw_user_meta_data->>'display_name',''),80),'patient')
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created_medifind on auth.users;
create trigger on_auth_user_created_medifind after insert on auth.users
for each row execute function public.new_medifind_profile();

create table if not exists public.pharmacies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 100),
  city text not null,
  address text not null,
  phone text not null default '',
  license text not null,
  lat double precision,
  lng double precision,
  is_verified boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint pharmacies_lat_check check (lat is null or lat between -90 and 90),
  constraint pharmacies_lng_check check (lng is null or lng between -180 and 180)
);

create table if not exists public.pharmacy_staff (
  pharmacy_id uuid not null references public.pharmacies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(pharmacy_id,user_id)
);

create table if not exists public.medicine_requests (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references auth.users(id) on delete cascade,
  medicine_name text not null check (char_length(trim(medicine_name)) between 2 and 120),
  strength text not null check (char_length(trim(strength)) between 1 and 50),
  dosage_form text not null check (char_length(trim(dosage_form)) between 1 and 40),
  quantity integer not null check (quantity between 1 and 999),
  city text not null,
  latitude double precision,
  longitude double precision,
  radius_km integer not null default 10 check(radius_km in (5,10,20,25)),
  urgency text not null default 'today' check(urgency in ('today','soon')),
  status text not null default 'open' check(status in ('open','fulfilled','cancelled','expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now()+interval '12 hours'),
  constraint req_lat_check check(latitude is null or latitude between -90 and 90),
  constraint req_lng_check check(longitude is null or longitude between -180 and 180)
);

create table if not exists public.request_targets (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.medicine_requests(id) on delete cascade,
  pharmacy_id uuid not null references public.pharmacies(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(request_id,pharmacy_id)
);

create table if not exists public.pharmacy_responses (
  id uuid primary key default gen_random_uuid(),
  target_id uuid not null unique references public.request_targets(id) on delete cascade,
  request_id uuid not null references public.medicine_requests(id) on delete cascade,
  pharmacy_id uuid not null references public.pharmacies(id) on delete cascade,
  status text not null check(status in ('available','limited','unavailable')),
  note text not null default '' check(char_length(note)<=240),
  confirmed_at timestamptz not null default now(),
  expires_at timestamptz not null default (now()+interval '30 minutes')
);

create index if not exists idx_request_patient_time on public.medicine_requests(patient_id,created_at desc);
create index if not exists idx_req_targets_pharmacy on public.request_targets(pharmacy_id);
create index if not exists idx_response_req on public.pharmacy_responses(request_id);
create index if not exists idx_pharmacies_city on public.pharmacies(city);
create index if not exists idx_pharmacy_staff_user on public.pharmacy_staff(user_id);

-- Always assign server timestamps/status. The client cannot mark a request fulfilled.
create or replace function public.medifind_request_defaults()
returns trigger language plpgsql set search_path='' as $$
begin
  new.created_at=now();
  new.expires_at=now()+interval '12 hours';
  new.status='open';
  return new;
end $$;
drop trigger if exists medifind_set_request_defaults on public.medicine_requests;
create trigger medifind_set_request_defaults before insert on public.medicine_requests
for each row execute function public.medifind_request_defaults();

-- Approximate great-circle distance in kilometres.
create or replace function public.medifind_distance_km(a_lat double precision,a_lng double precision,b_lat double precision,b_lng double precision)
returns double precision language sql immutable set search_path='' as $$
  select case when a_lat is null or a_lng is null or b_lat is null or b_lng is null then null
  else 6371 * acos(least(1.0,greatest(-1.0,
    sin(radians(a_lat))*sin(radians(b_lat)) + cos(radians(a_lat))*cos(radians(b_lat))*cos(radians(b_lng-a_lng))
  ))) end;
$$;

-- Match verified pharmacies on request creation. City fallback only if coordinates are missing.
create or replace function public.medifind_match_pharmacies()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.request_targets(request_id,pharmacy_id)
  select new.id,p.id from public.pharmacies p
  where p.is_verified=true and p.is_active=true and (
    (new.latitude is not null and new.longitude is not null and p.lat is not null and p.lng is not null
       and public.medifind_distance_km(new.latitude,new.longitude,p.lat,p.lng) <= new.radius_km)
    or ((new.latitude is null or new.longitude is null or p.lat is null or p.lng is null)
       and lower(trim(p.city))=lower(trim(new.city)))
  );
  return new;
end $$;
drop trigger if exists medifind_request_match on public.medicine_requests;
create trigger medifind_request_match after insert on public.medicine_requests
for each row execute function public.medifind_match_pharmacies();

-- Row-level security: patients see their own requests; staff use an explicit limited RPC.
alter table public.profiles enable row level security;
alter table public.pharmacies enable row level security;
alter table public.pharmacy_staff enable row level security;
alter table public.medicine_requests enable row level security;
alter table public.request_targets enable row level security;
alter table public.pharmacy_responses enable row level security;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
using (id=auth.uid() or public.is_medifind_admin());
drop policy if exists profiles_edit_name on public.profiles;
create policy profiles_edit_name on public.profiles for update to authenticated
using (id=auth.uid()) with check (id=auth.uid());

drop policy if exists pharmacies_read on public.pharmacies;
create policy pharmacies_read on public.pharmacies for select to anon,authenticated
using (is_verified=true and is_active=true or public.is_medifind_admin() or exists(
  select 1 from public.pharmacy_staff st where st.pharmacy_id=public.pharmacies.id and st.user_id=auth.uid() and st.is_active=true
));
drop policy if exists pharmacies_admin_insert on public.pharmacies;
create policy pharmacies_admin_insert on public.pharmacies for insert to authenticated
with check(public.is_medifind_admin());
drop policy if exists pharmacies_admin_update on public.pharmacies;
create policy pharmacies_admin_update on public.pharmacies for update to authenticated
using(public.is_medifind_admin()) with check(public.is_medifind_admin());

drop policy if exists pharmacy_staff_read on public.pharmacy_staff;
create policy pharmacy_staff_read on public.pharmacy_staff for select to authenticated
using(user_id=auth.uid() or public.is_medifind_admin());
drop policy if exists pharmacy_staff_admin_insert on public.pharmacy_staff;
create policy pharmacy_staff_admin_insert on public.pharmacy_staff for insert to authenticated
with check(public.is_medifind_admin());
drop policy if exists pharmacy_staff_admin_update on public.pharmacy_staff;
create policy pharmacy_staff_admin_update on public.pharmacy_staff for update to authenticated
using(public.is_medifind_admin()) with check(public.is_medifind_admin());

drop policy if exists patient_request_read on public.medicine_requests;
create policy patient_request_read on public.medicine_requests for select to authenticated
using(patient_id=auth.uid() or public.is_medifind_admin());
drop policy if exists patient_request_insert on public.medicine_requests;
create policy patient_request_insert on public.medicine_requests for insert to authenticated
with check(patient_id=auth.uid() and status='open');

drop policy if exists request_targets_select on public.request_targets;
create policy request_targets_select on public.request_targets for select to authenticated
using(public.is_medifind_admin() or exists(select 1 from public.medicine_requests r where r.id=public.request_targets.request_id and r.patient_id=auth.uid())
  or exists(select 1 from public.pharmacy_staff st where st.pharmacy_id=public.request_targets.pharmacy_id and st.user_id=auth.uid() and st.is_active=true));

drop policy if exists responses_read on public.pharmacy_responses;
create policy responses_read on public.pharmacy_responses for select to authenticated
using(public.is_medifind_admin() or exists(select 1 from public.medicine_requests r where r.id=public.pharmacy_responses.request_id and r.patient_id=auth.uid())
 or exists(select 1 from public.pharmacy_staff st where st.pharmacy_id=public.pharmacy_responses.pharmacy_id and st.user_id=auth.uid() and st.is_active=true));

-- Only staff of verified pharmacies can see anonymised request details via RPC.
create or replace function public.get_incoming_requests()
returns table(target_id uuid,request_id uuid,pharmacy_id uuid,medicine_name text,strength text,dosage_form text,quantity integer,city text,urgency text,status text,created_at timestamptz,expires_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select t.id,t.request_id,t.pharmacy_id,r.medicine_name,r.strength,r.dosage_form,r.quantity,r.city,r.urgency,r.status,r.created_at,r.expires_at
  from public.request_targets t
  join public.medicine_requests r on r.id=t.request_id
  join public.pharmacies p on p.id=t.pharmacy_id
  join public.pharmacy_staff s on s.pharmacy_id=t.pharmacy_id
  where s.user_id=auth.uid() and s.is_active=true and p.is_verified=true and p.is_active=true
    and r.status='open' and r.expires_at>now()
  order by r.created_at desc;
$$;

-- Server-controlled responses cannot forge a pharmacy or request association.
create or replace function public.respond_to_request(p_target_id uuid,p_status text,p_note text default '')
returns public.pharmacy_responses language plpgsql security definer set search_path = '' as $$
declare v_target record; v_reply public.pharmacy_responses;
begin
  if p_status not in ('available','limited','unavailable') then raise exception 'Invalid availability status'; end if;
  if char_length(coalesce(p_note,''))>240 then raise exception 'Response note is too long'; end if;
  select t.request_id,t.pharmacy_id into v_target
  from public.request_targets t
  join public.medicine_requests r on r.id=t.request_id
  join public.pharmacies p on p.id=t.pharmacy_id
  join public.pharmacy_staff s on s.pharmacy_id=t.pharmacy_id
  where t.id=p_target_id and s.user_id=auth.uid() and s.is_active=true
    and p.is_verified=true and p.is_active=true and r.status='open' and r.expires_at>now();
  if not found then raise exception 'No authorised active pharmacy request found'; end if;
  insert into public.pharmacy_responses (target_id,request_id,pharmacy_id,status,note,confirmed_at,expires_at)
  values(p_target_id,v_target.request_id,v_target.pharmacy_id,p_status,coalesce(p_note,''),now(),now()+interval '30 minutes')
  on conflict (target_id) do update set status=excluded.status,note=excluded.note,
    confirmed_at=now(),expires_at=now()+interval '30 minutes'
  returning * into v_reply;
  return v_reply;
end $$;

-- Patients can cancel only their own open request, not rewrite medicine details.
create or replace function public.cancel_medicine_request(p_request_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_count integer;
begin
  update public.medicine_requests set status='cancelled'
    where id=p_request_id and patient_id=auth.uid() and status='open' and expires_at>now();
  get diagnostics v_count = row_count;
  return v_count>0;
end $$;

-- Explicit grants. Direct response writes and staff data modifications are disallowed.
revoke all on public.profiles from anon,authenticated;
revoke all on public.pharmacies from anon,authenticated;
revoke all on public.pharmacy_staff from anon,authenticated;
revoke all on public.medicine_requests from anon,authenticated;
revoke all on public.request_targets from anon,authenticated;
revoke all on public.pharmacy_responses from anon,authenticated;
grant select on public.profiles to authenticated;
grant update(display_name) on public.profiles to authenticated;
grant select on public.pharmacies to anon,authenticated;
grant insert,update on public.pharmacies to authenticated;
grant select,insert,update on public.pharmacy_staff to authenticated;
grant select,insert on public.medicine_requests to authenticated;
grant select on public.request_targets to authenticated;
grant select on public.pharmacy_responses to authenticated;
revoke all on function public.get_incoming_requests() from public;
revoke all on function public.respond_to_request(uuid,text,text) from public;
revoke all on function public.cancel_medicine_request(uuid) from public;
grant execute on function public.get_incoming_requests() to authenticated;
grant execute on function public.respond_to_request(uuid,text,text) to authenticated;
grant execute on function public.cancel_medicine_request(uuid) to authenticated;

-- Create an admin AFTER that user signs up. Run this manually in SQL Editor:
-- update public.profiles set role='admin' where id=(select id from auth.users where email='admin@example.com');
-- Add staff AFTER pharmacy licence verification and a staff member registers:
-- insert into public.pharmacy_staff(pharmacy_id,user_id) values('VERIFIED-PHARMACY-UUID','STAFF-USER-UUID');
