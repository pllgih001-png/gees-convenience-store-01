-- ROLLBACK for migration 0005 (products)
-- Preconditions: stock_reservations.product_id FK must be gone (roll back 0006).
drop table if exists public.products cascade;
