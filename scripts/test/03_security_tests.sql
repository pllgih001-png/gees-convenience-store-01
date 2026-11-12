-- =============================================================================
-- SCRATCH-ONLY Stage 3 security test suite. NOT part of the deliverable schema.
-- Run: su postgres -c "psql -h /tmp/geespg -p 5433 -d gees_test -f scripts/test/03_security_tests.sql"
-- Covers spec §15 (A–G) and the DB-level parts of §24.6 (T1,T2,T4, forged-owner)
-- and §24.7 (G4,G6). Everything runs inside one transaction and is ROLLED BACK.
-- =============================================================================
\set ON_ERROR_STOP on
set client_min_messages to warning;

begin;

create temp table r (name text, result text, detail text) on commit drop;

-- Recorders run as the function owner (the migration/superuser) so they can
-- write the result table even while the session role is switched to anon/etc.
create function pg_temp.rec(n text, ok boolean, d text default '') returns void
language sql security definer as $$ insert into pg_temp.r values (n, case when ok then 'PASS' else 'FAIL' end, d); $$;

create function pg_temp.note(n text, res text, d text) returns void
language sql security definer as $$ insert into pg_temp.r values (n, res, d); $$;

-- Run a statement, return 'OK' or its SQLSTATE (so expected errors are consumed).
create function pg_temp.try(stmt text) returns text
language plpgsql as $$
begin
  execute stmt;
  return 'OK';
exception when others then
  return SQLSTATE;
end $$;

-- Switch execution role + verified JWT claims for the current transaction.
create function pg_temp.as_role(role text, claims text) returns void
language plpgsql as $$
begin
  perform set_config('role', role, true);
  perform set_config('request.jwt.claims', claims, true);
end $$;

create function pg_temp.as_super() returns void
language plpgsql as $$
begin
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- ---------------------------------------------------------------------------
-- Fixtures: three auth users (trigger provisions profiles).
-- C2 deliberately submits role=admin in user metadata (must be ignored).
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'c1@example.com',    '{"full_name":"C One"}'),
  ('22222222-2222-2222-2222-222222222222', 'c2@example.com',    '{"role":"admin","full_name":"C Two"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@example.com', '{"full_name":"Admin"}');

-- Promote A1 to admin through the service-role path (the ONLY permitted way).
do $$ begin
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  update public.profiles set role = 'admin' where id = '33333333-3333-3333-3333-333333333333';
  perform pg_temp.as_super();
end $$;

-- ===========================================================================
-- A. Schema integrity
-- ===========================================================================
select pg_temp.rec('A1 all_public_tables_have_rls',
  (select count(*) = 11 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity),
  'expect 11 tables, all with RLS enabled');

select pg_temp.rec('A2 enums_exact',
  (select enum_range(null::public.order_status)::text = '{pending_payment,paid,processing,shipped,delivered,cancelled}'
     and enum_range(null::public.payment_status)::text = '{unpaid,paid,failed}'
     and enum_range(null::public.reservation_status)::text = '{held,committed,released,expired}'
     and enum_range(null::public.email_log_status)::text = '{sent,failed,skipped}'),
  'order_status / payment_status / reservation_status / email_log_status');

select pg_temp.rec('A3 seed_counts',
  (select (select count(*) from public.categories) = 5
     and (select count(*) from public.box_themes) = 4
     and (select count(*) from public.products) = 25
     and (select count(*) from public.store_settings) = 1
     and (select count(*) from public.email_settings) = 8),
  'categories=5 box_themes=4 products=25 store_settings=1 email_settings=8');

select pg_temp.note('A4 no_base44_asset_urls', 'N/A (Stage 11)',
  (select count(*)::text || ' products still reference media.base44.com; asset migration is deferred to Stage 11' from public.products where image_url like '%media.base44.com%'));

-- ===========================================================================
-- B. Authorization / RLS negative tests
-- ===========================================================================
-- B1 anon cannot INSERT orders (privilege revoked; no policy).
do $$ begin
  perform pg_temp.as_role('anon', '{"role":"anon"}');
  perform pg_temp.rec('B1 anon_insert_orders_denied',
    pg_temp.try('insert into public.orders (order_reference) values (''hack'')') = '42501');
  perform pg_temp.as_super();
end $$;

