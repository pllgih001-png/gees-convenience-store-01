-- ROLLBACK for migration 0001 (enum types)
-- Preconditions: no columns/policies using these types (roll back 0002-0008 first).
drop type if exists public.reservation_status;
drop type if exists public.email_log_status;
drop type if exists public.user_role;
drop type if exists public.email_type;
drop type if exists public.payment_status;
drop type if exists public.order_status;
