-- =============================================================================
-- GEES Convenience Store — Stage 3 migration 0010
-- Seed: 5 categories, 4 box themes, 6 theme-category links, 25 products
-- Rollback: supabase/rollback/0010_seed_catalogue.sql
-- Source: read-only Base44 public API snapshot (migration/source-snapshot/*.json).
-- Values are transcribed verbatim; nothing is invented.
--
-- NOTE on image_url: the reference asset URLs (media.base44.com) are preserved
--   verbatim here because asset migration is explicitly OUT of Stage 3 (Stage 11).
--   The "no media.base44.com rows" assertion is therefore DEFERRED to Stage 11.
-- =============================================================================

insert into public.categories (name, slug, sort_order) values
  ('Gifts',              'gifts',             1),
  ('Books & Stationery', 'books-stationery',  2),
  ('Home',               'home',              3),
  ('Beauty',             'beauty',            4),
  ('Accessories',        'accessories',       5);

insert into public.box_themes (name, description) values
  ('Self-Care Sunday', 'Spa sets, candles and beauty treats'),
  ('Desk & Dream',     'Stationery, journals and creative kits'),
  ('Cosy Home',        'Kitchen, storage and home essentials'),
  ('Shine On',         'Jewellery, hair accessories and little luxuries');

-- 6 links (the reference's four themes × their categories[] entries).
insert into public.box_theme_categories (box_theme_id, category_slug)
select t.id, v.slug
from (values
  ('Shine On',         'accessories'),
  ('Shine On',         'beauty'),
  ('Cosy Home',        'home'),
  ('Desk & Dream',     'books-stationery'),
  ('Self-Care Sunday', 'beauty'),
  ('Self-Care Sunday', 'gifts')
) as v(theme, slug)
join public.box_themes t on t.name = v.theme;

insert into public.products
  (name, description, price, sale_price, category_slug, image_url, stock,
   is_new, is_trending, box_eligible, visible, sort_order)
values
  ('Jewellery Cleaner', 'Restore the sparkle to your jewellery.', 249.00, null, 'accessories', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/473165bd9_vjyyjytnzpekjbqovqst_supabase_co_1ce2c5d4-ebef-41b9-87d1-1ec23ee8beaf_f581a68a.jpeg', 8, true, false, false, true, 0),
  ('12pc Evil Eye Jewelry Set with Bracelet Necklace Pendant Ornament Earrings', '12-piece evil eye jewellery set.', 249.00, null, 'accessories', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/c9c942dd2_vjyyjytnzpekjbqovqst_supabase_co_036fdb89-76d8-4bb9-ba35-d43fa36b0f17_9b5fade8.jpeg', 13, true, true, true, true, 1),
  ('4 Pieces Emerald Style Bracelets Set Cubic Zirconia Chain Adjustable Jewelry', 'Four adjustable emerald-style bracelets.', 194.00, null, 'accessories', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/8908bbb4d_vjyyjytnzpekjbqovqst_supabase_co_e3a35c47-448e-4ce1-ad05-220f5d96d4af_5d479435.jpeg', 17, true, false, true, true, 2),
  ('58 Pieces Women''s Gold Jewelry Set Earrings Rings Necklaces Bracelets Gold', '58-piece gold jewellery set.', 264.00, null, 'accessories', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/6aa707b66_vjyyjytnzpekjbqovqst_supabase_co_e2fa8ca8-c0af-483a-b752-1189bf612fce_d6db8891.jpeg', 11, true, true, true, true, 3),
  ('5-piece set of vintage hairpins - Camellia-shaped hairpins with pearls', 'Vintage camellia hairpins with pearls.', 184.00, null, 'accessories', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/7c74caea3_vjyyjytnzpekjbqovqst_supabase_co_8d99dbc6-23ed-45fc-bdca-af7ffecf3c96_1ca5f31f.jpeg', 21, true, false, true, true, 4),
  ('3 Piece Evil Eye Hair Clip Set - Acrylic Claw Clips for Women', 'Three acrylic claw clips with an evil eye motif.', 188.00, null, 'accessories', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/dbb2341fc_vjyyjytnzpekjbqovqst_supabase_co_79c8866b-2c3f-4c11-a294-cf1cc8e64024_6caecbf5.jpeg', 28, true, true, true, true, 5),
  ('Crease Less Sliding Sectioning Hair Clips', 'Crease-free sectioning clips for styling.', 184.00, null, 'beauty', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/5b9e9f74e_vjyyjytnzpekjbqovqst_supabase_co_4e3f09a9-4945-4892-9fc5-aac9b65e1bc2_a50dd543.jpeg', 0, true, false, true, true, 6),
  ('18 Pieces Makeup Brushes Set with 5 Sponges & Holder & Sponge Case', '18 brushes, 5 sponges, holder and case.', 336.00, null, 'beauty', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/d98c3bd9e_vjyyjytnzpekjbqovqst_supabase_co_75c47240-e249-48c4-b9d6-2e328e12c260_244502d2.jpeg', 16, true, true, true, true, 7),
  ('Heatless Curling Set for No-Heat Soft Curls - Heatless Curls Overnight', 'Overnight heatless curls without damage.', 199.00, null, 'beauty', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/90abdadd0_vjyyjytnzpekjbqovqst_supabase_co_22c40967-7cb5-4307-8ed9-caabe057fdbb_1c485860.jpeg', 33, true, true, true, true, 8),
  ('Sulfar 4 Piece Airtight Food Storage Containers Clear Purple', 'Airtight food storage containers in clear purple.', 211.00, null, 'home', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/aa1c104e3_vjyyjytnzpekjbqovqst_supabase_co_7b4da223-0ac0-4b9f-b34f-cc02f1eeca96_d77d86e4.jpeg', 20, true, true, true, true, 9),
  ('2 Packs Of 100, 250mm x 360mm Plastic Zip Lock Bags', 'Two packs of 100 zip lock bags.', 334.00, null, 'home', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/ddab14e75_vjyyjytnzpekjbqovqst_supabase_co_f5a8ba1c-3b28-4e4c-885f-fe477597beb1_3c5e11d3.jpeg', 12, true, false, false, true, 10),
  ('Plastic Bag on a Roll - 1000 Bags', 'A roll of 1000 handy bags.', 115.00, null, 'home', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/fb843d920_vjyyjytnzpekjbqovqst_supabase_co_69b86320-2755-4b23-b8d0-89bf136510e8_68d3c48c.jpeg', 45, true, false, true, true, 11),
  ('Prestige Funnel Set - 4 Piece', 'Four-piece funnel set for the kitchen.', 69.00, null, 'home', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/e9e808afa_vjyyjytnzpekjbqovqst_supabase_co_9fc8ef81-b2e0-4ed4-9ee5-2e7a66f85f7b_9b606738.jpeg', 60, true, false, true, true, 12),
  ('19 Piece Silicone Kitchen Set with Knives, Cutting Board and Storage Rack', '19-piece silicone kitchen set with storage rack.', 236.00, null, 'home', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/361a83b8b_vjyyjytnzpekjbqovqst_supabase_co_ead79455-d3bb-40bf-b2c9-ede2ae924cbd_5fb6d05d.jpeg', 14, true, true, false, true, 13),
  ('DIY Journaling Kit - Bullet Junk Journal - Scrapbook Supplies - Brown', 'Warm brown junk journal kit.', 199.00, null, 'books-stationery', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/dbd1bcb48_vjyyjytnzpekjbqovqst_supabase_co_02943ac5-d978-421c-a612-42fef7a8c1a9_88003a1b.jpeg', 19, true, false, true, true, 14),
  ('Aesthetic Planner Stickers Set- 8 Sheets', 'Eight sheets of aesthetic planner stickers.', 124.00, null, 'books-stationery', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/8352059e6_vjyyjytnzpekjbqovqst_supabase_co_facb184f-6a0b-4f2d-82c9-e2f0b516fa5d_25da40a1.jpeg', 50, true, false, true, true, 15),
  ('155 Piece Scrapbooking Supplies Kit Vintage Aesthetic Scrapbook Kit For DIY', '155 vintage-aesthetic scrapbooking pieces.', 199.00, null, 'books-stationery', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/5c163680f_vjyyjytnzpekjbqovqst_supabase_co_8ded82eb-c19c-4f90-ba47-957ef4308250_56222e1d.jpeg', 27, true, false, true, true, 16),
  ('DIY Journaling Kit - Bullet Junk Journal - Scrapbook Supplies - Purple', 'Everything you need to start a junk journal.', 199.00, null, 'books-stationery', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/bd6421afe_vjyyjytnzpekjbqovqst_supabase_co_577c5e9f-dcd5-40a9-b3d5-0dd77a51fe81_892d34fc.jpeg', 22, true, true, true, true, 17),
  ('Cute Mini Macaron Stationery Set', 'Adorable macaron-themed mini stationery set.', 186.00, null, 'books-stationery', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/e825270fc_vjyyjytnzpekjbqovqst_supabase_co_4b8dab87-04a6-42aa-b52f-c8a454f49f0a_fedc2fc8.jpeg', 35, true, true, true, true, 18),
  ('DIY Beads Kids Craft Set -24 Colours +Letter Beads,Elastic Cord & Scissors', '24 colours of beads with letter beads, elastic cord and scissors.', 178.00, null, 'books-stationery', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/73a7ca62b_vjyyjytnzpekjbqovqst_supabase_co_6a4a20db-5a0c-449f-9cfe-f589f5003151_3c658283.jpeg', 40, true, false, true, true, 19),
  ('Bouquet of Gifts - Tubbees Blueberry Sorbet Perfume Gift Set - Purple', 'Blueberry sorbet perfume gift set arranged as a bouquet.', 624.00, null, 'gifts', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/3b4a9d1c9_vjyyjytnzpekjbqovqst_supabase_co_2405b89d-08e4-4db7-b1c2-efaeaf04a18a_55a5fef4.jpeg', 6, true, false, false, true, 20),
  ('Bouquet of Gifts - Ruby Red', 'A bouquet of curated gifts in ruby red.', 450.00, null, 'gifts', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/25e4f5541_vjyyjytnzpekjbqovqst_supabase_co_18658576-7f35-4940-876b-9f6ea37d9660_6476f76e.jpeg', 9, true, true, true, true, 21),
  ('2 Pack - French Lavender Scented Candle - Purple', 'Two soft French lavender scented candles.', 374.00, null, 'home', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/4f55b0fc6_vjyyjytnzpekjbqovqst_supabase_co_bc4cc83c-86cd-47a0-a54c-a5b90ddf74c6_e6bde4a8.jpeg', 30, true, true, true, true, 22),
  ('Relaxation Spa Gift Set 8 Pcs for Women Includes Eye Mask Vacuum Cup Soap', 'Eight-piece relaxation set, beautifully presented and ready to gift.', 352.00, null, 'gifts', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/c7936c832_vjyyjytnzpekjbqovqst_supabase_co_053f5fac-ca00-447f-be1f-177df1c76782_644829bd.jpeg', 18, true, true, true, true, 23),
  ('7-Piece Facial Cleansing & Spa Gift Set - Perfect Beauty Self-Care Kit', 'A complete facial cleansing and spa kit for at-home self-care.', 331.00, null, 'beauty', 'https://media.base44.com/images/public/6ad9e0622e1cb646cfcf950f/7acab3f9c_vjyyjytnzpekjbqovqst_supabase_co_5fc033a0-8bb6-418e-9a3d-39104faeea5e_1c29e1a2.jpeg', 24, true, true, true, true, 24);
