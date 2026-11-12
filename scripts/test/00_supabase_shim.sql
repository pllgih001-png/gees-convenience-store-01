-- =============================================================================
-- SCRATCH-ONLY Supabase environment shim (NOT part of the deliverable schema).
-- Emulates the parts of a Supabase project that migrations rely on, so the
-- migrations and RLS tests can be executed against a local PostgreSQL 16.
-- Real Supabase provides all of these; on a real project this file is NOT run.
-- =============================================================================

-- Roles that real Supabase creates.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

grant usage on schema public to anon, authenticated, service_role;

-- Real Supabase grants service_role broad privileges on the public schema (it is
-- the trusted server role and also BYPASSRLS). Emulate that so server-side
-- functions/paths behave as they would on a real project. Applies to objects
-- created AFTER this point (i.e. the migrations).
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant all on functions to service_role;

-- auth schema: users table + uid()/jwt() helpers backed by the request GUC.
create schema if not exists auth;

create table if not exists auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text,
  raw_user_meta_data jsonb not null default '{}'::jsonb
);

create or replace function auth.jwt()
returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
$$;

create or replace function auth.uid()
returns uuid language sql stable as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid;
$$;

grant usage on schema auth to anon, authenticated, service_role;
