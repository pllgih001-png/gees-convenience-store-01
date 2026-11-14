-- =============================================================================
-- GEES Convenience Store — Stage 3 migration 0008
-- email_settings + email_logs (+ orders FK) + RLS
-- Rollback: supabase/rollback/0008_email.sql
-- Depends on: 0001 (email_type, email_log_status), 0006 (orders.id)
-- =============================================================================

create table public.email_settings (
  id         uuid primary key default gen_random_uuid(),
  type       public.email_type not null unique,
  subject    text not null default '',
  html       text not null default '',
  enabled    boolean not null default true,
  updated_at timestamptz not null default now()
);

create trigger email_settings_set_updated_at
  before update on public.email_settings
  for each row execute function public.set_updated_at();

create table public.email_logs (
  id              uuid primary key default gen_random_uuid(),
  order_id        uuid null references public.orders(id) on delete set null,
  order_reference text null,
  type            public.email_type not null,
  to_email        text not null,
  status          public.email_log_status not null,
  error           text null,
  attempts        int not null default 0,
  created_at      timestamptz not null default now()
);

create index email_logs_order_idx on public.email_logs (order_id);

alter table public.email_settings enable row level security;
alter table public.email_logs enable row level security;

-- Templates & logs are admin-only, and are written by the server (service role).
create policy email_settings_admin_all on public.email_settings
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy email_logs_select_admin on public.email_logs
  for select to authenticated using (public.is_admin());
create policy email_logs_update_admin on public.email_logs
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy email_logs_delete_admin on public.email_logs
  for delete to authenticated using (public.is_admin());

grant select, insert, update, delete on public.email_settings to authenticated;
grant select, update, delete on public.email_logs to authenticated;
-- Logs are inserted by the server only (service role bypasses RLS).
revoke insert on public.email_logs from anon, authenticated;

-- service_role (trusted server role, server-only) — A2-1. Hosted Supabase no
-- longer grants default privileges on new public objects (enforced 2026-10-30).
-- The server reads templates to send and owns the email-log lifecycle; templates
-- themselves are edited by the admin (authenticated) RLS policies above.
grant select on public.email_settings to service_role;
grant select, insert, update on public.email_logs to service_role;
