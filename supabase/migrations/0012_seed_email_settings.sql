-- =============================================================================
-- GEES Convenience Store — Stage 3 migration 0012
-- Seed: email_settings (one row per email_type, copy pending owner export)
-- Rollback: supabase/rollback/0012_seed_email_settings.sql
--
-- The reference stores template copy in this table and today has 0 rows; the
-- reference's own fallback is empty copy. We seed empty subject/html (decision
-- N2) and will replace with the owner's exported copy verbatim when available.
-- =============================================================================

insert into public.email_settings (type, subject, html, enabled) values
  ('order_confirmation',   '', '', true),
  ('payment_confirmation', '', '', true),
  ('status_received',      '', '', true),
  ('status_processing',    '', '', true),
  ('status_dispatched',    '', '', true),
  ('status_delivered',     '', '', true),
  ('status_cancelled',     '', '', true),
  ('welcome',              '', '', true)
on conflict (type) do nothing;
