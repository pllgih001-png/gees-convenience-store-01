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

-- ---------------------------------------------------------------------------
-- A2-1: model the CURRENT hosted Supabase default-privilege behaviour.
--
-- Supabase is removing the automatic grants that previously applied to new
-- objects in the `public` schema, making Data-API exposure opt-in. This is the
-- platform default for new projects and is enforced for ALL existing projects
-- on 2026-10-30:
--   * new tables/views  -> no automatic grant to anon / authenticated / service_role
--   * new sequences     -> no automatic grant to those roles
--   * new functions     -> still callable via the global PUBLIC EXECUTE default,
--                          which the migrations remove with `revoke ... from public`
-- Docs: https://supabase.com/docs/guides/api/securing-your-api ("Default privileges")
--       https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically
--
-- Therefore this shim intentionally sets NO default privileges: every role
-- privilege on a migration-created object must come from an explicit `grant` in
-- the migration itself. (An earlier revision granted `all` to service_role via
-- default privileges, which diverged from hosted Supabase and masked missing
-- grants — that is the divergence this file now avoids.)
-- ---------------------------------------------------------------------------

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
