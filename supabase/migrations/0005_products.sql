-- =============================================================================
-- GEES Convenience Store — Stage 3 migration 0005
-- products + category FK + indexes + RLS
-- Rollback: supabase/rollback/0005_products.sql
-- Depends on: 0003 (categories.slug UNIQUE)
-- =============================================================================

create table public.products (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  description   text not null default '',
  price         numeric(10,2) not null check (price >= 0),
  sale_price    numeric(10,2) null check (sale_price >= 0),
  category_slug text null references public.categories(slug) on update cascade on delete set null,
  image_url     text not null default '',
  stock         int not null default 0 check (stock >= 0),
  is_new        boolean not null default false,
  is_trending   boolean not null default false,
  box_eligible  boolean not null default true,
  visible       boolean not null default true,
  sort_order    int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger products_set_updated_at
  before update on public.products
  for each row execute function public.set_updated_at();

create index products_category_slug_idx on public.products (category_slug);
create index products_visible_idx on public.products (visible);

alter table public.products enable row level security;

create policy products_select_all on public.products
  for select to anon, authenticated using (true);
create policy products_insert_admin on public.products
  for insert to authenticated with check (public.is_admin());
create policy products_update_admin on public.products
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy products_delete_admin on public.products
  for delete to authenticated using (public.is_admin());

grant select on public.products to anon, authenticated;
grant insert, update, delete on public.products to authenticated;

-- service_role (server-only): read access for server-side/admin reads (A2-1).
grant select on public.products to service_role;
