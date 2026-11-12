-- =============================================================================
-- GEES Convenience Store — Stage 3 migration 0004
-- box_themes + box_theme_categories (join table) + RLS
-- Rollback: supabase/rollback/0004_box_themes.sql
-- Depends on: 0003 (categories.slug)
-- =============================================================================

create table public.box_themes (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  description text not null default '',
  active      boolean not null default true,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger box_themes_set_updated_at
  before update on public.box_themes
  for each row execute function public.set_updated_at();

-- Join table replacing the reference's categories[] array.
create table public.box_theme_categories (
  box_theme_id  uuid not null references public.box_themes(id) on delete cascade,
  category_slug text not null references public.categories(slug) on update cascade on delete cascade,
  primary key (box_theme_id, category_slug)
);

alter table public.box_themes enable row level security;
alter table public.box_theme_categories enable row level security;

create policy box_themes_select_all on public.box_themes
  for select to anon, authenticated using (true);
create policy box_themes_insert_admin on public.box_themes
  for insert to authenticated with check (public.is_admin());
create policy box_themes_update_admin on public.box_themes
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy box_themes_delete_admin on public.box_themes
  for delete to authenticated using (public.is_admin());

create policy box_theme_categories_select_all on public.box_theme_categories
  for select to anon, authenticated using (true);
create policy box_theme_categories_insert_admin on public.box_theme_categories
  for insert to authenticated with check (public.is_admin());
create policy box_theme_categories_update_admin on public.box_theme_categories
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy box_theme_categories_delete_admin on public.box_theme_categories
  for delete to authenticated using (public.is_admin());

grant select on public.box_themes, public.box_theme_categories to anon, authenticated;
grant insert, update, delete on public.box_themes, public.box_theme_categories to authenticated;