-- B2 a customer cannot set payment_status on their own order (column UPDATE revoked).
do $$ declare oref text; begin
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  oref := (public.create_order(
    format('{"items":[{"product_id":"%s","quantity":1}],"customer_email":"c1@example.com"}',
      (select id from public.products where visible order by sort_order, name limit 1))::jsonb,
    'b2000000-0000-0000-0000-000000000001'::uuid, 'g:b2owner', null) ->> 'order_reference');
  perform pg_temp.as_role('authenticated',
    '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111","email":"c1@example.com"}');
  perform pg_temp.rec('B2 customer_set_paid_denied',
    pg_temp.try(format('update public.orders set payment_status = ''paid'' where order_reference = %L', oref)) = '42501');
  perform pg_temp.as_super();
end $$;

-- B3 a customer cannot UPDATE another customer's order (RLS filters → 0 rows).
do $$ declare n int; begin
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  perform public.create_order(
    format('{"items":[{"product_id":"%s","quantity":1}],"customer_email":"c2@example.com"}',
      (select id from public.products where visible order by sort_order, name limit 1))::jsonb,
    'b3000000-0000-0000-0000-000000000001'::uuid, 'g:b3owner', null);
  perform pg_temp.as_role('authenticated',
    '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111","email":"c1@example.com"}');
  update public.orders set customer_name = 'pwn' where customer_email = 'c2@example.com';
  get diagnostics n = row_count;
  perform pg_temp.rec('B3 customer_update_other_order_0rows', n = 0, 'rows affected=' || n);
  perform pg_temp.as_super();
end $$;

-- B4 a customer cannot SELECT another customer's order.
do $$ declare n int; begin
  perform pg_temp.as_role('authenticated',
    '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111","email":"c1@example.com"}');
  select count(*) into n from public.orders where customer_email = 'c2@example.com';
  perform pg_temp.rec('B4 customer_select_other_order_0rows', n = 0, 'rows=' || n);
  perform pg_temp.as_super();
end $$;

-- B5 a customer cannot self-promote.
do $$ begin
  perform pg_temp.as_role('authenticated',
    '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111"}');
  perform pg_temp.rec('B5 self_promote_denied',
    pg_temp.try('update public.profiles set role = ''admin'' where id = ''11111111-1111-1111-1111-111111111111''') = '42501');
  perform pg_temp.as_super();
end $$;

-- B6 role in user metadata is ignored at signup.
select pg_temp.rec('B6 signup_metadata_role_ignored',
  (select role = 'customer' from public.profiles where id = '22222222-2222-2222-2222-222222222222'),
  'C2 submitted {"role":"admin"} in metadata');

-- B7 a customer cannot INSERT/DELETE profiles.
do $$ begin
  perform pg_temp.as_role('authenticated', '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111"}');
  perform pg_temp.rec('B7a customer_insert_profile_denied',
    pg_temp.try('insert into public.profiles (id) values (''44444444-4444-4444-4444-444444444444'')') = '42501');
  perform pg_temp.rec('B7b customer_delete_profile_denied',
    pg_temp.try('delete from public.profiles where id = ''11111111-1111-1111-1111-111111111111''') = '42501');
  perform pg_temp.as_super();
end $$;

-- B8 anon/customer cannot read email_settings / email_logs / stock_reservations.
do $$ declare n int; begin
  perform pg_temp.as_role('anon', '{"role":"anon"}');
  perform pg_temp.rec('B8a anon_read_email_settings_denied',
    pg_temp.try('select 1 from public.email_settings') = '42501');
  perform pg_temp.as_role('authenticated', '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111"}');
  select count(*) into n from public.email_settings;
  perform pg_temp.rec('B8b customer_read_email_settings_0rows', n = 0, 'rows=' || n);
  select count(*) into n from public.stock_reservations;
  perform pg_temp.rec('B8c customer_read_stock_reservations_0rows', n = 0, 'rows=' || n);
  perform pg_temp.as_super();
end $$;

-- B9 anon/customer cannot INSERT/UPDATE stock_reservations.
do $$ begin
  perform pg_temp.as_role('authenticated', '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111"}');
  perform pg_temp.rec('B9a customer_insert_reservation_denied',
    pg_temp.try('insert into public.stock_reservations (order_id, product_id, quantity) select id, id, 1 from public.orders limit 1') = '42501');
  perform pg_temp.rec('B9b customer_update_reservation_denied',
    pg_temp.try('update public.stock_reservations set status = ''committed''') = '42501');
  perform pg_temp.as_super();
