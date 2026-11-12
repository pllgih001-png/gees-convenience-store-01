-- ROLLBACK for migration 0008 (email settings + logs)
drop table if exists public.email_logs cascade;
drop table if exists public.email_settings cascade;
