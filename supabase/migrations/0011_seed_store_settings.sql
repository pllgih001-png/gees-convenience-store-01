-- =============================================================================
-- GEES Convenience Store — Stage 3 migration 0011
-- Seed: store_settings singleton (id = 1)
-- Rollback: supabase/rollback/0011_seed_store_settings.sql
--
-- Only values we can state without inventing copy are set; the remaining text
-- columns keep the column defaults (empty) and will be populated from the
-- reference / owner in the content stage. delivery_fee = R100 (decision: no
-- free-delivery threshold). Social links stay NULL so they render hidden.
-- =============================================================================

insert into public.store_settings
  (id, delivery_fee, store_name, payment_link, social_instagram, social_facebook, social_tiktok)
values
  (1, 100, 'GEES Convenience Store', 'https://pay.yoco.com/gees-convenience-store', null, null, null)
on conflict (id) do nothing;
