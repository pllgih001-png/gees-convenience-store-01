-- ROLLBACK for migration 0002 (profiles + triggers + is_admin)
-- Preconditions: orders.user_id FK must be dropped first (roll back 0006).
-- NOTE: public.is_admin() is referenced by policies on many tables. Those tables
--       (0003-0008) are rolled back before this file, so by now the only remaining
--       dependent is public.profiles itself — so the table (and its policies) MUST
--       be dropped BEFORE the function, otherwise the drop fails with
--       "cannot drop function is_admin() because other objects depend on it".
drop trigger if exists on_auth_user_created on auth.users;
drop table if exists public.profiles cascade;
drop function if exists public.prevent_role_escalation();
drop function if exists public.handle_new_user();
drop function if exists public.is_admin();
