-- ROLLBACK for migration 0006 (orders + sequence + reservations + events)
-- Preconditions: email_logs.order_id FK must be gone (roll back 0008);
--                create_order/settle_order must be gone (roll back 0009).
drop table if exists public.payment_events cascade;
drop table if exists public.stock_reservations cascade;
drop table if exists public.orders cascade;
drop function if exists public.next_order_reference();
drop sequence if exists public.order_reference_seq;
