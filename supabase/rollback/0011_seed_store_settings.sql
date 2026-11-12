-- ROLLBACK for migration 0011 (store_settings seed)
delete from public.store_settings where id = 1;
