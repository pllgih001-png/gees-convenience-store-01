-- ROLLBACK for migration 0003 (categories)
-- Preconditions: products and box_theme_categories FKs must be gone (roll back 0005, 0004).
drop table if exists public.categories cascade;
