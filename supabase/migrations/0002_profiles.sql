-- =============================================================================
-- GEES Convenience Store — Stage 3 migration 0002
-- profiles + signup provisioning trigger + role-escalation guard + RLS
-- Rollback: supabase/rollback/0002_profiles.sql
-- Depends on: 0000 (set_updated_at, is_admin), 0001 (user_role)
-- =============================================================================

create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  role       public.user_role not null default 'customer',
  full_name  text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Signup provisioning. role is HARD-CODED to 'customer'; only a display value
-- (full_name) is copied from user-editable metadata. Never trust metadata for role.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, role, full_name)
  values (
    new.id,
    'customer',
    coalesce(new.raw_user_meta_data ->> 'full_name', '')
  )
  on conflict (id) do nothing;
  return new;
end
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Role-escalation guard. A role change is only permitted for a service-role
-- (server) caller. Uses the verified JWT claim, NOT the deprecated auth.role().
-- ---------------------------------------------------------------------------
create or replace function public.prevent_role_escalation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.role is distinct from old.role then
    if coalesce(auth.jwt() ->> 'role', 'anon') <> 'service_role' then
      raise exception 'role_change_forbidden' using errcode = '42501';
    end if;
  end if;
  return new;
end
$$;

create trigger profiles_prevent_role_escalation
  before update on public.profiles
  for each row execute function public.prevent_role_escalation();

-- Trigger functions are invoked by the trigger system (which does not check the
-- caller's EXECUTE privilege), so no client role needs EXECUTE. Revoke the implicit
-- PUBLIC grant to keep the §20 hardening rule ("no `=X` PUBLIC grant on any definer
-- function") true for every definer function, including these two.
revoke all on function public.handle_new_user() from public;
revoke all on function public.prevent_role_escalation() from public;

-- ---------------------------------------------------------------------------
-- Admin predicate used by RLS policies below.
-- Created HERE (not in 0000) because it is `language sql` and PostgreSQL
-- validates the body at CREATE time; it reads public.profiles, which must exist.
-- SECURITY DEFINER (owner = migration role) so policies can read the role column
-- without recursing into profiles RLS. search_path pinned; references qualified.
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  )
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RLS: no client INSERT/DELETE; a user may read/update only their own row.
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;

create policy profiles_select_own_or_admin on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_admin());

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

grant select, update on public.profiles to authenticated;

-- service_role (trusted server role, server-only): the approved server-side
-- role-provisioning flow (§11) reads a profile and EXTENDS/CHANGES its role.
-- Hosted Supabase no longer grants default privileges on new public objects
-- (enforced 2026-10-30), so this is stated explicitly (A2-1).
grant select, update on public.profiles to service_role;
