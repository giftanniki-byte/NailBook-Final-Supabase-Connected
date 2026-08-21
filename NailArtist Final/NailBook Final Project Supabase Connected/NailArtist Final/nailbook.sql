-- ============================================================
-- NAILBOOK - ONE COPY/PASTE SUPABASE DATABASE SCRIPT
-- ============================================================
-- Run this entire file once in a dedicated NailBook Supabase project.
--
-- IMPORTANT:
-- * This resets NailBook PUBLIC tables, but DOES NOT delete auth.users.
-- * It removes all custom (non-internal) triggers from auth.users so an
--   old NailBook trigger cannot cause "Database error saving new user".
-- * Passwords are handled only by Supabase Auth.
-- * Google sign-in is not included.
-- * Location is TEXT only. No latitude/longitude columns.
--
-- After this script, the frontend uses Supabase Auth first and creates
-- NailBook profile records only after a user has authenticated.
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 0. REMOVE OLD NAILBOOK AUTH TRIGGERS
-- ------------------------------------------------------------
-- A previous version of the project created an auth.users trigger.
-- Any failing custom trigger can make Supabase Auth return the generic
-- "Database error saving new user" message. This removes custom triggers
-- from auth.users in this dedicated NailBook project.
-- ------------------------------------------------------------
do $$
declare
    r record;
begin
    for r in
        select tgname
        from pg_trigger
        where tgrelid = 'auth.users'::regclass
          and not tgisinternal
    loop
        execute format('drop trigger if exists %I on auth.users', r.tgname);
    end loop;
end $$;

-- Remove old NailBook trigger function if it exists.
drop function if exists public.handle_new_nailbook_user() cascade;

-- ------------------------------------------------------------
-- 1. RESET NAILBOOK PUBLIC OBJECTS
-- ------------------------------------------------------------
drop view if exists public.v_artist_directory cascade;
drop table if exists public.reviews cascade;
drop table if exists public.favorites cascade;
drop table if exists public.bookings cascade;
drop table if exists public.artist_services cascade;
drop table if exists public.services cascade;
drop table if exists public.support_messages cascade;
drop table if exists public.artist_profiles cascade;
drop table if exists public.client_profiles cascade;
drop table if exists public.profiles cascade;
drop function if exists public.ensure_nailbook_profile(text,text,text,text,text,text,jsonb) cascade;
drop function if exists public.ensure_nailbook_profile() cascade;
drop function if exists public.set_updated_at() cascade;
drop function if exists public.submit_support_message(text,text,text,text) cascade;

-- ------------------------------------------------------------
-- 2. PROFILES
-- One row per authenticated NailBook user.
-- ------------------------------------------------------------
create table public.profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    role text not null check (role in ('client','artist','admin')),
    full_name text not null default '',
    email text not null default '',
    phone text,
    city text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index profiles_role_idx on public.profiles(role);
create index profiles_city_idx on public.profiles(city);