end $$;

-- B10 non-admin cannot execute reassign_products_category.
do $$ begin
  perform pg_temp.as_role('authenticated', '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111"}');
  perform pg_temp.rec('B10 non_admin_reassign_denied',
    pg_temp.try('select public.reassign_products_category(''jewellery'', ''jewellery'')') = '42501');
  perform pg_temp.as_super();
end $$;

-- ===========================================================================
-- C. SECURITY DEFINER hardening (catalogue-level)
-- ===========================================================================
select pg_temp.rec('C1 anon_execute_only_get_order_by_token',
  (not has_function_privilege('anon', 'public.create_order(jsonb,uuid,text,text)', 'EXECUTE')
   and has_function_privilege('anon', 'public.get_order_by_token(uuid)', 'EXECUTE')
   and not has_function_privilege('anon', 'public.settle_order(uuid,public.payment_status,text)', 'EXECUTE')),
  'anon: create_order=F get_order_by_token=T settle_order=F');

select pg_temp.rec('C2 no_public_execute_on_definer_fns',
  (select count(*) = 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef and p.proname in
      ('create_order','get_order_by_token','settle_order','release_expired_reservations',
       'reassign_products_category','is_admin','next_order_reference','handle_new_user',
       'prevent_role_escalation')
      and exists (select 1 from unnest(coalesce(p.proacl,'{}')) a where a::text like '=X/%')),
  'no "=X/" (PUBLIC execute) entry in proacl');

select pg_temp.rec('C3 search_path_pinned',
  (select count(*) = 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef and p.proname in
      ('create_order','get_order_by_token','settle_order','release_expired_reservations',
       'reassign_products_category','is_admin','next_order_reference','handle_new_user',
       'prevent_role_escalation')
      and not (coalesce(p.proconfig, '{}')::text like '%search_path=public, pg_temp%')),
  'every definer fn pins search_path=public, pg_temp');

select pg_temp.rec('C4 definer_fns_not_owned_by_client_roles',
  (select count(*) = 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    join pg_roles r on r.oid = p.proowner
    where n.nspname = 'public' and p.prosecdef and r.rolname in ('anon','authenticated','service_role')),
  'owner must be the migration role');

-- ===========================================================================
-- D. Order integrity
-- ===========================================================================
do $$ declare pid uuid; exp numeric; got numeric; res jsonb; ref text; begin
  select id, coalesce(sale_price, price) into pid, exp
    from public.products where visible order by sort_order, name limit 1;
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  -- Client sends a tampered price; the RPC must ignore it and use the DB price + R100.
  res := public.create_order(
    format('{"items":[{"product_id":"%s","quantity":2,"price":1}],"customer_email":"d1@example.com"}', pid)::jsonb,
    'd1000000-0000-0000-0000-000000000001'::uuid, 'g:d1', null);
  got := (res ->> 'total')::numeric;
  perform pg_temp.rec('D1 client_price_ignored', got = exp * 2 + 100, 'db_total=' || got || ' expected=' || (exp * 2 + 100));

  select total, delivery_fee into got, exp from public.orders where order_reference = res ->> 'order_reference';
  perform pg_temp.rec('D2 delivery_fee_is_100', exp = 100, 'fee=' || exp);

  perform pg_temp.rec('D4 new_order_pending_unpaid',
    (select status = 'pending_payment' and payment_status = 'unpaid' from public.orders where order_reference = res ->> 'order_reference'));
  perform pg_temp.as_super();
end $$;

-- D3 ownership: signed-in → user_id = auth.uid(); guest → NULL.
do $$ declare res jsonb; uid uuid; begin
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  res := public.create_order(
    format('{"items":[{"product_id":"%s","quantity":1}]}', (select id from public.products where visible limit 1))::jsonb,
    'd3000000-0000-0000-0000-000000000001'::uuid, 'g:d3guest', null);
  perform pg_temp.rec('D3a guest_order_user_id_null',
    (select user_id is null from public.orders where order_reference = res ->> 'order_reference'));

  perform pg_temp.as_role('authenticated',
    '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111","email":"c1@example.com"}');
  res := public.create_order(
    format('{"items":[{"product_id":"%s","quantity":1}]}', (select id from public.products where visible limit 1))::jsonb,
    'd3000000-0000-0000-0000-000000000002'::uuid, null, null);
  select user_id into uid from public.orders where order_reference = res ->> 'order_reference';
  perform pg_temp.rec('D3b signed_in_order_user_id_uid', uid = '11111111-1111-1111-1111-111111111111', 'user_id=' || uid);
  perform pg_temp.as_super();
