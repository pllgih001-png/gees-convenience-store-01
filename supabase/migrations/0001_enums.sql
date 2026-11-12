-- =============================================================================
-- GEES Convenience Store — Stage 3 migration 0001
-- Enum types
-- Rollback: supabase/rollback/0001_enums.sql
-- =============================================================================

create type public.order_status as enum (
  'pending_payment', 'paid', 'processing', 'shipped', 'delivered', 'cancelled'
);

create type public.payment_status as enum ('unpaid', 'paid', 'failed');

create type public.email_type as enum (
  'order_confirmation', 'payment_confirmation', 'status_received',
  'status_processing', 'status_dispatched', 'status_delivered',
  'status_cancelled', 'welcome'
);

create type public.user_role as enum ('customer', 'admin');

create type public.email_log_status as enum ('sent', 'failed', 'skipped');

-- Internal-only: stock reservation lifecycle.
create type public.reservation_status as enum ('held', 'committed', 'released', 'expired');