-- ------------------------------------------------------------
-- 3. ARTIST PROFILES
-- Public artist information shown in Find Artists.
-- Artists can update these fields from their dashboard.
-- `gallery` stores public Supabase Storage URLs for the artist's images.
-- ------------------------------------------------------------
create table public.artist_profiles (
    user_id uuid primary key references public.profiles(user_id) on delete cascade,
    business_name text not null,
    location text not null default '',
    bio text not null default '',
    years_experience integer not null default 0 check (years_experience >= 0),
    average_rating numeric(3,2) not null default 0.00 check (average_rating between 0 and 5),
    review_count integer not null default 0 check (review_count >= 0),
    total_bookings integer not null default 0 check (total_bookings >= 0),
    is_available boolean not null default true,
    gallery jsonb not null default '[]'::jsonb,
    instagram_handle text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index artist_profiles_location_idx on public.artist_profiles(location);
create index artist_profiles_rating_idx on public.artist_profiles(average_rating desc);

-- ------------------------------------------------------------
-- 4. CLIENT PROFILES
-- Client-only information.
-- ------------------------------------------------------------
create table public.client_profiles (
    user_id uuid primary key references public.profiles(user_id) on delete cascade,
    preferences text not null default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 5. SERVICES
-- These are the options shown in All Specialties and artist signup.
-- ------------------------------------------------------------
create table public.services (
    service_id bigint generated by default as identity primary key,
    service_name text not null unique,
    description text not null default '',
    default_duration_minutes integer not null default 60 check (default_duration_minutes > 0),
    created_at timestamptz not null default now()
);

insert into public.services(service_name, description, default_duration_minutes) values
('Manicure','Classic manicure service',45),
('Pedicure','Pedicure service',60),
('Gel Nails','Gel nail application',60),
('Chrome Nails','Chrome nail finish',75),
('French Tips','French tip nail design',60),
('Nail Art','Custom nail art',90),
('Acrylic','Acrylic nail extensions',90),
('Extensions','Nail extensions',120),
('Ombre','Ombre nail design',90),
('Stamping','Nail stamping designs',60)
on conflict(service_name) do update set
    description = excluded.description,
    default_duration_minutes = excluded.default_duration_minutes;

-- ------------------------------------------------------------
-- 6. ARTIST SERVICES
-- Many-to-many relationship: one artist can offer many services.
-- `price` is the price chosen by the individual artist for that service.
-- `duration_minutes` lets the artist choose the appointment duration.
-- The Artist Dashboard updates these values with an upsert.
-- ------------------------------------------------------------
create table public.artist_services (
    artist_id uuid not null references public.artist_profiles(user_id) on delete cascade,
    service_id bigint not null references public.services(service_id) on delete cascade,
    price numeric(10,2) not null default 0 check (price >= 0),
    duration_minutes integer check (duration_minutes is null or duration_minutes > 0),
    is_available boolean not null default true,
    created_at timestamptz not null default now(),
    primary key (artist_id, service_id)
);

create index artist_services_service_idx on public.artist_services(service_id);
create index artist_services_artist_idx on public.artist_services(artist_id);

-- ------------------------------------------------------------
-- 7. BOOKINGS
-- Client + artist + service + appointment.
-- ------------------------------------------------------------
create table public.bookings (
    booking_id uuid primary key default gen_random_uuid(),
    client_id uuid not null references public.profiles(user_id) on delete cascade,
    artist_id uuid not null references public.artist_profiles(user_id) on delete cascade,
    service_id bigint not null references public.services(service_id) on delete restrict,
    booking_date date not null,
    start_time time not null,
    end_time time,
    status text not null default 'pending'
        check (status in ('pending','confirmed','completed','cancelled','declined','no_show')),
    price numeric(10,2) not null default 0 check (price >= 0),
    client_notes text not null default '',
    artist_notes text not null default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index bookings_client_date_idx on public.bookings(client_id, booking_date desc);
create index bookings_artist_date_idx on public.bookings(artist_id, booking_date desc);
create index bookings_artist_status_idx on public.bookings(artist_id, status);

-- ------------------------------------------------------------
-- 8. FAVORITES
-- Clients can save artists.
-- ------------------------------------------------------------
create table public.favorites (
    client_id uuid not null references public.profiles(user_id) on delete cascade,
    artist_id uuid not null references public.artist_profiles(user_id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key(client_id, artist_id)
);

-- ------------------------------------------------------------
-- 9. REVIEWS
-- One review per booking.
-- ------------------------------------------------------------
create table public.reviews (
    review_id uuid primary key default gen_random_uuid(),
    booking_id uuid not null unique references public.bookings(booking_id) on delete cascade,
    client_id uuid not null references public.profiles(user_id) on delete cascade,
    artist_id uuid not null references public.artist_profiles(user_id) on delete cascade,
    rating integer not null check (rating between 1 and 5),
    review_text text not null default '',
    is_visible boolean not null default true,
    created_at timestamptz not null default now()
);

create index reviews_artist_idx on public.reviews(artist_id);

-- ------------------------------------------------------------
-- 10. SUPPORT MESSAGES
-- Contact Us / Help & Support submissions.
-- ------------------------------------------------------------
create table public.support_messages (
    message_id uuid primary key default gen_random_uuid(),
    user_id uuid references public.profiles(user_id) on delete set null,
    name text not null,
    email text not null,
    subject text not null,
    message text not null,
    status text not null default 'new'
        check (status in ('new','in_progress','resolved','closed')),
    created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 11. UPDATED_AT HELPER
-- Keeps updated_at current when rows are edited.
-- ------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger artist_profiles_updated_at
before update on public.artist_profiles
for each row execute function public.set_updated_at();

create trigger client_profiles_updated_at
before update on public.client_profiles
for each row execute function public.set_updated_at();

create trigger bookings_updated_at
before update on public.bookings
for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 12. SECURE PROFILE PROVISIONING
-- IMPORTANT: this is NOT an auth.users trigger.
-- It runs only after a user has authenticated.
-- ------------------------------------------------------------
create or replace function public.ensure_nailbook_profile(
    p_role text default null,
    p_full_name text default null,
    p_phone text default null,
    p_city text default null,
    p_location text default null,
    p_business_name text default null,
    p_services jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
    v_user_id uuid := auth.uid();
    v_auth_email text;
    v_meta jsonb;
    v_existing_role text;
    v_role text;
    v_name text;
    v_phone text;
    v_city text;
    v_location text;
    v_business text;
    v_services jsonb;
    v_service_name text;
    v_service_id bigint;
begin
    if v_user_id is null then
        raise exception 'You must be signed in.' using errcode = '42501';
    end if;

    select email, raw_user_meta_data
      into v_auth_email, v_meta
      from auth.users
     where id = v_user_id;

    select role
      into v_existing_role
      from public.profiles
     where user_id = v_user_id;

    -- Once a role exists, do not allow later metadata changes to switch it.
    v_role := coalesce(v_existing_role,
        case when p_role in ('artist','client') then p_role end,
        case when v_meta->>'role' in ('artist','client') then v_meta->>'role' end,
        'client'
    );

    v_name := coalesce(
        nullif(trim(p_full_name),''),
        nullif(trim(v_meta->>'full_name'),''),
        'NailBook User'
    );
    v_phone := coalesce(nullif(trim(p_phone),''), nullif(trim(v_meta->>'phone'),''));
    v_city := coalesce(nullif(trim(p_city),''), nullif(trim(v_meta->>'city'),''));
    v_location := coalesce(nullif(trim(p_location),''), nullif(trim(v_meta->>'location'),''), v_city, '');
    v_business := coalesce(nullif(trim(p_business_name),''), nullif(trim(v_meta->>'business_name'),''), v_name);
    v_services := case
        when jsonb_typeof(coalesce(p_services, v_meta->'services', '[]'::jsonb)) = 'array'
        then coalesce(p_services, v_meta->'services', '[]'::jsonb)
        else '[]'::jsonb
    end;

    insert into public.profiles(user_id, role, full_name, email, phone, city)
    values(v_user_id, v_role, v_name, lower(coalesce(v_auth_email,'')), v_phone, v_city)
    on conflict(user_id) do update set
        full_name = excluded.full_name,
        email = excluded.email,
        phone = excluded.phone,
        city = excluded.city,
        updated_at = now();

    if v_role = 'artist' then
        insert into public.artist_profiles(
            user_id, business_name, location, bio, gallery
        ) values(
            v_user_id,
            v_business,
            v_location,
            'Welcome to NailBook. Update your bio from your artist dashboard.',
            jsonb_build_array(
                'https://images.unsplash.com/photo-1604654894610-df63bc536371?auto=format&fit=crop&w=900&q=80',
                'https://images.unsplash.com/photo-1610992015732-2449b76344bc?auto=format&fit=crop&w=900&q=80'
            )
        )
        on conflict(user_id) do update set
            business_name = excluded.business_name,
            location = excluded.location,
            updated_at = now();

        if jsonb_array_length(v_services) > 0 then
            for v_service_name in
                select jsonb_array_elements_text(v_services)
            loop
                select service_id into v_service_id
                  from public.services
                 where lower(trim(service_name)) = lower(trim(v_service_name))
                 limit 1;

                if v_service_id is not null then
                    insert into public.artist_services(artist_id, service_id, is_available)
                    values(v_user_id, v_service_id, true)
                    on conflict(artist_id, service_id) do update set is_available = true;
                end if;
            end loop;
        end if;
    else
        insert into public.client_profiles(user_id)
        values(v_user_id)
        on conflict(user_id) do nothing;
    end if;

    return jsonb_build_object(
        'user_id', v_user_id,
        'role', v_role,
        'full_name', v_name,
        'email', lower(coalesce(v_auth_email,''))
    );
end;
$$;

revoke all on function public.ensure_nailbook_profile(text,text,text,text,text,text,jsonb) from public;
grant execute on function public.ensure_nailbook_profile(text,text,text,text,text,text,jsonb) to authenticated;

-- ------------------------------------------------------------
-- 13. ARTIST DIRECTORY VIEW
-- This is the single source used by Find Artists.
-- ------------------------------------------------------------
create or replace view public.v_artist_directory
with (security_invoker = true)
as
select
    ap.user_id as artist_id,
    ap.business_name,
    ap.location,
    ap.bio,
    ap.years_experience,
    ap.average_rating,
    ap.review_count,
    ap.total_bookings,
    ap.is_available,
    ap.gallery,
    ap.instagram_handle,
    coalesce(
        jsonb_agg(
            jsonb_build_object(
                'service_id', s.service_id,
                'service_name', s.service_name,
                'price', ass.price,
                'duration_minutes', coalesce(ass.duration_minutes, s.default_duration_minutes)
            ) order by s.service_name
        ) filter(where s.service_id is not null),
        '[]'::jsonb
    ) as services
from public.artist_profiles ap
left join public.artist_services ass
    on ass.artist_id = ap.user_id
   and ass.is_available = true
left join public.services s
    on s.service_id = ass.service_id
group by
    ap.user_id, ap.business_name, ap.location, ap.bio,
    ap.years_experience, ap.average_rating, ap.review_count,
    ap.total_bookings, ap.is_available, ap.gallery,
    ap.instagram_handle;

-- ------------------------------------------------------------
-- 12B. REVIEW RATING AGGREGATION
-- Keeps artist rating and review count synchronized with reviews.
-- ------------------------------------------------------------
create or replace function public.refresh_artist_rating()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
    v_artist_id uuid;
begin
    v_artist_id := coalesce(new.artist_id, old.artist_id);
    update public.artist_profiles ap
       set average_rating = coalesce((select round(avg(r.rating)::numeric, 2) from public.reviews r where r.artist_id = v_artist_id and r.is_visible = true), 0),
           review_count = (select count(*) from public.reviews r where r.artist_id = v_artist_id and r.is_visible = true),
           updated_at = now()
     where ap.user_id = v_artist_id;
    if tg_op = 'DELETE' then
        return old;
    end if;
    return new;
end;
$$;

create trigger reviews_refresh_artist_rating
after insert or update or delete on public.reviews
for each row execute function public.refresh_artist_rating();

-- ------------------------------------------------------------
-- 13B. BOOKING DASHBOARD VIEWS
-- Security-definer views expose only the signed-in user's bookings while
-- avoiding broad access to other users' profile data.
-- ------------------------------------------------------------
create or replace view public.v_my_bookings
with (security_invoker = false)
as
select
    b.booking_id,
    b.client_id,
    b.artist_id,
    b.service_id,
    b.booking_date,
    b.start_time,
    b.end_time,
    b.status,
    b.price,
    b.client_notes,
    b.artist_notes,
    b.created_at,
    b.updated_at,
    cp.full_name as client_name,
    cp.email as client_email,
    ap.business_name as artist_name,
    ap.location as artist_location,
    s.service_name
from public.bookings b
join public.profiles cp on cp.user_id = b.client_id
join public.artist_profiles ap on ap.user_id = b.artist_id
join public.services s on s.service_id = b.service_id
where b.client_id = auth.uid() or b.artist_id = auth.uid();

-- ------------------------------------------------------------
-- 13C. CONTACT / SUPPORT MESSAGE RPC
-- Used by Contact Us so anonymous and signed-in visitors can submit
-- support messages without needing direct table write logic in the browser.
-- ------------------------------------------------------------
create or replace function public.submit_support_message(
    p_name text,
    p_email text,
    p_subject text,
    p_message text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
    v_id uuid;
begin
    if length(trim(coalesce(p_name,''))) < 2 then
        raise exception 'Please enter your name.';
    end if;
    if length(trim(coalesce(p_email,''))) < 5 then
        raise exception 'Please enter a valid email address.';
    end if;
    if length(trim(coalesce(p_subject,''))) < 1 then
        raise exception 'Please select a subject.';
    end if;
    if length(trim(coalesce(p_message,''))) < 2 then
        raise exception 'Please enter a message.';
    end if;

    insert into public.support_messages(user_id,name,email,subject,message)
    values(auth.uid(),trim(p_name),lower(trim(p_email)),trim(p_subject),trim(p_message))
    returning message_id into v_id;

    return v_id;
end;
$$;

revoke all on function public.submit_support_message(text,text,text,text) from public;
grant execute on function public.submit_support_message(text,text,text,text) to anon, authenticated;

-- ------------------------------------------------------------
-- 13D. SUPABASE STORAGE FOR ARTIST GALLERIES
-- Publicly readable images; artists can upload/delete only inside their
-- own UUID folder.
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('artist-gallery','artist-gallery',true)
on conflict (id) do update set public = true;

drop policy if exists artist_gallery_public_read on storage.objects;
drop policy if exists artist_gallery_insert_own on storage.objects;
drop policy if exists artist_gallery_update_own on storage.objects;
drop policy if exists artist_gallery_delete_own on storage.objects;

create policy artist_gallery_public_read
on storage.objects for select
to anon, authenticated
using (bucket_id = 'artist-gallery');

create policy artist_gallery_insert_own
on storage.objects for insert
to authenticated
with check (bucket_id = 'artist-gallery' and (storage.foldername(name))[1] = auth.uid()::text);

create policy artist_gallery_update_own
on storage.objects for update
to authenticated
using (bucket_id = 'artist-gallery' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'artist-gallery' and (storage.foldername(name))[1] = auth.uid()::text);

create policy artist_gallery_delete_own
on storage.objects for delete
to authenticated
using (bucket_id = 'artist-gallery' and (storage.foldername(name))[1] = auth.uid()::text);

-- ------------------------------------------------------------
-- 14. RLS
-- ------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.artist_profiles enable row level security;
alter table public.client_profiles enable row level security;
alter table public.services enable row level security;
alter table public.artist_services enable row level security;
alter table public.bookings enable row level security;
alter table public.favorites enable row level security;
alter table public.reviews enable row level security;
alter table public.support_messages enable row level security;

create policy profiles_select_own on public.profiles
for select to authenticated using(user_id = auth.uid());

create policy profiles_update_own on public.profiles
for update to authenticated
using(user_id = auth.uid())
with check(user_id = auth.uid());

create policy artist_profiles_public_read on public.artist_profiles
for select to anon, authenticated using(true);

create policy artist_profiles_insert_own on public.artist_profiles
for insert to authenticated with check(user_id = auth.uid());

create policy artist_profiles_update_own on public.artist_profiles
for update to authenticated
using(user_id = auth.uid())
with check(user_id = auth.uid());

create policy client_profiles_select_own on public.client_profiles
for select to authenticated using(user_id = auth.uid());

create policy client_profiles_update_own on public.client_profiles
for update to authenticated
using(user_id = auth.uid())
with check(user_id = auth.uid());

create policy services_public_read on public.services
for select to anon, authenticated using(true);

create policy artist_services_public_read on public.artist_services
for select to anon, authenticated using(is_available = true);

create policy artist_services_insert_own on public.artist_services
for insert to authenticated with check(artist_id = auth.uid());

create policy artist_services_update_own on public.artist_services
for update to authenticated
using(artist_id = auth.uid())
with check(artist_id = auth.uid());

create policy artist_services_delete_own on public.artist_services
for delete to authenticated using(artist_id = auth.uid());

create policy bookings_select_participants on public.bookings
for select to authenticated
using(client_id = auth.uid() or artist_id = auth.uid());

create policy bookings_insert_client on public.bookings
for insert to authenticated
with check(
    client_id = auth.uid()
    and exists(
        select 1 from public.profiles p
        where p.user_id = auth.uid() and p.role = 'client'
    )
    and exists(
        select 1 from public.artist_services ass
        where ass.artist_id = bookings.artist_id
          and ass.service_id = bookings.service_id
          and ass.is_available = true
    )
);

create policy bookings_update_participants on public.bookings
for update to authenticated
using(client_id = auth.uid() or artist_id = auth.uid())
with check(client_id = auth.uid() or artist_id = auth.uid());

create policy favorites_select_own on public.favorites
for select to authenticated using(client_id = auth.uid());

create policy favorites_insert_own on public.favorites
for insert to authenticated with check(client_id = auth.uid());

create policy favorites_delete_own on public.favorites
for delete to authenticated using(client_id = auth.uid());

create policy reviews_public_read on public.reviews
for select to anon, authenticated using(is_visible = true);

create policy reviews_insert_own on public.reviews
for insert to authenticated
with check(
    client_id = auth.uid()
    and exists(
        select 1 from public.bookings b
        where b.booking_id = reviews.booking_id
          and b.client_id = auth.uid()
          and b.artist_id = reviews.artist_id
          and b.status = 'completed'
    )
);

create policy support_insert_anyone on public.support_messages
for insert to anon, authenticated with check(true);

-- ------------------------------------------------------------
-- 15. API GRANTS
-- ------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select on public.artist_profiles to anon, authenticated;
grant select on public.services to anon, authenticated;
grant select on public.artist_services to anon, authenticated;
grant select on public.reviews to anon, authenticated;
grant select on public.v_artist_directory to anon, authenticated;
grant select on public.v_my_bookings to authenticated;
grant select, update on public.profiles to authenticated;
grant select, update on public.client_profiles to authenticated;
grant select, insert, update on public.artist_profiles to authenticated;
grant select, insert, update, delete on public.artist_services to authenticated;
grant select, insert, update on public.bookings to authenticated;
grant select, insert, delete on public.favorites to authenticated;
grant select, insert on public.reviews to authenticated;
grant insert on public.support_messages to anon, authenticated;
grant execute on function public.submit_support_message(text,text,text,text) to anon, authenticated;

-- ------------------------------------------------------------
-- 16. FINAL CHECKS
-- ------------------------------------------------------------
select 'profiles' as table_name, count(*) as rows from public.profiles
union all select 'artist_profiles', count(*) from public.artist_profiles
union all select 'client_profiles', count(*) from public.client_profiles
union all select 'services', count(*) from public.services
union all select 'artist_services', count(*) from public.artist_services
union all select 'bookings', count(*) from public.bookings
union all select 'favorites', count(*) from public.favorites
union all select 'reviews', count(*) from public.reviews
union all select 'support_messages', count(*) from public.support_messages
order by table_name;

select id as storage_bucket, public from storage.buckets where id = 'artist-gallery';

-- This should return zero rows in a dedicated NailBook project.
select tgname as remaining_custom_auth_trigger
from pg_trigger
where tgrelid = 'auth.users'::regclass
  and not tgisinternal;
