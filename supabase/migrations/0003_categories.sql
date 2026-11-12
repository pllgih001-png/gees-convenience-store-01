-- =============================================================================
-- GEES Convenience Store — Stage 3 migration 0003
-- categories + RLS
-- Rollback: supabase/rollback/0003_categories.sql
-- Depends on: 0000
-- =============================================================================

create table public.categories (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  slug       text not null unique,
  sort_order int  not null default 0,
  visible    boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger categories_set_updated_at
  before update on public.categories
  for each row execute function public.set_updated_at();

alter table public.categories enable row level security;

-- Public catalogue: readable by everyone.
create policy categories_select_all on public.categories
  for select to anon, authenticated
  using (true);

create policy categories_insert_admin on public.categories
  for insert to authenticated
  with check (public.is_admin());

create policy categories_update_admin on public.categories
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy categories_delete_admin on public.categories
  for delete to authenticated
  using (public.is_admin());

grant select on public.categories to anon, authenticated;
grant insert, update, delete on public.categories to authenticated;