end $$;

-- D5 duplicate order_reference rejected by UNIQUE.
select pg_temp.rec('D5 duplicate_reference_rejected',
  pg_temp.try(format('insert into public.orders (order_reference) values (%L)',
    (select order_reference from public.orders limit 1))) = '23505');

-- D6 same owner + same key → ONE order (true retry).
do $$ declare r1 jsonb; r2 jsonb; n int; begin
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  r1 := public.create_order(
    format('{"items":[{"product_id":"%s","quantity":1}],"customer_email":"d6@example.com"}', (select id from public.products where visible limit 1))::jsonb,
    'd6000000-0000-0000-0000-000000000001'::uuid, 'g:d6owner', null);
  r2 := public.create_order(
    format('{"items":[{"product_id":"%s","quantity":1}],"customer_email":"d6@example.com"}', (select id from public.products where visible limit 1))::jsonb,
    'd6000000-0000-0000-0000-000000000001'::uuid, 'g:d6owner', null);
  select count(*) into n from public.orders where idempotency_owner = 'g:d6owner';
  perform pg_temp.rec('D6 retry_returns_one_order',
    (r1 ->> 'order_reference') = (r2 ->> 'order_reference') and n = 1,
    'refs=' || (r1 ->> 'order_reference') || '/' || (r2 ->> 'order_reference') || ' rows=' || n);
  perform pg_temp.as_super();
end $$;

-- D6b same owner + same key + DIFFERENT payload → rejected.
do $$ begin
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  perform pg_temp.rec('D6b key_reuse_different_payload_rejected',
    pg_temp.try(format('select public.create_order(
      %L::jsonb, ''d6000000-0000-0000-0000-000000000001''::uuid, ''g:d6owner'', null)',
      format('{"items":[{"product_id":"%s","quantity":3}],"customer_email":"d6@example.com"}', (select id from public.products where visible limit 1))))
      = '23505');
  perform pg_temp.as_super();
end $$;

-- D7 Build-a-Box: only 5/10/15 accepted; price = individual unit price (no bundle price).
do $$ declare pid uuid; exp numeric; got numeric; res jsonb; begin
  select id, coalesce(sale_price, price) into pid, exp from public.products where box_eligible and visible order by sort_order limit 1;
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  perform pg_temp.rec('D7a box_invalid_pack_rejected',
    pg_temp.try(format('select public.create_order(''{"items":[{"product_id":"%s","quantity":7,"box":true}]}''::jsonb, ''d7000000-0000-0000-0000-000000000001''::uuid, ''g:d7'', null)', pid)) <> 'OK');
  res := public.create_order(
    format('{"items":[{"product_id":"%s","quantity":10,"box":true}]}', pid)::jsonb,
    'd7000000-0000-0000-0000-000000000002'::uuid, 'g:d7b', null);
  got := (res ->> 'total')::numeric;
  perform pg_temp.rec('D7b box_pack_individual_price', got = exp * 10 + 100, 'total=' || got || ' expected=' || (exp * 10 + 100));
  perform pg_temp.as_super();
end $$;

-- ===========================================================================
-- E. Guest retrieval (whitelist + non-enumerable)
-- ===========================================================================
do $$ declare res jsonb; tok uuid; o jsonb; begin
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  res := public.create_order(
    format('{"items":[{"product_id":"%s","quantity":1}],"customer_name":"Eve","address":"1 St"}', (select id from public.products where visible limit 1))::jsonb,
    'e1000000-0000-0000-0000-000000000001'::uuid, 'g:e1', null);
  perform pg_temp.as_super();

  perform pg_temp.as_role('anon', '{"role":"anon"}');
  o := public.get_order_by_token((res ->> 'public_token')::uuid);
  perform pg_temp.rec('E1 whitelist_only',
    (o ? 'order_reference' and o ? 'total' and not (o ? 'id') and not (o ? 'user_id')
     and not (o ? 'paid_at') and not (o ? 'gateway_ref') and not (o ? 'idempotency_owner')
     and not (o ? 'public_token')),
    'keys=' || (select string_agg(k, ',') from jsonb_object_keys(o) k));
  perform pg_temp.rec('E2 wrong_token_returns_nothing',
    public.get_order_by_token('00000000-0000-0000-0000-0000000000ff'::uuid) is null);
  perform pg_temp.as_super();
