-- =============================================================================
-- GEES Convenience Store — Stage 3 migration 0000
-- Extensions + shared helper functions
-- Rollback: supabase/rollback/0000_init_extensions_helpers.sql
-- Postconditions: pgcrypto present; public.set_updated_at() exists.
-- (public.is_admin() is created in 0002 — see NOTE below.)
-- =============================================================================

create extension if not exists pgcrypto;

-- Generic updated_at trigger helper (invoker rights — no SECURITY DEFINER).
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end
$$;

-- NOTE: public.is_admin() is created in migration 0002, immediately after
-- public.profiles exists. It is a `language sql` function, which PostgreSQL
-- validates at CREATE time, so it cannot be created before the table it reads.
