-- =============================================================================
-- GEES Convenience Store — Stage 3 migration 0007
-- store_settings (singleton) + RLS
-- Rollback: supabase/rollback/0007_store_settings.sql
-- =============================================================================

create table public.store_settings (
  id              int primary key default 1 check (id = 1),
  delivery_fee    numeric(10,2) not null default 100,
  store_name      text not null default 'GEES Convenience Store',
  slogan          text not null default '',
  delivery_info   text not null default '',
  refund_policy   text not null default '',
  privacy_policy  text not null default '',
  terms           text not null default '',
  contact_email   text not null default '',
  contact_phone   text not null default '',
  payment_link    text not null default '',
  -- Additive extension: NULL keeps the links hidden (no generic/fake links).
  social_instagram text null,
  social_facebook  text null,
  social_tiktok    text null,
  updated_at      timestamptz not null default now()
);

create trigger store_settings_set_updated_at
  before update on public.store_settings
  for each row execute function public.set_updated_at();

alter table public.store_settings enable row level security;

create policy store_settings_select_all on public.store_settings
  for select to anon, authenticated using (true);
create policy store_settings_insert_admin on public.store_settings
  for insert to authenticated with check (public.is_admin());
create policy store_settings_update_admin on public.store_settings
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy store_settings_delete_admin on public.store_settings
  for delete to authenticated using (public.is_admin());

grant select on public.store_settings to anon, authenticated;
grant insert, update, delete on public.store_settings to authenticated;

-- service_role (server-only): the server reads the singleton for delivery-fee and
-- store metadata (A2-1). Edits stay with the admin (authenticated) RLS policies.
grant select on public.store_settings to service_role;