end $$;

-- ===========================================================================
-- F. Stock reservation
-- ===========================================================================
-- Reset reservation state + stock so the stock sub-tests start from a known
-- baseline (earlier sections legitimately left held reservations behind).
do $$ begin
  perform pg_temp.as_super();
  delete from public.stock_reservations;
  update public.products set stock = 50;
end $$;

-- F1 availability = stock - held: with stock 1 and one held unit, a second order fails.
do $$ declare pid uuid; begin
  select id into pid from public.products where visible order by sort_order, name offset 20 limit 1;
  perform pg_temp.as_super();
  update public.products set stock = 1 where id = pid;

  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  perform public.create_order(
    format('{"items":[{"product_id":"%s","quantity":1}]}', pid)::jsonb,
    'f1000000-0000-0000-0000-000000000001'::uuid, 'g:f1a', null);
  perform pg_temp.rec('F1 second_order_insufficient_stock',
    pg_temp.try(format('select public.create_order(''{"items":[{"product_id":"%s","quantity":1}]}''::jsonb, ''f1000000-0000-0000-0000-000000000002''::uuid, ''g:f1b'', null)', pid)) <> 'OK');
  perform pg_temp.as_super();
end $$;

-- F2 release_expired_reservations flips past-expiry held rows to expired.
do $$ declare res jsonb; o uuid; n int; begin
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  res := public.create_order(
    format('{"items":[{"product_id":"%s","quantity":1}]}', (select id from public.products where visible order by sort_order, name offset 21 limit 1))::jsonb,
    'f2000000-0000-0000-0000-000000000001'::uuid, 'g:f2', null);
  perform pg_temp.as_super();
  select id into o from public.orders where order_reference = res ->> 'order_reference';
  update public.stock_reservations set expires_at = now() - interval '1 minute' where order_id = o and status = 'held';

  perform pg_temp.as_role('authenticated', '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111"}');
  n := public.release_expired_reservations();
  perform pg_temp.as_super();
  perform pg_temp.rec('F2 expired_held_released',
    (select count(*) = 1 from public.stock_reservations where order_id = o and status = 'expired'),
    'released=' || n);
end $$;

-- F4 verified paid → reservations committed + products.stock decremented.
do $$ declare pid uuid; res jsonb; o uuid; before int; after int; begin
  perform pg_temp.as_super();
  select id into pid from public.products where visible order by sort_order, name offset 22 limit 1;
  update public.products set stock = 5 where id = pid;
  select stock into before from public.products where id = pid;

  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  res := public.create_order(
    format('{"items":[{"product_id":"%s","quantity":2}]}', pid)::jsonb,
    'f4000000-0000-0000-0000-000000000001'::uuid, 'g:f4', null);
  select id into o from public.orders where order_reference = res ->> 'order_reference';
  perform public.settle_order(o, 'paid', 'yoco-TESTREF');
  perform pg_temp.as_super();

  select stock into after from public.products where id = pid;
  perform pg_temp.rec('F4 paid_commits_and_decrements',
    (after = before - 2
     and (select count(*) = 1 from public.stock_reservations where order_id = o and status = 'committed')
     and (select payment_status = 'paid' and paid_at is not null and gateway_ref = 'yoco-TESTREF' from public.orders where id = o)),
    'stock ' || before || '->' || after);
end $$;

-- ===========================================================================
-- G. Payments
-- ===========================================================================
-- G2 a non-admin customer cannot settle an order (service-role / admin only).
do $$ declare res jsonb; begin
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  res := public.create_order(
    format('{"items":[{"product_id":"%s","quantity":1}]}', (select id from public.products where visible limit 1))::jsonb,
    'c2000000-0000-0000-0000-000000000001'::uuid, 'g:g2', null);
  perform pg_temp.as_role('authenticated', '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111"}');
  perform pg_temp.rec('G2 non_admin_settle_denied',
    pg_temp.try(format('select public.settle_order((select id from public.orders where order_reference = %L), ''paid'')', res ->> 'order_reference')) = '42501');
  perform pg_temp.as_super();
  perform pg_temp.rec('G2b order_still_unpaid',
    (select payment_status = 'unpaid' from public.orders where order_reference = res ->> 'order_reference'));
