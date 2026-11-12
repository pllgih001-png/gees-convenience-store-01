-- ROLLBACK for migration 0004 (box themes + join table)
drop table if exists public.box_theme_categories cascade;
drop table if exists public.box_themes cascade;
