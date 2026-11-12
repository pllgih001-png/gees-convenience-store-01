-- =============================================================================
-- GEES Convenience Store — Stage 3 migration 0006
-- orders + order_reference_seq + next_order_reference() + stock_reservations
--   + payment_events + RLS
-- Rollback: supabase/rollback/0006_orders.sql
-- Depends on: 0001 (enums), 0002 (profiles), 0005 (products)
--
-- NOTE: order_reference_seq is created but NOT seeded (decision B2). Checkout stays
--       disabled until verified references / backend source are available (§9).
-- =============================================================================

create sequence public.order_reference_seq;

-- Observed format: 'gees' || <n>  (e.g. gees1006 -> gees1007 -> gees1008).
create or replace function public.next_order_reference()
returns text
language sql
volatile
security definer
set search_path = public, pg_temp
as $$
  select 'gees' || nextval('public.order_reference_seq')::text;
$$;
revoke all on function public.next_order_reference() from public;
-- No client grant: only invoked from inside the SECURITY DEFINER create_order().

create table public.orders (
  id                       uuid primary key default gen_random_uuid(),
  order_reference          text not null unique,
  public_token             uuid not null unique default gen_random_uuid(),
  idempotency_key          uuid null,
  idempotency_payload_hash text null,
  idempotency_owner        text null,
  user_id                  uuid null references auth.users(id) on delete set null,
  customer_name            text not null default '',
  customer_email           text not null default '',
  phone                    text not null default '',
  address                  text not null default '',
  city                     text not null default '',
  province                 text not null default '',
  postal_code              text not null default '',
  gift_note                text not null default '',
  items                    jsonb not null default '[]'::jsonb,
  subtotal                 numeric(10,2) not null default 0,
  delivery_fee             numeric(10,2) not null default 0,
  total                    numeric(10,2) not null default 0,
  status                   public.order_status   not null default 'pending_payment',
  payment_status           public.payment_status not null default 'unpaid',
  paid_at                  timestamptz null,
  gateway_ref              text null,
  stock_conflict           boolean not null default false,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create trigger orders_set_updated_at
  before update on public.orders
  for each row execute function public.set_updated_at();

-- Idempotency is scoped to (owner, key); enforced only when both are present.
create unique index orders_idempotency_owner_key_idx
  on public.orders (idempotency_owner, idempotency_key)
  where idempotency_key is not null and idempotency_owner is not null;

create index orders_customer_email_idx on public.orders (customer_email);
create index orders_created_at_idx on public.orders (created_at desc);

-- ---------------------------------------------------------------------------
-- stock_reservations — atomic holds so concurrent checkouts cannot oversell.
-- ---------------------------------------------------------------------------
create table public.stock_reservations (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity   int not null check (quantity > 0),
  status     public.reservation_status not null default 'held',
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  created_at timestamptz not null default now()
);

create index stock_reservations_product_idx on public.stock_reservations (product_id);
create index stock_reservations_status_expires_idx on public.stock_reservations (status, expires_at);
create index stock_reservations_order_idx on public.stock_reservations (order_id);

-- ---------------------------------------------------------------------------
-- payment_events — idempotency + audit for gateway notifications (server-only).
-- ---------------------------------------------------------------------------
create table public.payment_events (
  id              uuid primary key default gen_random_uuid(),
  provider        text not null default 'yoco',
  event_id        text not null unique,
  order_id        uuid null references public.orders(id) on delete set null,
  outcome         text not null check (outcome in ('paid', 'failed', 'ignored')),
  signature_valid boolean not null default false,
  payload_hash    text not null,
  received_at     timestamptz not null default now()
);

create index payment_events_order_idx on public.payment_events (order_id);

-- ---------------------------------------------------------------------------
-- RLS: default deny. Orders are READ-ONLY to clients (created only via create_order).
-- ---------------------------------------------------------------------------
alter table public.orders             enable row level security;
alter table public.stock_reservations enable row level security;
alter table public.payment_events     enable row level security;

create policy orders_select_own_or_admin on public.orders
  for select to authenticated
  using (
    user_id = auth.uid()
    or (auth.jwt() ->> 'email') is not null and customer_email = (auth.jwt() ->> 'email')
    or public.is_admin()
  );
create policy orders_update_admin on public.orders
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy orders_delete_admin on public.orders
  for delete to authenticated using (public.is_admin());

create policy stock_reservations_select_admin on public.stock_reservations
  for select to authenticated using (public.is_admin());
create policy stock_reservations_delete_admin on public.stock_reservations
  for delete to authenticated using (public.is_admin());

create policy payment_events_select_admin on public.payment_events
  for select to authenticated using (public.is_admin());
create policy payment_events_delete_admin on public.payment_events
  for delete to authenticated using (public.is_admin());

-- Grants: reads only; writes happen through SECURITY DEFINER functions / service role.
grant select on public.orders, public.stock_reservations, public.payment_events to authenticated;
grant delete on public.orders, public.stock_reservations, public.payment_events to authenticated;

-- Explicit revokes: clients can never INSERT orders/reservations/events.
revoke insert on public.orders, public.stock_reservations, public.payment_events from anon, authenticated;
-- Clients can never UPDATE reservations/events directly.
revoke update on public.stock_reservations, public.payment_events from anon, authenticated;
-- Clients (including an admin's *client* session) can never rewrite the fields that
-- define ownership, payment state or money. Admin status transitions are performed
-- server-side through SECURITY DEFINER RPCs (e.g. settle_order) / the service role,
-- never by a direct client UPDATE. This matches "customers must never be able to
-- manipulate payment status or order ownership" (requirement 3).
--
-- NB: a bare `revoke update (<col>)` is a NO-OP while a table-wide UPDATE grant
-- exists, because the table-level ACL entry still covers every column (verified:
-- such a revoke leaves pg_attribute.attacl empty). So we first drop the table-wide
-- UPDATE, then grant UPDATE only on the safe, admin-editable columns. Every other
-- column (payment state, ownership, money, identifiers) is therefore not updatable
-- by clients — the restriction holds even if an RLS policy is later misconfigured.
revoke update on public.orders from anon, authenticated;
grant update (customer_name, customer_email, phone, address, city, province,
              postal_code, gift_note)
  on public.orders to authenticated;
