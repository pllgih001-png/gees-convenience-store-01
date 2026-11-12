-- ROLLBACK for migration 0012 (email_settings seed)
delete from public.email_settings
 where subject = '' and html = ''
   and type in ('order_confirmation','payment_confirmation','status_received',
                'status_processing','status_dispatched','status_delivered',
                'status_cancelled','welcome');
