-- ROLLBACK for migration 0010 (seeded catalogue)
-- Deletes ONLY the seeded rows (matched by the exact names shipped in 0010).
delete from public.products
 where sort_order between 0 and 24
   and category_slug in ('accessories','beauty','home','books-stationery','gifts');
delete from public.box_theme_categories
 where box_theme_id in (select id from public.box_themes)
   and category_slug in ('accessories','beauty','home','books-stationery','gifts');
delete from public.box_themes
 where name in ('Self-Care Sunday','Desk & Dream','Cosy Home','Shine On');
delete from public.categories
 where slug in ('gifts','books-stationery','home','beauty','accessories');