end $$;

-- G3 duplicate settle_order('paid') is a no-op.
do $$ declare pid uuid; res jsonb; o uuid; paid1 timestamptz; paid2 timestamptz; begin
  perform pg_temp.as_super();
  select id into pid from public.products where visible order by sort_order, name limit 1;
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  res := public.create_order(
    format('{"items":[{"product_id":"%s","quantity":1}]}', pid)::jsonb,
    'c3000000-0000-0000-0000-000000000001'::uuid, 'g:g3', null);
  select id into o from public.orders where order_reference = res ->> 'order_reference';
  perform public.settle_order(o, 'paid', 'ref-1');
  select paid_at into paid1 from public.orders where id = o;
  perform public.settle_order(o, 'paid', 'ref-1');
  select paid_at into paid2 from public.orders where id = o;
  perform pg_temp.as_super();
  perform pg_temp.rec('G3 duplicate_settle_noop', paid1 = paid2, 'paid_at unchanged=' || (paid1 = paid2));
end $$;

select pg_temp.note('G4 invalid_signature_event_ignored', 'N/A (Stage 3 scope)',
  'payment webhook verification route is explicitly out of Stage 3 scope (B1); cannot be executed');

-- ===========================================================================
-- §24.6 / §24.7 DB-level owner & grace behaviour
-- ===========================================================================
-- T1 two DIFFERENT owners, same email + identical basket → TWO distinct orders.
do $$ declare pid uuid; a jsonb; b jsonb; begin
  select id into pid from public.products where visible order by sort_order, name limit 1;
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  a := public.create_order(format('{"items":[{"product_id":"%s","quantity":1}],"customer_email":"t1@example.com"}', pid)::jsonb,
        'aa000000-0000-0000-0000-000000000001'::uuid, 'g:ownerA', null);
  b := public.create_order(format('{"items":[{"product_id":"%s","quantity":1}],"customer_email":"t1@example.com"}', pid)::jsonb,
        'bb000000-0000-0000-0000-000000000001'::uuid, 'g:ownerB', null);
  perform pg_temp.rec('T1 two_owners_two_orders',
    (a ->> 'order_reference') <> (b ->> 'order_reference')
    and (a ->> 'public_token') <> (b ->> 'public_token'),
    'refs=' || (a ->> 'order_reference') || '/' || (b ->> 'order_reference'));
  perform pg_temp.as_super();
end $$;

-- T2 same owner, same key, POSTed twice → ONE order, identical reference.
do $$ declare pid uuid; r1 jsonb; r2 jsonb; n int; begin
  select id into pid from public.products where visible order by sort_order, name limit 1;
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  r1 := public.create_order(format('{"items":[{"product_id":"%s","quantity":1}]}', pid)::jsonb,
        'a2000000-0000-0000-0000-000000000001'::uuid, 'g:t2', null);
  r2 := public.create_order(format('{"items":[{"product_id":"%s","quantity":1}]}', pid)::jsonb,
        'a2000000-0000-0000-0000-000000000001'::uuid, 'g:t2', null);
  select count(*) into n from public.orders where idempotency_owner = 'g:t2';
  perform pg_temp.rec('T2 same_owner_retry_one_order',
    (r1 ->> 'order_reference') = (r2 ->> 'order_reference') and n = 1, 'rows=' || n);
  perform pg_temp.as_super();
end $$;

