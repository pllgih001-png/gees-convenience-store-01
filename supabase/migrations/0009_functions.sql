-- =============================================================================
-- GEES Convenience Store — Stage 3 migration 0009
-- Functions: create_order, get_order_by_token, settle_order,
--            release_expired_reservations, reassign_products_category
-- Rollback: supabase/rollback/0009_functions.sql
-- Depends on: 0000-0008
-- Hardening: each function is SECURITY DEFINER, pins search_path, is
--            schema-qualified, revokes PUBLIC execute and grants least privilege.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- release_expired_reservations — idempotent; returns units released.
-- ---------------------------------------------------------------------------
create or replace function public.release_expired_reservations()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_count integer;
begin
  update public.stock_reservations
     set status = 'expired'
   where status = 'held' and expires_at < now();
  get diagnostics v_count = row_count;
  return v_count;
end
$$;
revoke all on function public.release_expired_reservations() from public;
grant execute on function public.release_expired_reservations() to authenticated;

-- ---------------------------------------------------------------------------
-- create_order — the ONLY way an order is created. Identity, prices, fee, totals
-- and payment state are all derived server-side.
-- ---------------------------------------------------------------------------
create or replace function public.create_order(
  payload jsonb,
  p_idempotency_key uuid,
  p_guest_owner text default null,
  p_guest_owner_prev text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_owner        text;
  v_owner_prev   text;
  v_user_id      uuid;
  v_role         text;
  v_fee          numeric(10,2);
  v_subtotal     numeric(10,2) := 0;
  v_items        jsonb;
  v_hash         text;
  v_existing     public.orders%rowtype;
  v_item         jsonb;
  v_pid          uuid;
  v_qty          int;
  v_price        numeric(10,2);
  v_avail        int;
  v_held         int;
  v_agg          int;
  v_order_id     uuid;
  v_ref          text;
  v_token        uuid;
  v_total        numeric(10,2);
begin
  -- ── Identity (never trusted from the browser) ────────────────────────────
  v_role := coalesce(auth.jwt() ->> 'role', 'anon');
  if auth.uid() is not null then
    v_user_id := auth.uid();
    v_owner   := 'u:' || v_user_id::text;
  elsif v_role = 'service_role' then
    if p_guest_owner is null or p_guest_owner = '' then
      raise exception 'missing_guest_owner' using errcode = '22023';
    end if;
    v_owner      := p_guest_owner;
    v_owner_prev := p_guest_owner_prev;
  else
    raise exception 'guest_checkout_requires_server' using errcode = '42501';
  end if;

  -- ── Opportunistic cleanup of expired holds ───────────────────────────────
  perform public.release_expired_reservations();

  -- ── Payload shape / size guards ──────────────────────────────────────────
  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'invalid_payload' using errcode = '22023';
  end if;
  if pg_column_size(payload) > 65536 then
    raise exception 'payload_too_large' using errcode = '22001';
  end if;
  v_items := payload -> 'items';
  if v_items is null or jsonb_typeof(v_items) <> 'array'
     or jsonb_array_length(v_items) = 0 or jsonb_array_length(v_items) > 20 then
    raise exception 'invalid_items' using errcode = '22023';
  end if;

  -- ── Customer field length guards ─────────────────────────────────────────
  if length(coalesce(payload->>'customer_email','')) > 254
     or length(coalesce(payload->>'customer_name','')) > 200
     or length(coalesce(payload->>'address','')) > 500 then
    raise exception 'field_too_long' using errcode = '22001';
  end if;

  -- ── Idempotency: scoped to (owner, key); same owner+key+payload → same order ──
  v_hash := encode(digest(v_items::text || coalesce(payload->>'customer_email',''), 'sha256'), 'hex');
  if p_idempotency_key is not null then
    select * into v_existing from public.orders o
     where o.idempotency_key = p_idempotency_key
       and o.idempotency_owner in (v_owner, coalesce(v_owner_prev, v_owner))
     limit 1;
    if found then
      if v_existing.idempotency_payload_hash is distinct from v_hash then
        raise exception 'idempotency_key_reused' using errcode = '23505';
      end if;
      return jsonb_build_object(
        'order_reference', v_existing.order_reference,
        'public_token',    v_existing.public_token,
        'total',           v_existing.total,
        'idempotent',      true
      );
    end if;
  end if;

  -- ── Delivery fee: server-side only (R100 default), no free-delivery branch ──
  select s.delivery_fee into v_fee from public.store_settings s where s.id = 1;
  v_fee := coalesce(v_fee, 100);

  -- ── Lock product rows in a deterministic order (prevents deadlock/oversell) ──
  for v_pid in
    select distinct (e.value ->> 'product_id')::uuid
      from jsonb_array_elements(v_items) e
     order by 1
  loop
    perform 1 from public.products p where p.id = v_pid for update;
  end loop;

  -- ── Validate each line, recompute prices from the DB ─────────────────────
  for v_item in select value from jsonb_array_elements(v_items) loop
    v_pid := (v_item ->> 'product_id')::uuid;
    v_qty := coalesce((v_item ->> 'quantity')::int, 0);

    if v_qty < 1 or v_qty > 99 then
      raise exception 'invalid_quantity' using errcode = '22023';
    end if;
    if coalesce((v_item ->> 'box')::boolean, false) and v_qty not in (5, 10, 15) then
      raise exception 'invalid_box_pack' using errcode = '22023';
    end if;

    select coalesce(p.sale_price, p.price) into v_price
      from public.products p
     where p.id = v_pid and p.visible and (not coalesce((v_item ->> 'box')::boolean, false) or p.box_eligible);
    if not found then
      raise exception 'product_unavailable' using errcode = '22023';
    end if;

    v_subtotal := v_subtotal + (v_price * v_qty);
  end loop;

  v_total := v_subtotal + v_fee;

  -- ── Availability check, AGGREGATED PER PRODUCT (A4-1) ────────────────────
  -- The same product may legitimately appear on several lines (Build-a-Box and
  -- the cart both allow repeats). Availability MUST be validated against the
  -- TOTAL quantity per product, not line-by-line: two lines of 3 units each
  -- would otherwise both pass a per-line check against the same `held` snapshot
  -- and together over-reserve a product whose stock is 5. Aggregating first
  -- makes the check exact and conservative — sum(qty per product) must fit in
  -- stock − held(committed elsewhere). Rows are already locked above, so no
  -- concurrent writer can change `stock` between this check and the inserts.
  for v_pid, v_agg in
    select (e.value ->> 'product_id')::uuid,
           sum((e.value ->> 'quantity')::int)::int
      from jsonb_array_elements(v_items) e
     group by 1
     order by 1
  loop
    select coalesce(sum(r.quantity), 0) into v_held
      from public.stock_reservations r
     where r.product_id = v_pid and r.status = 'held' and r.expires_at > now();

    select p.stock into v_avail from public.products p where p.id = v_pid;
    if v_avail - v_held < v_agg then
      raise exception 'insufficient_stock' using errcode = 'P0001';
    end if;
  end loop;

  -- ── Insert the order with forced literals; ownership from the server ──────
  insert into public.orders (
    order_reference, idempotency_key, idempotency_payload_hash, idempotency_owner,
    user_id, customer_name, customer_email, phone, address, city, province,
    postal_code, gift_note, items, subtotal, delivery_fee, total,
    status, payment_status
  ) values (
    public.next_order_reference(), p_idempotency_key, v_hash, v_owner,
    v_user_id,
    coalesce(payload->>'customer_name',''), coalesce(payload->>'customer_email',''),
    coalesce(payload->>'phone',''), coalesce(payload->>'address',''),
    coalesce(payload->>'city',''), coalesce(payload->>'province',''),
    coalesce(payload->>'postal_code',''), coalesce(payload->>'gift_note',''),
    v_items, v_subtotal, v_fee, v_total,
    'pending_payment', 'unpaid'
  )
  on conflict (idempotency_owner, idempotency_key)
    where idempotency_key is not null and idempotency_owner is not null
    do nothing
  returning id, order_reference, public_token, total into v_order_id, v_ref, v_token, v_total;

  if v_order_id is null then
    -- Lost the race: return the winner (same owner, same key).
    select * into v_existing from public.orders o
     where o.idempotency_key = p_idempotency_key
       and o.idempotency_owner in (v_owner, coalesce(v_owner_prev, v_owner))
     limit 1;
    return jsonb_build_object(
      'order_reference', v_existing.order_reference,
      'public_token',    v_existing.public_token,
      'total',           v_existing.total,
      'idempotent',      true
    );
  end if;

  -- ── Hold stock atomically for each line ──────────────────────────────────
  for v_item in select value from jsonb_array_elements(v_items) loop
    insert into public.stock_reservations (order_id, product_id, quantity)
    values (v_order_id, (v_item ->> 'product_id')::uuid, (v_item ->> 'quantity')::int);
  end loop;

  return jsonb_build_object(
    'order_reference', v_ref,
    'public_token',    v_token,
    'total',           v_total,
    'idempotent',      false
  );
end
$$;
revoke all on function public.create_order(jsonb, uuid, text, text) from public;
-- Never granted to anon: guest checkout goes through the server route (service_role).
grant execute on function public.create_order(jsonb, uuid, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- get_order_by_token — guest retrieval by unguessable token, whitelisted fields.
-- ---------------------------------------------------------------------------
create or replace function public.get_order_by_token(p_token uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
           'order_reference', o.order_reference,
           'customer_name',   o.customer_name,
           'items',           o.items,
           'subtotal',        o.subtotal,
           'delivery_fee',    o.delivery_fee,
           'total',           o.total,
           'status',          o.status,
           'payment_status',  o.payment_status,
           'created_at',      o.created_at
         )
  from public.orders o
  where o.public_token = p_token;
$$;
revoke all on function public.get_order_by_token(uuid) from public;
grant execute on function public.get_order_by_token(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- settle_order — server-verified payment outcome only. Idempotent.
-- ---------------------------------------------------------------------------
create or replace function public.settle_order(
  p_order_id uuid,
  p_outcome public.payment_status,
  p_gateway_ref text default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_stock int; v_qty int; v_rec record;
begin
  if not (public.is_admin() or coalesce(auth.jwt() ->> 'role','anon') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if p_outcome = 'paid' then
    -- Commit only an order that is still unpaid (idempotent otherwise).
    update public.orders
       set payment_status = 'paid', status = 'paid', paid_at = now(),
           gateway_ref = coalesce(p_gateway_ref, gateway_ref)
     where id = p_order_id and payment_status = 'unpaid';
    if not found then return; end if;

    for v_rec in
      select product_id, quantity from public.stock_reservations
       where order_id = p_order_id and status = 'held' for update
    loop
      select stock into v_stock from public.products where id = v_rec.product_id for update;
      if v_stock < v_rec.quantity then
        update public.orders set stock_conflict = true where id = p_order_id;
      else
        update public.products set stock = stock - v_rec.quantity where id = v_rec.product_id;
      end if;
      update public.stock_reservations set status = 'committed'
       where order_id = p_order_id and product_id = v_rec.product_id and status = 'held';
    end loop;

  elsif p_outcome = 'failed' then
    update public.orders set payment_status = 'failed'
     where id = p_order_id and payment_status = 'unpaid';
    if not found then return; end if;
    update public.stock_reservations set status = 'released'
     where order_id = p_order_id and status = 'held';
  end if;
end
$$;
revoke all on function public.settle_order(uuid, public.payment_status, text) from public;
-- A2-2: settlement is a SERVER-ONLY operation. The server verifies the gateway
-- outcome and calls settle_order with the service-role key (§18, §20). It is NOT
-- granted to `authenticated` (or `anon`): a signed-in customer/admin never settles
-- directly from the browser — the payment boundary is the service-role route.
grant execute on function public.settle_order(uuid, public.payment_status, text) to service_role;

-- ---------------------------------------------------------------------------
-- reassign_products_category — admin-only; used before deleting a category.
-- ---------------------------------------------------------------------------
create or replace function public.reassign_products_category(p_old text, p_new text)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update public.products set category_slug = p_new where category_slug = p_old;
  insert into public.box_theme_categories (box_theme_id, category_slug)
    select bt.box_theme_id, p_new from public.box_theme_categories bt
     where bt.category_slug = p_old
    on conflict do nothing;
  delete from public.box_theme_categories where category_slug = p_old;
  return (select count(*)::int from public.products where category_slug = p_new);
end
$$;
revoke all on function public.reassign_products_category(text, text) from public;
grant execute on function public.reassign_products_category(text, text) to authenticated;
