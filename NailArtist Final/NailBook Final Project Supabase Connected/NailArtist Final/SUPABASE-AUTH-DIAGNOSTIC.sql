-- NailBook authentication diagnostic
-- Run this if Supabase still says: Database error saving new user

-- 1. Any custom triggers on auth.users? This should return ZERO rows.
select
  tgname,
  pg_get_triggerdef(oid) as trigger_definition
from pg_trigger
where tgrelid = 'auth.users'::regclass
  and not tgisinternal
order by tgname;

-- 2. Check functions that are explicitly executable by Supabase Auth.
-- This can help reveal a Postgres Auth Hook function.
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where has_function_privilege('supabase_auth_admin', p.oid, 'EXECUTE')
  and n.nspname not in ('pg_catalog','information_schema')
order by n.nspname, p.proname;

-- 3. Check for unusual constraints on auth.users.
select
  conname,
  contype,
  pg_get_constraintdef(oid) as constraint_definition
from pg_constraint
where conrelid = 'auth.users'::regclass
order by conname;

-- 4. Confirm NailBook's provisioning function exists.
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'ensure_nailbook_profile';

-- 5. Confirm required NailBook tables exist.
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in (
    'profiles','artist_profiles','client_profiles','services',
    'artist_services','bookings','favorites','reviews','support_messages'
  )
order by table_name;