-- T4 owner B replays owner A's key → B gets B's OWN order (never A's).
do $$ declare pid uuid; a jsonb; b jsonb; begin
  select id into pid from public.products where visible order by sort_order, name limit 1;
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  a := public.create_order(format('{"items":[{"product_id":"%s","quantity":1}]}', pid)::jsonb,
        'a4000000-0000-0000-0000-000000000001'::uuid, 'g:A', null);
  b := public.create_order(format('{"items":[{"product_id":"%s","quantity":1}]}', pid)::jsonb,
        'a4000000-0000-0000-0000-000000000001'::uuid, 'g:B', null);   -- same key, different owner
  perform pg_temp.rec('T4 cross_owner_replay_isolated',
    (a ->> 'order_reference') <> (b ->> 'order_reference')
    and (a ->> 'public_token') <> (b ->> 'public_token'),
    'A=' || (a ->> 'order_reference') || ' B=' || (b ->> 'order_reference'));
  perform pg_temp.as_super();
end $$;

-- G4 post-invalidation retry: same key under NEW owner + grace(prev owner) → resolves to ORIGINAL.
do $$ declare pid uuid; orig jsonb; retry jsonb; n int; begin
  select id into pid from public.products where visible order by sort_order, name limit 1;
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  orig := public.create_order(format('{"items":[{"product_id":"%s","quantity":1}]}', pid)::jsonb,
        'c4000000-0000-0000-0000-000000000001'::uuid, 'g:before', null);
  -- new owner 'g:after' with key; grace supplies prev owner 'g:before' → should return orig.
  retry := public.create_order(format('{"items":[{"product_id":"%s","quantity":1}]}', pid)::jsonb,
        'c4000000-0000-0000-0000-000000000001'::uuid, 'g:after', 'g:before');
  select count(*) into n from public.orders where idempotency_owner in ('g:before','g:after');
  perform pg_temp.rec('G4 grace_resolves_to_original',
    (retry ->> 'order_reference') = (orig ->> 'order_reference') and n = 1,
    'orig=' || (orig ->> 'order_reference') || ' retry=' || (retry ->> 'order_reference') || ' rows=' || n);
  perform pg_temp.as_super();
end $$;

-- G4b grace owner does NOT hijack a NEW key → new order.
do $$ declare pid uuid; r jsonb; begin
  select id into pid from public.products where visible order by sort_order, name limit 1;
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  r := public.create_order(format('{"items":[{"product_id":"%s","quantity":1}]}', pid)::jsonb,
        'c4000000-0000-0000-0000-0000000000ff'::uuid, 'g:after', 'g:before');
  perform pg_temp.rec('G4b grace_new_key_new_order', (r ->> 'idempotent')::boolean = false);
  perform pg_temp.as_super();
end $$;

-- G6 grace cookie is create-only: it grants no read access (token check still required).
do $$ declare pid uuid; orig jsonb; begin
  select id into pid from public.products where visible order by sort_order, name limit 1;
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  orig := public.create_order(format('{"items":[{"product_id":"%s","quantity":1}]}', pid)::jsonb,
        'c6000000-0000-0000-0000-000000000001'::uuid, 'g:before', null);
  perform pg_temp.rec('G6 grace_no_read_access',
    public.get_order_by_token('00000000-0000-0000-0000-0000000000aa'::uuid) is null);
  perform pg_temp.as_super();
end $$;

-- Forged guest owner: anon calling create_order → refused (nothing inserted).
do $$ begin
  perform pg_temp.as_role('anon', '{"role":"anon"}');
  perform pg_temp.rec('T5 forged_owner_refused',
    pg_temp.try(format('select public.create_order(''{"items":[]}''::jsonb, null, ''g:forge'', null)')) = '42501');
  perform pg_temp.as_super();
end $$;

-- Service-role path stores the SERVER-derived owner hash, never a client value.
do $$ declare pid uuid; r jsonb; owner text; begin
  select id into pid from public.products where visible order by sort_order, name limit 1;
  perform pg_temp.as_role('service_role', '{"role":"service_role"}');
  r := public.create_order(format('{"items":[{"product_id":"%s","quantity":1}]}', pid)::jsonb,
        '5e000000-0000-0000-0000-000000000001'::uuid, 'g:hashcheck', null);
  select idempotency_owner into owner from public.orders where order_reference = r ->> 'order_reference';
  perform pg_temp.rec('T5 service_role_owner_is_server_value', owner = 'g:hashcheck', 'owner=' || owner);
  perform pg_temp.as_super();
end $$;

-- ===========================================================================
-- Summary
-- ===========================================================================
select result, count(*) from r group by result order by result;
\echo
select name, result, coalesce(detail,'') from r where result <> 'PASS' order by name;
\echo
select count(*) filter (where result = 'PASS') as passed,
       count(*) filter (where result = 'FAIL') as failed,
       count(*) filter (where result not in ('PASS','FAIL')) as not_run
from r;

rollback;
