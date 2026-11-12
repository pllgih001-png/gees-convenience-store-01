-- ROLLBACK for migration 0000 (extensions + helpers)
-- Preconditions: no dependent objects (run after 0002+ have been rolled back).
-- Restores: removes public.set_updated_at(). Keeps pgcrypto.
-- (public.is_admin() is dropped by rollback/0002.)
drop function if exists public.set_updated_at();
