-- ROLLBACK for migration 0009 (functions)
drop function if exists public.reassign_products_category(text, text);
drop function if exists public.settle_order(uuid, public.payment_status, text);
drop function if exists public.get_order_by_token(uuid);
drop function if exists public.create_order(jsonb, uuid, text, text);
drop function if exists public.release_expired_reservations();
