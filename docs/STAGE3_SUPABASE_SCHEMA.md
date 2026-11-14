# Stage 3 — Supabase schema, RLS & migration plan (FINAL v8 — GRACE-COOKIE REVIEW, FOR APPROVAL)

Status: **proposed — not applied.** No database objects created. No credentials used or committed. Base44 site untouched.
Supersedes v1–v7. Awaiting **separate explicit approval** before implementation.
v7 fixed CSRF delivery and removed owner-independent dedupe; v8 reviews the grace-cookie design (§24.7), corrects the idempotency resolution order across invalidation, and states clearly that **no test has been executed** (all tests are specified only).

---

## 0f. What changed in v8 (grace-cookie review)

| # | Your verification | v8 response |
|---|---|---|
| 1 | Signed, time-limited, validated server-side | ✅ Same HMAC + `exp`-in-payload format; timing-safe compare + `iat ≤ now < exp` on every use (§24.7). |
| 2 | Preserves only the idempotency owner; no order access | ✅ Content is a prior `sid` only; consulted **only** in the checkout-create idempotency lookup; never on any read path (§24.7). |
| 3 | Cannot be used by another guest to impersonate | ✅ HttpOnly + signed; only the original browser holds it; single-purpose scope grants no read/admin access (§24.7). |
| 4 | Not replayable beyond expiry | ✅ `exp` inside the signed bytes; expired/tampered cookies rejected (§24.7). |
| 5 | Does not bypass CSRF/Origin/method checks | ✅ Those checks run identically and **before** grace evaluation; grace never applies to GET (§24.7). |
| 6 | No duplicate orders / no cross-exposure | ✅ **Corrected resolution order**: after invalidation the browser has the new `sid`, so the lookup must check the key under the current owner **and** the grace (previous) owner — v7's "current → else grace" ordering would have missed the original order (§24.4 pt 2). |
| — | Executed vs specified tests | ✅ §24.7 states plainly: **nothing has been executed**; all §15/§24.6 tests are specified only. |

---

## 0e. What changed in v7 (mapped to your two issues)

| # | Your issue | v7 response |
|---|---|---|
| 1 | CSRF token delivery vs an HttpOnly cookie | ✅ The `gees_guest` identity cookie **stays HttpOnly**. The CSRF token is **derived server-side from the session and rendered into the form** — no cookie needs to be JS-readable, so nothing is exposed (§24.2). |
| 2 | Owner-independent dedupe (`email + payload_hash + 60s`) | ✅ **Removed.** Identity is `(idempotency_owner, idempotency_key)` only. The owner is **preserved across renewal** (same `sid`) and across controlled invalidation (grace window), so a genuine retry returns the original order — and two distinct sessions with identical details create **two** orders (§24.4). |

---

## 0d. What changed in v6 (mapped to your four points)

| # | Your requirement | v6 response |
|---|---|---|
| 1 | HMAC expiry protection | ✅ The signed payload now carries `exp`; the server verifies signature **and** expiry, so an old cookie cannot be replayed (§24.1). |
| 2 | CSRF beyond `SameSite=Lax` | ✅ Route Handler enforces **Origin/`Sec-Fetch-Site` validation + a server-derived CSRF token (rendered into the form) + POST-only**; the identity cookie stays HttpOnly (§24.2). |
| 3 | `auth.role()` deprecation | ✅ Replaced with the current recommended claim check `(auth.jwt() ->> 'role')` (with the underlying `request.jwt.claims` noted) (§24.3). |
| 4 | Rotation-safe idempotency | ✅ **Renewal** (same `sid`, extended `exp`) vs **invalidation** (new `sid`); a new `sid` is never issued mid-checkout, and a signed **grace cookie** preserves the same owner so a retry resolves to the original order — no email/payload fallback (§24.4). |
| 5 | Revised SQL signature, grants, flow, tests | ✅ §6.1, §6.3, §24.5, §15/§24.6. |

---

## 0c. What changed in v5 (mapped to your corrections & decisions)

| # | Your instruction | v5 response |
|---|---|---|
| 1 | Scope idempotency keys to the customer/guest session | ✅ `idempotency_key` is bound to the caller and re-checked against session/email (§17.1). |
| 2 | Reject reuse of an existing key with a different payload | ✅ `payload_hash` stored; same key + different payload → rejected (§17.1). |
| 3 | Duplicates must not expose another customer's order or guest token | ✅ On conflict, the existing order is returned **only** if the same caller owns it (§17.1). |
| 4 | Retrieving an existing order requires authorisation | ✅ Conflict-return and `get_order_by_token` both require the matching caller/token (§17.1, §7). |
| 5 | Per-IP rate limiting uses a trusted server-derived IP | ✅ IP taken from the trusted proxy header server-side only; never from client input (§17.1). |
| 6 | Record decisions B1–B4, N1–N7 | ✅ Recorded verbatim as DECIDED (§16). |
| 7 | Final implementation checklist | ✅ Added (§23). |

---

## 0b. What changed in v4 (mapped to your final review)

| # | Your request | v4 response |
|---|---|---|
| 1 | Public checkout protection | ✅ Full input-validation table + idempotency key + rate limiting + size caps (§17). |
| 2 | Yoco verification | ✅ Trusted verification route, signature/idempotency handling, duplicate-notification dedupe, and the exact stock-commit point documented — incl. a **limitation of the static payment link** (§18). |
| 3 | Stock lifecycle | ✅ Cancellation, expiry, repeated expiry jobs, late-payment-after-release and concurrency all specified (§19). |
| 4 | Privileged access review | ✅ Every definer fn / trigger / grant / table audited for bypass paths (§20). |
| 5 | Guest retrieval & reservation isolation | ✅ Field whitelist confirmed; reservation table has no client grants + RLS deny (§20). |
| 6 | Final migration order + rollback deps + test procedure | ✅ Dependency-ordered migrations, reverse-order rollbacks, step-by-step test procedure (§21). |

---

## 0a. What changed in v3 (mapped to your final checks)

| # | Your requirement | v3 response |
|---|---|---|
| 1 | `SECURITY DEFINER` hardening | ✅ Explicit `REVOKE ALL … FROM PUBLIC`, grants only to intended roles, pinned `search_path`, schema-qualified references (§6.3, §12.1). |
| 2 | Guest retrieval returns only customer-facing data | ✅ `get_order_by_token()` now builds an explicit **field whitelist** (no `id`, no `user_id`, no admin notes, no payment internals) (§7). |
| 3 | Transactional stock reservation | ✅ New `stock_reservations` table + atomic reservation inside `create_order()`, with `expires_at` and `release_expired_reservations()` (§6.2). |
| 4 | Preserve Build-a-Box rules | ✅ 5/10/15 packs, individual prices, eligibility rules and existing theme/category links preserved verbatim (§6.1, §9). |
| 5 | Preserve R100 delivery; no free-delivery threshold | ✅ Fee read from `store_settings` (default **R100**); the free-delivery threshold idea is **withdrawn** (§4.6, §6.1). |
| 6 | Do not guess order-reference sequence | ✅ No speculative default; sequence is seeded **only** from verified records/source; checkout blocked until confirmed (§9). |
| 7 | Email copy export or empty | ✅ Unchanged: seed verbatim if exported, else `''` (reference fallback) (§10). |
| 8 | Category delete → warning + reassign | ✅ `ON DELETE SET NULL` kept; admin confirm-warning + `reassign_products_category()` RPC (§4.3, §6.4). |
| 9 | Only verified payment outcomes change status | ✅ Reaffirmed; redirects never establish success (§8). |
| 10 | Confirm tier before upgrade | ✅ Unchanged: tier confirmation required first (§14). |
| 11 | Versioned CLI migrations + separate rollbacks | ✅ Unchanged; rollback files extended for the new table (§13). |

---

## 0. What changed in v2 (mapped to your earlier review points)

| # | Your requirement | v2 response |
|---|---|---|
| 1 | Real join table for Build-a-Box | ✅ `box_theme_categories` join table replaces `text[]` (§4.4). Existing assignments preserved (§9). |
| 2 | Confirm `category_slug` FK is sound | ✅ Confirmed: `categories.slug` is `UNIQUE` in the live data; FK + behaviour defined (§4.3). |
| 3 | Server-validated orders | ✅ **Removed** client `INSERT` on `orders`. Creation only via `create_order()` — a `SECURITY DEFINER` RPC that recomputes all prices/fees/totals and fixes ownership + payment state (§6). |
| 4 | Secure guest retrieval | ✅ Added `orders.public_token` (random UUID) + `get_order_by_token()`; retrieval never uses the guessable reference (§7). |
| 5 | `email_logs.order_id` FK | ✅ Added `order_id` FK (nullable) as the authoritative link; `order_reference` kept as a display snapshot (§4.8). |
| 6 | Role changes impossible for customers | ✅ Role never read from user-editable metadata; insert-time trigger + update-time trigger + no client INSERT policy (§11). |
| 7 | Payments stay pending until verified | ✅ `payment_status` is not client-writable at all; a redirect never sets `paid` (§8). |
| 8 | Preserve `gees1007`-style references | ✅ Confirmed server-side in the reference; reproduced via a Postgres sequence + `gees` prefix (§9). Exact rule still needs samples/backend source. |
| 9 | Preserve reference email copy | ✅ Confirmed copy lives in the `EmailSetting` table (empty today) — not in the bundle. Requesting owner export (§10). |
| 10 | Reviewed rollback scripts | ✅ Separate `supabase/rollback/*.sql` files, reviewed independently — not comments (§13). |
| 11 | Document backup options first | ✅ Free vs Pro/paid options documented with an interim manual process; **no upgrade recommended** yet (§14). |

---

## 1. New evidence gathered for this revision (from the reference source)

**1.1 Live data (public API, re-confirmed today)**

| Entity | Count | Fields actually present |
|---|---|---|
| `Product` | **25** | `name, description, price, category, image_url, stock, is_new, is_trending, box_eligible` (+ system) |
| `Category` | **5** | `name, slug, sort_order` (+ system) |
| `BoxTheme` | **4** | `name, description, categories[]` (+ system) |
| `StoreSetting` | **0** | — (defaults come from the bundle: `wz`) |
| `EmailSetting` | **0** | — |
| `Order` | **0** | — |

Products: price **R69–R624**, **21** box-eligible, **1** with `stock = 0`, categories = the 5 slugs.

**1.2 Bundle behaviour (VERIFIED)**
- Product entity default: `{ …, sale_price:'', visible:true, box_eligible:true }`; read paths use `box_eligible !== false`, `visible !== false`.
- Box-product pool = `box_eligible !== false AND visible !== false AND stock > 0`, further filtered to the selected theme's `categories` when a theme is picked.
- Category normaliser `CA = s => String(s||'').toLowerCase().trim().replace(/\s+/g,'-')`; `Category.list` maps `slug: row.slug || CA(row.name)`.
- Fallback arrays exist in the bundle (`IA` products, `SA` categories, `YA` themes) used only when the API returns nothing — the API returns real data, so **live rows are the source of truth**.
- Orders are created by a **Base44 backend function** (`/apps/{appId}/functions/{name}`); the client only receives `order_reference` back → the numbering rule is **not** in the public bundle.
- Email templates live in the DB (`EmailSetting`) and are rendered by the backend (`getEmailPreview`).
- Social links are **hardcoded** in the footer (`https://instagram.com/`, `/facebook.com/`, `/tiktok.com/`) — they are **not** in `StoreSetting`.

**1.3 Schema corrections vs v1** (important): `products` gains `sale_price` (nullable) and `visible` (default true); `categories` gains `visible`; `box_themes` gains `active` + `sort_order`. All are unset in the live rows today, so the proposed defaults **reproduce current behaviour exactly**.

---

## 2. Inspection status — still blocked

No credentials locally (env unset, no `.env.local`, CLI not linked), so I could not inspect the project's live schema. Read-only inspection queries are in v1 §1. Expected: an empty project. Add credentials to a git-ignored `.env.local` when you want me to run it.

---

## 3. Enums (VERIFIED)

| Enum | Values |
|---|---|
| `order_status` | `pending_payment`, `paid`, `processing`, `shipped`, `delivered`, `cancelled` |
| `payment_status` | `unpaid`, `paid`, `failed` |
| `email_type` | `order_confirmation`, `payment_confirmation`, `status_received`, `status_processing`, `status_dispatched`, `status_delivered`, `status_cancelled`, `welcome` |
| `user_role` | `customer`, `admin` |
| `email_log_status` | `sent`, `failed`, `skipped` |
| `reservation_status` | `held`, `committed`, `released`, `expired` *(new in v3 — internal only)* |

---

## 4. Tables

### 4.1 `profiles` (1:1 with `auth.users`)
`id uuid PK → auth.users(id) ON DELETE CASCADE` · `role user_role NOT NULL DEFAULT 'customer'` · `full_name text NOT NULL DEFAULT ''` · `created_at`, `updated_at`.

### 4.2 `categories`
`id uuid PK` · `name text NOT NULL` · **`slug text NOT NULL UNIQUE`** · `sort_order int NOT NULL DEFAULT 0` · `visible bool NOT NULL DEFAULT true` · timestamps.

### 4.3 `products`
`id uuid PK` · `name text NOT NULL` · `description text NOT NULL DEFAULT ''` · `price numeric(10,2) NOT NULL CHECK (>=0)` · **`sale_price numeric(10,2) NULL CHECK (>=0)`** · `category_slug text NULL` · `image_url text NOT NULL DEFAULT ''` · `stock int NOT NULL DEFAULT 0 CHECK (>=0)` · `is_new bool NOT NULL DEFAULT false` · `is_trending bool NOT NULL DEFAULT false` · `box_eligible bool NOT NULL DEFAULT true` · **`visible bool NOT NULL DEFAULT true`** · `sort_order int NOT NULL DEFAULT 0` · timestamps.

**FK (point 2):** `category_slug → categories(slug)`, which is **UNIQUE** (confirmed: the 5 live categories each have a distinct slug).
Behaviour: `ON UPDATE CASCADE` (renaming a slug propagates — matches the app's `CA`-normalised lookups) and `ON DELETE SET NULL` (deleting a category never destroys products; they become uncategorised, which is what the reference tolerates). *Alternative considered:* `ON DELETE RESTRICT` — rejected because it would block the admin Categories tab, changing existing behaviour.
Effective price = `COALESCE(sale_price, price)` — matches the reference's strikethrough display.

**Category deletion UX (point 8):** The Admin Categories tab must (a) show a confirmation warning naming the affected product count before deleting, and (b) offer reassignment first via `reassign_products_category(old_slug, new_slug)` (§6.4). The `SET NULL` FK is the safety net; the warning + reassign path is the intended workflow so no product is silently orphaned.

### 4.4 `box_themes` + `box_theme_categories` (point 4)
`box_themes`: `id uuid PK` · `name text NOT NULL` · `description text NOT NULL DEFAULT ''` · **`active bool NOT NULL DEFAULT true`** · `sort_order int NOT NULL DEFAULT 0` · timestamps.

`box_theme_categories`: `box_theme_id uuid FK → box_themes(id) ON DELETE CASCADE` · `category_slug text FK → categories(slug) ON UPDATE CASCADE ON DELETE CASCADE` · `PRIMARY KEY (box_theme_id, category_slug)`.

Preserves the **six** existing assignments exactly (§9; verified against the Base44 `BoxTheme` source: Shine On→[accessories,beauty], Cosy Home→[home], Desk & Dream→[books-stationery], Self-Care Sunday→[beauty,gifts]). Query for a theme's pool:
```sql
select p.* from products p
join box_theme_categories bt on bt.category_slug = p.category_slug
where bt.box_theme_id = $1 and p.box_eligible and p.visible and p.stock > 0;
```

### 4.5 `orders`
`id uuid PK` · `order_reference text NOT NULL UNIQUE` · **`public_token uuid NOT NULL UNIQUE DEFAULT gen_random_uuid()`** · **`idempotency_key uuid NULL`** (client-supplied) · **`idempotency_payload_hash text NULL`** · **`idempotency_owner text NULL`** (scope: `auth.uid()` for signed-in, else a hashed guest session id → §17.1) · `user_id uuid NULL → auth.users(id) ON DELETE SET NULL` · `customer_name`, `customer_email`, `phone`, `address`, `city`, `province`, `postal_code`, `gift_note` · `items jsonb NOT NULL DEFAULT '[]'` · `subtotal`, `delivery_fee`, `total` `numeric(10,2) NOT NULL DEFAULT 0` · `status order_status NOT NULL DEFAULT 'pending_payment'` · `payment_status payment_status NOT NULL DEFAULT 'unpaid'` · **`paid_at timestamptz NULL`** · **`gateway_ref text NULL`** (verified Yoco reference, server-written only) · **`stock_conflict bool NOT NULL DEFAULT false`** (set if a late verified payment cannot be reserved, §19) · `created_at`, `updated_at`.
Indexes: unique `order_reference`, unique `public_token`, unique **`(idempotency_owner, idempotency_key)`**, `(customer_email)`, `(created_at desc)`.

### 4.6 `store_settings` (singleton, `id = 1`)
`delivery_fee numeric(10,2) NOT NULL DEFAULT 100` · `store_name` · `slogan` · `delivery_info` · `refund_policy` · `privacy_policy` · `terms` · `contact_email` · `contact_phone` · `payment_link` · **`social_instagram`/`social_facebook`/`social_tiktok` `text NULL`** · `updated_at`.
All defaults verbatim from `wz` (§1). The `social_*` columns are an **additive extension** (the reference hardcodes those links); they exist so links can be shown later without hardcoding, and stay `NULL` → hidden (§0-point 9 of the plan's §10C).

### 4.7 `email_settings`
`id uuid PK` · `type email_type NOT NULL UNIQUE` · `subject text NOT NULL DEFAULT ''` · `html text NOT NULL DEFAULT ''` · `enabled bool NOT NULL DEFAULT true` · `updated_at`.

### 4.8 `email_logs` (order link)
`id uuid PK` · **`order_id uuid NULL → orders(id) ON DELETE SET NULL`** (authoritative link; `NULL` for non-order mail such as `welcome`) · `order_reference text NULL` (display snapshot, survives order deletion) · `type email_type NOT NULL` · `to_email text NOT NULL` · `status email_log_status NOT NULL` · `error text NULL` · `attempts int NOT NULL DEFAULT 0` · `created_at`.

### 4.9 `stock_reservations` (v3, point 3)
Holds stock for an unpaid order so concurrent checkouts cannot oversell.
`id uuid PK` · `order_id uuid NOT NULL → orders(id) ON DELETE CASCADE` · `product_id uuid NOT NULL → products(id) ON DELETE RESTRICT` · `quantity int NOT NULL CHECK (> 0)` · `status reservation_status NOT NULL DEFAULT 'held'` (`held` | `committed` | `released` | `expired`) · `expires_at timestamptz NOT NULL` (default `now() + interval '30 minutes'`) · `created_at`.
Indexes: `(product_id)`, `(status, expires_at)`, `(order_id)`. Only `held` rows count against availability; `released`/`expired` rows are history.

**Availability rule (single source of truth):** `available(p) = p.stock − Σ(quantity of held, non-expired reservations for p)`. This is the only place stock is counted, so the storefront, Build-a-Box pool and checkout all agree.

### 4.10 `payment_events` (v4, point 2)
Idempotency + audit trail for gateway notifications.
`id uuid PK` · `provider text NOT NULL DEFAULT 'yoco'` · **`event_id text NOT NULL UNIQUE`** (gateway event/notification id → duplicate notifications collapse) · `order_id uuid NULL → orders(id) ON DELETE SET NULL` · `outcome text NOT NULL` (`paid` | `failed` | `ignored`) · `signature_valid bool NOT NULL` · `payload_hash text NOT NULL` · `received_at timestamptz NOT NULL DEFAULT now()`.
No client grants; RLS deny-all except admin `SELECT`. Written only by the server-side verification route (§18).

---

## 5. Relationships

```
auth.users 1─1 profiles
auth.users 1─* orders                      (user_id NULL = guest)
categories 1─* products                    (products.category_slug → categories.slug, UNIQUE)
box_themes *─* categories                  (via box_theme_categories)
orders 1─* email_logs                      (email_logs.order_id, NULL for welcome)
orders 1─* stock_reservations              (CASCADE; products 1─* stock_reservations, RESTRICT)
orders 1─* payment_events                  (payment_events.order_id, NULL if unmatched)
store_settings (single row)   ·   email_settings (one row per email_type)
```

---

## 6. Server-side order creation, validation & stock (points 3, 5)

### 6.1 Validation & pricing
**No client `INSERT` on `orders`.** The policy is revoked for `anon`/`authenticated`; the only path is the `create_order()` RPC:

```sql
create function public.create_order(
  payload jsonb,
  p_idempotency_key uuid,
  p_guest_owner text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_fee numeric; v_sub numeric(10,2) := 0; it jsonb; v_line jsonb;
        v_owner text;   -- identity is derived HERE, never taken from the browser
begin
  -- ── Identity: the DB establishes it; it never trusts a client-supplied owner ──
  if auth.uid() is not null then
    v_owner := auth.uid()::text;                       -- signed-in customer
  elsif (auth.jwt() ->> 'role') = 'service_role' then  -- server route only (see §24.3)
    v_owner := p_guest_owner;                          -- validated by the server, trusted here
    if v_owner is null then raise exception 'missing_guest_owner' using errcode = '22023'; end if;
  else
    raise exception 'guest_checkout_requires_server' using errcode = '42501';
  end if;

  -- ── Idempotency: scoped to (owner, key); same key + different payload is rejected ──
  --   (logic in §17.1; returns the existing order on a true retry)
  ...

  -- Fee: server-side only. R100 standard charge from store settings; NO free-delivery threshold.
  select public.store_settings.delivery_fee into v_fee from public.store_settings where id = 1;

  for it in select * from jsonb_array_elements(payload->'items') loop
    v_line := public.resolve_line(it);      -- looks up public.products by id
    v_sub  := v_sub + (v_line->>'line_total')::numeric;   -- prices from DB, NOT the client
  end loop;

  insert into public.orders ( ... , idempotency_owner, idempotency_key, status, payment_status )
  values ( public.next_order_reference(), v_owner, p_idempotency_key, ...,
           v_sub, v_fee, v_sub + v_fee, 'pending_payment', 'unpaid' )
  returning id, order_reference, public_token, total into ...;

  return jsonb_build_object('order_reference', ..., 'public_token', ..., 'total', ...);
end $$;
```

Guarantees:
- **Prices/subtotal** come from `public.products` (`COALESCE(sale_price, price)`) — client-supplied prices are ignored.
- **Delivery fee** comes from `public.store_settings` (default **R100**) — not client-supplied, and **no free-delivery threshold** is introduced (point 5).
- **Total** = `subtotal + delivery_fee`, computed in the function.
- **Ownership / idempotency owner** is derived **inside** the function: `auth.uid()` for signed-in callers, or the server-validated guest id for a **service-role** caller. A guest identity supplied by a browser (an `anon` caller) is **refused** (§24).
- **Payment state**: `status`/`payment_status` are literals inside the function; unreachable from the client.

**Build-a-Box preservation (point 4):** `resolve_line` keeps the existing **5 / 10 / 15** pack sizes, prices each line from the **individual product price**, and applies the existing eligibility rules (`box_eligible !== false AND visible !== false`, theme filtered to its categories). Pack sizes are counts, not fixed bundle prices — no bundle price is invented. Theme/category assignments are the existing links in `box_theme_categories` (§4.4).

### 6.2 Transactional stock reservation (point 3)
All reservation happens **inside the same `create_order()` transaction**, so a failure rolls the whole order back:

```sql
-- inside create_order(), per line, after resolving the product:
select p.stock - coalesce(sum(r.quantity) filter (where r.status='held' and r.expires_at > now()), 0)
  into v_avail
  from public.products p
  left join public.stock_reservations r on r.product_id = p.id
  where p.id = v_line_product_id
  for update of p;                       -- row lock: serialises concurrent buyers

if v_avail < v_qty then
  raise exception 'insufficient_stock:%', v_line_product_id using errcode = 'P0001';
end if;

insert into public.stock_reservations (order_id, product_id, quantity, status, expires_at)
values (v_order_id, v_line_product_id, v_qty, 'held', now() + interval '30 minutes');
```

Lifecycle:
- **Held** — created on order creation; counts against `available(p)` (§4.9).
- **Committed** — set when payment is independently verified (§8); this is when `products.stock` is decremented (pending confirmation that the reference decrements on order — see §16).
- **Expired** — `release_expired_reservations()` flips `held` rows past `expires_at` to `expired`, returning the units to availability. It is `SECURITY DEFINER`, granted to `authenticated`, and also invoked opportunistically at checkout start; an optional `pg_cron` schedule can run it periodically (out of scope for Stage 3 — no extension enabled without approval).
- **Released** — an admin cancelling an unpaid order (§8) releases its `held` rows immediately.

This prevents overselling under concurrency: availability is always `stock − held`, guarded by a row lock.

### 6.3 `SECURITY DEFINER` hardening (point 1)
Every `SECURITY DEFINER` function (`create_order`, `get_order_by_token`, `next_order_reference`, `release_expired_reservations`, `reassign_products_category`, `is_admin`) follows these rules:

1. **Revoke the implicit PUBLIC grant** first: `revoke all on function public.<fn>(<args>) from public;` — and **from `anon`** on `create_order` specifically.
2. **Grant only to intended roles** — least privilege:
   - `create_order(jsonb, uuid, text)` → `grant execute … to authenticated, service_role;` **never `anon`** (guest checkout goes through the server route, §24.3).
   - `settle_order(uuid, payment_status, text)` → `grant execute … to service_role;` **only** — **never `anon` or `authenticated`**. Settlement is the server-side payment boundary (§18/§20): the server verifies the gateway outcome and settles with the service-role key; no browser session settles directly (A2-2).
   - `get_order_by_token(uuid)` → `grant execute … to anon, authenticated;` (unguessable token + field whitelist, §7).
   - `release_expired_reservations()` → `grant execute … to authenticated;` (body is idempotent; no admin check needed)
   - `reassign_products_category(text, text)` → `grant execute … to authenticated;` with an **internal `is_admin()` check** (never granted to `anon`)
   - `is_admin()` → `grant execute … to authenticated;`
3. **Pin the search path**: `set search_path = public, pg_temp` (no `$user`, no writable schemas).
4. **Schema-qualify every reference** in the body (`public.products`, `public.store_settings`, `public.orders`, `public.is_admin()`, …) so a hostile `search_path` cannot redirect them.
5. Functions are **owned by the migration role** (not `anon`/`authenticated`), so the definer privileges are not user-controllable.

### 6.4 Category reassignment (point 8)
```sql
create function public.reassign_products_category(p_old text, p_new text) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  update public.products set category_slug = p_new where category_slug = p_old;
  update public.box_theme_categories set category_slug = p_new where category_slug = p_old
    on conflict do nothing;
  return (select count(*) from public.products where category_slug = p_new);
end $$;
```
The Admin Categories tab calls this before deletion, after showing the affected-product warning (§4.3). `ON DELETE SET NULL` remains the fallback if an admin deletes without reassigning.

**Open dependency (unchanged):** whether the reference decrements `products.stock` on order vs only on verified payment must be confirmed before checkout (§16). Reservation logic above is designed to support either; activation matches the reference.

---

## 7. Guest confirmation & retrieval (points 2, 4)

- Every order gets a random `public_token` (122-bit UUID). `order_reference` stays as the human/payment-matching reference only.
- **Creation response** returns only `order_reference`, `public_token`, `total` → the confirmation screen renders from this; no `SELECT` needed.
- **Later retrieval** (e.g. reopening the confirmation link) uses `get_order_by_token()`, which returns an **explicit field whitelist** — never `to_jsonb(o) - 'user_id'`, because subtraction still leaks `id` and any future column:

```sql
create function public.get_order_by_token(p_token uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
           'order_reference', o.order_reference,
           'customer_name',   o.customer_name,
           'items',           o.items,
           'subtotal',        o.subtotal,
           'delivery_fee',    o.delivery_fee,
           'total',           o.total,
           'status',          o.status,          -- progress only
           'payment_status',  o.payment_status,  -- 'unpaid'|'paid'|'failed', never amounts/gateway data
           'created_at',      o.created_at
         )
  from public.orders o
  where o.public_token = p_token;
$$;
revoke all on function public.get_order_by_token(uuid) from public;
grant execute on function public.get_order_by_token(uuid) to anon, authenticated;
```

**Never exposed (point 2):** internal `id`, `user_id`, `public_token` (echo only, never re-queryable beyond the holder), admin notes, `paid_at`/gateway references, `next_order_reference()` internals or any other customer's row. `security definer` + exact token match; tokens are 122-bit and non-enumerable.
- Signed-in customers additionally have the RLS `SELECT` (owner-or-admin) path, which also excludes admin-only columns.

---

## 8. Payments (point 9)

- `payment_status` starts `unpaid` and is **never** settable by the client (no INSERT policy; not a parameter of `create_order`).
- The Yoco redirect/return is **informational only** — it does **not** set `paid` and is never treated as proof of payment. The return page may *show* "awaiting payment confirmation".
- **Only independently verified outcomes change payment status**: an admin marking the order paid after checking the gateway, or (later) a server-side Yoco verification/webhook call. `paid_at` records when verification happened.
- On verified `paid`: `settle_order(order_id, outcome)` is called server-side — it sets `payment_status='paid'`, commits the order's `held` reservations to `committed`, and decrements `products.stock`. **Decided (B3):** stock is decremented **only** at this independently verified point; before payment, stock is held by atomic reservations, never decremented.
- On `failed` (recorded server-side only): `held` reservations are released.
- Admin cancelling an unpaid order calls `release_expired_reservations()`-equivalent release for that order, returning stock.

---

## 9. Order references (point 6)

**Confirmed:** `order_reference` is produced by a Base44 **backend function**; the client receives it read-only. The rule is not present in the public bundle, and no literal `gees<number>` exists in it.

**Reproduction of the observed format** (`gees1007`, `gees1008` = prefix `gees` + a sequential number):
- A dedicated Postgres sequence `order_reference_seq`; `next_order_reference()` = `'gees' || nextval('order_reference_seq')`.
- Uniqueness enforced by `UNIQUE(order_reference)`; a sequence (not `count+1`) guarantees this under concurrent checkout.

**No guessed starting number (point 6).** The sequence is seeded **only** from verified order records or the backend source:
- If the `Order` table (or an owner export) is available: seed to `max(numeric suffix) + 1`, continuing the live series exactly.
- If it is **not** available: the sequence is **not** seeded with any speculative value (the earlier "default 1001" is **withdrawn**), and **checkout cannot be enabled** until the rule is confirmed. I will not invent a starting point.

**Blocking input for checkout (see §16):** provide either a few real production references **or** the Base44 backend function source. Until then, `orders.order_reference` stays `NOT NULL UNIQUE` but the sequence is left unseeded and checkout is off.

> **✅ Decision B2 (recorded): do not seed until verified.** The sequence will **not** be seeded and **checkout remains disabled** until verified existing order references or the backend source are available. No starting number will be assumed.

---

## 10. Email templates & logs (point 7)

**Confirmed:** the reference's template copy is stored in the `EmailSetting` table (`subject`, `html`) and rendered by a backend function; the public table is **empty (0 rows)**, and no default copy exists in the client bundle.

Therefore:
- If the owner can export the `EmailSetting` rows (or the backend's default copy), we seed them **verbatim** — zero rewriting.
- Until then, `email_settings` rows are seeded with `subject = ''`, `html = ''`, which is exactly the reference's own fallback behaviour when unset.
- `email_logs` uses `order_id` as the authoritative link (§4.8), with `status` ∈ `sent|failed|skipped`; the dev transport records `skipped` so development needs no subscription.

---

## 11. Admin security (role escalation guards)

- **`role` is never derived from user-editable data.** `auth.users.raw_user_meta_data` is user-writable, so `handle_new_user()` hardcodes `role = 'customer'` and only copies `full_name` (a display value) from metadata.
- `profiles` has **no client `INSERT`/`DELETE`** policy; rows are created solely by the signup trigger (`ON CONFLICT (id) DO NOTHING`).
- `prevent_role_escalation()` (BEFORE UPDATE) raises unless `auth.role() = 'service_role'` **and** `role` changed — so neither the owner nor any client can self-promote; only the server/service-role script can.
- `profiles` UPDATE policy is `USING (id = auth.uid()) WITH CHECK (id = auth.uid())` — a user may edit only their own row and cannot reassign `id`.
- `is_admin()` is `STABLE SECURITY DEFINER` reading `profiles` (never JWT claims); used by every admin write policy.
- Admin UI access is re-checked server-side per request (§10E of the plan); the service-role key stays server-only.

---

## 12. RLS policy plan (revised)

RLS enabled on **every** table; default deny. The service role bypasses RLS (server-side only).

| Table | anon SELECT | authenticated SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|---|
| `products` | ✅ true | ✅ true | admin | admin | admin |
| `categories` | ✅ true | ✅ true | admin | admin | admin |
| `box_themes` | ✅ true | ✅ true | admin | admin | admin |
| `box_theme_categories` | ✅ true | ✅ true | admin | admin | admin |
| `store_settings` | ✅ true | ✅ true | admin | admin | admin |
| `orders` | ❌ | ✅ `user_id = auth.uid() OR customer_email = auth.jwt()->>'email' OR is_admin()` | **❌ (revoked — only `create_order`)** | admin | admin |
| `stock_reservations` | ❌ | ✅ `is_admin()` | **❌ (only via `create_order` / release fn)** | **❌ (server/definer only)** | admin |
| `payment_events` | ❌ | ✅ `is_admin()` | **❌ (server-side verification only)** | ❌ | admin |
| `profiles` | ❌ | ✅ `id = auth.uid() OR is_admin()` | ❌ | ✅ `id = auth.uid()` + role trigger | ❌ |
| `email_settings` | ❌ | admin | admin | admin | admin |
| `email_logs` | ❌ | admin | ❌ (server writes) | admin | admin |

### 12.1 Function grants & `SECURITY DEFINER` hardening
- `create_order(jsonb)`, `get_order_by_token(uuid)` → `EXECUTE` to `anon, authenticated`; `release_expired_reservations()`, `reassign_products_category(text,text)`, `is_admin()` → `authenticated` (+ internal admin check where required).
- Every `SECURITY DEFINER` function first `REVOKE ALL … FROM PUBLIC`, pins `set search_path = public, pg_temp`, and schema-qualifies all references — full rules in **§6.3**.

---

## 13. Migration sequence (point 11)

Versioned Supabase CLI migrations under `supabase/migrations/`, each with a **separate, independently reviewed** rollback under `supabase/rollback/`.

| Ver | Migration | Rollback (separate file, reviewed) |
|---|---|---|
| 0000 | extensions + `set_updated_at()` + `is_admin()` | drop functions |
| 0001 | enum types (incl. `reservation_status`) | drop enum types |
| 0002 | `profiles` + `handle_new_user()` + `prevent_role_escalation()` + triggers | drop triggers/functions + table |
| 0003 | `categories` (+ unique slug) + RLS | drop table |
| 0004 | `box_themes` + `box_theme_categories` + RLS | drop tables (child first) |
| 0005 | `products` + FK + indexes + RLS | drop table |
| 0006 | `orders` + `public_token` + `idempotency_key` + `order_reference_seq` + `next_order_reference()` + `stock_reservations` + `payment_events` + RLS | drop table/sequence/functions |
| 0007 | `store_settings` + RLS | drop table |
| 0008 | `email_settings` + `email_logs` (+ `order_id` FK) + RLS | drop tables |
| 0009 | `create_order()`, `get_order_by_token()`, `settle_order()`, `release_expired_reservations()`, `reassign_products_category()` + grants/hardening | drop functions |
| 0010 | seed: 5 categories, 4 box themes, **6** theme-category links, 25 products | delete seeded rows |
| 0011 | seed: `store_settings` singleton (+ null social columns) | delete row |
| 0012 | seed: `email_settings` rows (empty copy pending owner export) | delete rows |

Applied via `supabase db push` / `migration up`. Rollbacks are executed explicitly by filename — never as inline comments. `order_reference_seq` seeding is a **separate, gated** step (checkout stays disabled until §9 is confirmed). Storage buckets (`product-images`, `brand`) remain **out of Stage 3**.

---

## 14. Backup options — document before recommending an upgrade (point 10)

Supabase's backup features depend on plan tier (verify against Supabase's current pricing/docs, as these change):

| Tier | Automated backups | PITR | Notes |
|---|---|---|---|
| **Free** | ❌ none | ❌ | Project can be paused after inactivity; restore relies on manual dumps |
| **Pro** (paid) | ✅ daily backups, limited retention | ➕ paid add-on | Retention/PITR window varies |
| Team / Enterprise (paid) | ✅ longer retention | ➕ | — |

**Recommendation for now: do NOT upgrade.** Regardless of tier, and until you tell me which tier the project is on, the migration uses an interim process that needs no paid feature:
1. `supabase db dump --schema public` (schema) + `--data-only` (data) → saved **outside git** (owner storage) before the first seed and after each migration.
2. All migrations + rollbacks versioned in git → the schema is fully reproducible.
3. Immutable Base44 source snapshot (products/categories/themes) committed under `migration/source-snapshot/` → seed data is reproducible.
4. `.env.local`/Vercel env values kept in the owner's password manager.

**Please confirm** your current tier (Free or Pro) so I can state the exact automated-backup position (**point 10**). **No upgrade is recommended** until the actual tier is confirmed; an upgrade is only worth discussing afterwards and only if you want automated daily backups or PITR.

> **✅ Decision B4 (recorded): assume Free; manual backups.** Planning proceeds on the **Free** tier and uses the **manual dump process** below until the actual account tier is confirmed. No paid upgrade is undertaken.

---

## 15. Security test checklist (run after applying; `scripts/verify-schema.ts`)

**A. Schema integrity**
- [ ] All 11 tables exist with **RLS enabled** (`relrowsecurity = true`).
- [ ] Enums present with exact values, incl. `reservation_status` and `email_log_status`.
- [ ] Seed counts: `categories=5`, `box_themes=4`, `box_theme_categories=`**6**` links` (Shine On→[accessories,beauty] · Cosy Home→[home] · Desk & Dream→[books-stationery] · Self-Care Sunday→[beauty,gifts]), `products=25`, `store_settings=1`.
- [ ] No `media.base44.com` strings remain in any row.

**B. Authorization / RLS (negative tests with the anon + a customer key)**
- [ ] anon/customer **cannot `INSERT`** into `orders` directly → denied.
- [ ] customer **cannot** set `status='paid'` / `payment_status='paid'` on their own order → denied.
- [ ] customer **cannot** `UPDATE` another user's `orders` → denied.
- [ ] customer **cannot** read another email's orders via the `orders` SELECT policy → 0 rows.
- [ ] customer **cannot** change `profiles.role` (self-promote) → `prevent_role_escalation` raises.
- [ ] customer **cannot** change `role` via `raw_user_meta_data` on signup → row is always `customer`.
- [ ] customer **cannot `INSERT`/`DELETE`** `profiles` → denied.
- [ ] anon/customer **cannot** read `email_settings` / `email_logs` / `stock_reservations` → denied.
- [ ] anon/customer **cannot** `INSERT`/`UPDATE` `stock_reservations` directly → denied.
- [ ] non-admin **cannot** execute `reassign_products_category()` → `forbidden`.

**C. `SECURITY DEFINER` hardening**
- [ ] `has_function_privilege('anon', <fn>, 'EXECUTE')` is true only for `create_order`, `get_order_by_token` (not for admin-only fns).
- [ ] `pg_proc.proacl` shows **no `=X` PUBLIC grant** on any definer function.
- [ ] each definer function has `search_path = public, pg_temp` (checked via `proconfig`).
- [ ] functions are owned by the migration role, not `anon`/`authenticated`.

**D. Order integrity**
- [ ] `create_order` **ignores client-supplied prices** — send a tampered price, assert DB total is recomputed from `products`.
- [ ] delivery fee equals `store_settings.delivery_fee` (**R100** default); client override ignored; no free-delivery branch.
- [ ] `user_id` is set from `auth.uid()` (signed-in) / `NULL` (guest); client-supplied `user_id` ignored.
- [ ] new order is always `status='pending_payment'`, `payment_status='unpaid'`.
- [ ] duplicate `order_reference` is rejected by the UNIQUE constraint.
- [ ] re-POSTing the same `idempotency_key` yields **one** order (identical reference/token).
- [ ] Build-a-Box lines keep **5/10/15** pack sizes and use **individual product prices** (no invented bundle price).

**E. Guest retrieval**
- [ ] `get_order_by_token` returns **only** the whitelisted fields (assert `id`, `user_id`, `paid_at` are absent).
- [ ] wrong/absent token → returns nothing (no row leak); tokens are non-enumerable.

**F. Stock reservation**
- [ ] two concurrent `create_order` for the last unit → exactly one succeeds, the other raises `insufficient_stock` (row-lock proven).
- [ ] `release_expired_reservations()` flips past-`expires_at` `held` rows to `expired` and restores availability.
- [ ] cancelling an unpaid order releases its held stock.
- [ ] on verified `paid`, held rows → `committed` and `products.stock` decremented.

**G. Payments**
- [ ] a browser redirect / return-page call **cannot** change `payment_status` (assert still `unpaid`).
- [ ] only a service-role/admin verified action can set `paid`; `paid_at` recorded then.
- [ ] a duplicate gateway event (`payment_events.event_id`) is a **no-op**; `settle_order` on an already-`paid` order changes nothing.
- [ ] an event with an invalid signature is stored `ignored` and does **not** set `paid`.

**H. Migrations**
- [ ] each migration has a matching `supabase/rollback/NNNN_*.sql`; applying the rollback restores the prior state on a scratch DB.
- [ ] `order_reference_seq` is **unseeded** until §9 is confirmed; checkout remains disabled.

---

## 16. Decisions — RECORDED (owner-approved)

All previously outstanding decisions are now **resolved and recorded verbatim**. No open questions remain; implementation is gated only on your separate explicit approval.

**Blocking decisions — resolved:**

| # | Decision | Recorded outcome |
|---|---|---|
| B1 | **Yoco verification** | **Manual admin verification initially.** Preserve the **existing static Yoco payment link**. **Do not** introduce the Checkout API or automatic payment integration during the initial extraction. *(§18)* |
| B2 | **Order references** | **Do not seed** `order_reference_seq` until verified existing order references or the backend source are available. **Checkout stays disabled** until then. *(§9)* |
| B3 | **Stock decrement** | Decrement `products.stock` **only after independently verified payment**; keep **atomic reservations before payment**. *(§6.2, §19)* |
| B4 | **Supabase tier** | **Assume Free** for planning; use **manual backups** until the actual account tier is confirmed. *(§14)* |

**Non-blocking decisions — recorded:**

| # | Decision | Recorded outcome |
|---|---|---|
| N1 | Build-a-Box | **No discount** (pack total = sum of individual prices). |
| N2 | Email templates | **Export verbatim if possible; otherwise leave empty.** |
| N3 | `failed` status | **Retain**; set only after a **verified** failure. |
| N4 | Reservation window | **30 minutes.** |
| N5 | Late payment w/o stock | **`stock_conflict`** for late payment where stock is unavailable. |
| N6 | Migrations | **CLI migrations.** |
| N7 | Rate limiting | **Per-IP** (trusted server-derived IP, §17.1). |

---

## 17. Public checkout protection (review point 1)

All validation happens **inside `create_order()`** (and a thin API route that never trusts client math). The client can influence only *what* is ordered, never *what it costs* or *how it is paid*.

| Input | Rule |
|---|---|
| `items` | JSON array, **1–20 lines**; each line exactly `{ product_id: uuid, quantity: int, box: bool? }`; unknown keys ignored. |
| `product_id` | Must exist in `products`; must be `visible`; box lines must additionally be `box_eligible`. Unknown/hidden → reject. |
| `quantity` | Integer `1–99` (box packs `5/10/15`); non-integer, ≤0 or over cap → reject. |
| stock | `available(p) = stock − held` must be ≥ quantity (row-locked, §6.2). |
| `customer_name` | Non-empty, 1–120 chars, control chars stripped. |
| `customer_email` | Valid format, ≤254 chars; lower-cased for the RLS email match. |
| `phone` | Optional; ≤20 chars, digits/`+ - ( ) space` only. |
| `address`/`city`/`province`/`postal_code` | Non-empty address; each ≤120 chars. |
| `gift_note` | ≤500 chars. |
| payload size | Whole JSON payload **≤ 64 KB**, enforced in the RPC and the API route. |
| price / delivery_fee / total | **Never accepted from the client** — recomputed from `products` + `store_settings`. |

**Duplicate-submission protection:** the checkout form generates an `idempotency_key uuid`. `create_order()` performs a scoped `INSERT … ON CONFLICT (idempotency_owner, idempotency_key) DO NOTHING`; a repeated POST / double-click therefore yields one order. Per-IP rate limiting on the API route (N7) provides abuse protection. **There is no owner-independent dedupe** (see §24.4): identity is `(idempotency_owner, idempotency_key)` only, so two different sessions that happen to share an email or an identical basket still create two separate orders.

### 17.1 Idempotency-key security (v5 correction)
An idempotency key is **never a global handle** — it is scoped, payload-bound and authorisation-checked:

1. **Scoped to the caller.** `idempotency_owner` = `auth.uid()` for a signed-in customer, or a **server-derived, httpOnly-cookie guest session id** (hashed) for a guest. The unique constraint is `(idempotency_owner, idempotency_key)`, so two different customers may use the same key value without colliding, and one customer's key can never address another's row.
2. **Payload-bound.** The server computes `idempotency_payload_hash = sha256(canonical(items + customer fields))` and stores it. On a key hit:
   - **same owner + same payload** → return the existing order (its `order_reference`/`public_token`) — a true retry;
   - **same owner + different payload** → **reject** (`idempotency_key_reused`), so a key cannot be recycled to create a different order;
   - **different owner** → treated as a brand-new key (isolated by the composite unique constraint) — never returns or reveals the other customer's order.
3. **No cross-customer exposure.** The conflict path returns data **only** to the same `idempotency_owner`; a guest therefore cannot retrieve another guest's order or token by guessing a key.
4. **Authorisation on retrieval.** Returning an existing order on conflict requires the same owner; **any other retrieval** (confirmation link) goes through `get_order_by_token()` with the unguessable 122-bit token (§7). There is no lookup-by-key API.
5. **Trusted IP for rate limiting.** The per-IP limit uses an IP **derived server-side** from the platform's trusted proxy header (e.g. Vercel's `x-forwarded-for` first hop set by the platform) inside the server route/middleware — **never** a client-supplied `X-Forwarded-For` or body value. If no trusted header is present, the limit falls back to a conservative global bucket rather than trusting the client.

---

## 18. Yoco verification (review point 2)

**Trusted verification route — ranked:**

1. **Server-side gateway verification (preferred).** The server holds the Yoco secret key, and confirms the payment by **querying Yoco** for the specific checkout/payment (created per order via the Yoco Checkout API) and requiring a terminal `succeeded` state before setting `paid`.
2. **Signed webhook.** Yoco's webhook is accepted **only after signature validation** (`payment_events.signature_valid=true`); unsigned or invalid-signature payloads are recorded as `ignored`, never acted on.
3. **Manual admin verification.** An admin checks the Yoco dashboard and marks the order paid.

> **⚠ Limitation you must decide on (B1).** The current artefact is a **static hosted payment link** (`pay.yoco.com/gees-convenience-store`). A static link does **not** return a gateway transaction id we can independently verify and does not raise a **signed webhook bound to our order**. Therefore, with the static link alone, route (1)/(2) are **not** available and only **route (3) manual verification** is trustworthy. Automatic verification requires moving to the **Yoco Checkout API** (server-created per-order checkout) and/or registered **webhooks**. This is decision **B1**.

> **✅ Decision B1 (recorded): manual admin verification, for now.** Keep the **existing static Yoco payment link** and **do not introduce the Yoco Checkout API or any automatic payment integration during the initial extraction**. Orders therefore move to `paid` **only** when an admin verifies the payment against the Yoco dashboard and records it server-side. `settle_order()`, `payment_events` and the idempotency rules above are **built and kept ready** (so an automated route can be added later without schema change), but **no webhook/Checkout-API path is wired in Stage 3**.

**Idempotency & duplicate notifications:**
- Every notification is keyed by `payment_events.event_id UNIQUE`; a repeat insert **conflicts and is ignored** (no double settlement).
- `settle_order(p_order_id, p_outcome, p_event_id, p_gateway_ref)` is **idempotent**: it updates only `WHERE payment_status = 'unpaid'`; if the order is already `paid`, it is a **no-op** returning current state. Late/duplicate `paid` or `failed` events after settlement change nothing.
- The **browser redirect/return is never trusted** and is not an input to `settle_order()` (§8).

**Exact point stock becomes committed:** inside the **same transaction** that flips `payment_status 'unpaid' → 'paid'`, `settle_order()` transitions the order's `held` reservations to `committed` and decrements `products.stock`. If availability can no longer be satisfied at that moment (see §19 late payment), the order is still marked `paid` but `stock_conflict=true` is set for manual fulfilment — **no oversell**.

---

## 19. Stock lifecycle verification (review point 3)

| Scenario | Behaviour |
|---|---|
| **Cancellation** (admin cancels unpaid order) | `held` reservations for the order → `released`; units return to availability. |
| **Expiry** | `release_expired_reservations()` updates `held` rows with `expires_at < now()` → `expired` (idempotent; only touches `held`). |
| **Repeated expiry jobs** | Safe: the `WHERE status='held' AND expires_at < now()` predicate means a second run affects **zero** rows; concurrent runs cannot double-release (row-level update). No cron required for correctness — it is also called at checkout start. |
| **Late payment after release** | On verified `paid` for an order whose reservations already `expired`/`released`: re-check `available`. If sufficient → re-reserve, `commit`, decrement. If not → `payment_status='paid'`, `stock_conflict=true`, no decrement; surfaced to admin (§18). |
| **Concurrent checkout** | Lines processed **sorted by `product_id`** (deterministic lock order → no deadlock); each line `SELECT … FOR UPDATE` on `products`; availability = `stock − held`. Two buyers for the last unit → one commits, the other raises `insufficient_stock` and rolls back **entirely** (no partial order). |
| **Idempotent retry** | Re-POSTing the same `idempotency_key` returns the original order without creating reservations twice (§17). |

---

## 20. Privileged-access review (review points 4, 5)

**Every elevated object, and why it cannot be abused:**

| Object | Type | Exposure | Bypass considered | Mitigation |
|---|---|---|---|---|
| `create_order(jsonb,uuid,text)` | definer fn | **`authenticated, service_role`** (never `anon`) | price/fee/owner/payment tampering; forged guest owner; huge payload; dup submit | identity derived in-function (§6.1); server route for guests (§24.3); validation + recompute (§17), forced literals, idempotency key |
| `get_order_by_token(uuid)` | definer fn | `anon, authenticated` | leak internal fields; token brute-force | explicit field whitelist (§7); 122-bit token; exact match |
| `settle_order(...)` | definer fn | **service role only** | client setting `paid` | not granted to anon/authenticated; idempotent guard (§18) |
| `release_expired_reservations()` | definer fn | `authenticated` | abusive repeated calls; data change beyond expiry | body only flips `held`→`expired`; no data read back |
| `reassign_products_category(text,text)` | definer fn | `authenticated` + internal `is_admin()` | non-admin reassign | explicit `is_admin()` raise `42501` (§6.4) |
| `is_admin()` | definer fn | `authenticated` | claim spoofing | reads `profiles` only, never JWT claims (§11) |
| `next_order_reference()` | definer fn | **no direct grant** (used inside `create_order`) | clients burning sequence numbers | `revoke … from public`, granted to no client role |
| `handle_new_user()` | trigger fn on `auth.users` | trigger-only | role injection via metadata | hardcodes `role='customer'` (§11) |
| `prevent_role_escalation()` | trigger fn on `profiles` | trigger-only | self-promotion | raises unless `(auth.jwt() ->> 'role') = 'service_role'` (§11, §24.3) |
| `set_updated_at()` | trigger fn | trigger-only | — | invoker-rights, no definer |

**Grants & schema:**
- **Every** function gets `revoke all … from public` (Postgres grants `EXECUTE` to `PUBLIC` by default) before targeted grants (§6.3).
- **Table-level:** `anon`/`authenticated` receive only `SELECT` on public catalogue tables; on `orders` **`INSERT` is revoked** (only `create_order` writes) and the **table-wide `UPDATE` is revoked**, with `UPDATE` granted only on the safe columns (`customer_name, customer_email, phone, address, city, province, postal_code, gift_note`). `DELETE` is granted to `authenticated` but RLS restricts it to admins. The payment/ownership columns (`status`, `payment_status`, `user_id`, `paid_at`, `total`, …) are therefore **not updatable** by any client role — so even a misconfigured RLS row policy cannot let a customer set them.
- **Sequence:** `USAGE, UPDATE ON SEQUENCE order_reference_seq` is **revoked** from `anon`/`authenticated` (prevents burning references); the definer `create_order` uses it internally.
- **`stock_reservations` / `payment_events`:** clients receive **no `INSERT`/`UPDATE`** grant at all; `authenticated` holds `SELECT`+`DELETE` only and RLS restricts both to admins (`is_admin()`), so a non-admin customer reads **0 rows** and deletes nothing; `anon` has **no** grant. Reservation/payment data therefore cannot be read or modified by non-admins (review point 5).
- **`service_role` (A2-1):** hosted Supabase no longer grants default privileges on new `public` objects (enforced **2026-10-30**; opt-in since 2026-04-28, default for new projects 2026-05-30). Every `service_role` privilege is therefore stated **explicitly** in the owning migration, with least privilege: **`SELECT` on all 11 tables** plus only the writes the server needs (`UPDATE` on `profiles` for role provisioning §11; `INSERT`/`UPDATE` on `email_logs`). It has **no** direct DML on `orders`/`stock_reservations`/`payment_events`/catalogue/settings, and **no** direct sequence grant — every write goes through the `SECURITY DEFINER` functions. `EXECUTE`: `create_order` + `settle_order` only. New **functions** still default to `PUBLIC EXECUTE`, which the migrations remove with `revoke … from public`.
- **Views:** there are **none** in this design. Rule for future: any view must be created `WITH (security_invoker = true)` so it inherits RLS — a default (definer) view would bypass RLS and is prohibited.
- **Owner:** all definer objects owned by the migration role, never `anon`/`authenticated`.

---

## 21. Final migration order, rollback dependencies & test procedure (review point 6)

**Migration order (each depends only on earlier ones):**

```
0000 extensions · set_updated_at() · is_admin()
0001 enum types (order_status, payment_status, email_type, user_role, email_log_status, reservation_status)
0002 profiles · handle_new_user() · prevent_role_escalation()   [dep: 0000,0001]
0003 categories (unique slug)                                   [dep: 0000]
0004 box_themes · box_theme_categories                           [dep: 0003]
0005 products (FK→categories)                                    [dep: 0003]
0006 orders · order_reference_seq · next_order_reference()
     · stock_reservations (FK→orders,products) · payment_events  [dep: 0005]
0007 store_settings                                             [dep: 0000]
0008 email_settings · email_logs (FK→orders)                    [dep: 0006]
0009 create_order · get_order_by_token · settle_order
     · release_expired_reservations · reassign_products_category [dep: 0002–0008]
0010 seed: categories, box_themes, box_theme_categories, products [dep: 0003–0005]
0011 seed: store_settings (singleton)                            [dep: 0007]
0012 seed: email_settings (empty copy pending export)            [dep: 0008]
(gated) seed order_reference_seq — only after §9/B2 confirmed
```

**Rollback dependencies (apply in reverse; a rollback may only run once its children are rolled back):**

```
0012 → 0008      (email rows)              0011 → 0007   (settings row)
0010 → 0003..0005 (seed rows)              0009 → 0002..0008 (drop functions)
0008 → 0006 (email_logs FK)                0007 → 0000 (table)
0006 → 0005 (orders/reservations/events)   0005 → 0003 (products FK)
0004 → 0003 (join table FK)                0003 → 0000 (categories)
0002 → 0000/0001                           0001 → 0000   (enums; last)
0000 (extensions/fns) — only when ALL dependents are gone
```
Each rollback file states its **preconditions** (dependent objects already removed) and is executed **explicitly by filename** — never as inline comments (§13).

**Rollback execution & migration-history reconciliation (A8-2):**
The rollbacks under `supabase/rollback/` are **raw SQL** (run with `psql`), whereas the Supabase CLI records applied versions in the `supabase_migrations.schema_migrations` table (`version` = the numeric filename prefix, e.g. `0009`). **A raw-SQL rollback does not touch that table**, so after a rollback the recorded history no longer matches the live schema. If a later `supabase db push` runs in that state, the CLI believes those versions are already applied and **skips them**, silently leaving objects missing. Reconcile as follows:

1. **Before rollback** — capture the recorded history: `select version from supabase_migrations.schema_migrations order by version;`.
2. **Roll back** — run the rollback file(s) in reverse dependency order (see the graph above).
3. **Reconcile history** — use the CLI's supported repair command, one version at a time:
   `supabase migration repair --status reverted 0009` (repeat for each reverted version).
   This updates `schema_migrations` **without** touching the database. (Equivalent raw SQL, if the CLI is unavailable: `delete from supabase_migrations.schema_migrations where version in ('0009', …);` — this only edits bookkeeping.)
4. **Re-apply** — `supabase db push` (or `migration up`) now re-applies the reverted versions and re-records them.
5. **Verify** — the recorded versions line up exactly with `supabase/migrations/*.sql`, and the schema/seed object counts match §15 A.

> ⚠ **This procedure is documented and verified only in the scratch/test harness** (`scripts/test/06_rollback_bookkeeping.sh`). It must **not** be run against a production project without a fresh manual dump first (§14, decision B4). No `supabase db push` and no production connection are performed in Stage 3/3.1.

**Practical security test procedure:**
1. **Setup:** scratch Supabase project (or local `supabase start`); apply migrations `0000–0012` via `supabase db push`; capture three keys: anon, a service-role (server-only), and one customer login.
2. **`scripts/verify-schema.ts`** (service role) — schema, enums, seed counts, `relrowsecurity`, function `acl`/`proconfig` (checklist §15 A, C, H).
3. **anon-key negative tests** — attempt (and expect denials): direct `INSERT` into `orders`; `UPDATE` own order `payment_status='paid'`; read `stock_reservations`/`payment_events`/`email_logs`; self-promote `profiles.role`; execute `reassign_products_category` (checklist §15 B).
4. **Price-tampering test** — call `create_order` with a falsified `price`/`total` in the payload; assert stored `subtotal`/`delivery_fee`/`total` equal the DB-derived values (checklist §15 D).
5. **Idempotency test** — call `create_order` twice with the same `idempotency_key`; assert **one** order row, identical `order_reference`/`public_token`.
6. **Guest retrieval test** — call `get_order_by_token` with a valid, a partial and a random token; assert only the whitelist fields for the valid token and empty results otherwise.
7. **Concurrency test** — two sessions (`psql`) or `pgbench` run `create_order` for the **last unit** of a product simultaneously; assert exactly one commits and the other raises `insufficient_stock`.
8. **Lifecycle test** — force `expires_at` into the past, run `release_expired_reservations()` **twice**; assert idempotent (`expired` only, availability restored, no double-release). Then simulate a verified late payment and assert `stock_conflict` handling.
9. **Payment test** — from the return page / an unsigned POST, assert `payment_status` **cannot** change; then drive the trusted route (§18) and assert `unpaid → paid`, `paid_at` set, reservations committed, stock decremented, and a **duplicate** event is a no-op via `payment_events.event_id`.
10. **Rollback drill** — on a throwaway DB, roll back `0012 → 0000` in the reverse order above and assert the schema returns to empty without errors.

---

## 22. Outstanding decisions

**None.** All blocking (B1–B4) and non-blocking (N1–N7) decisions are **recorded in §16**. The design is frozen pending your separate explicit approval to implement; the final implementation checklist follows.

---

## 23. Final implementation checklist (for approval)

**Pre-implementation (no DB objects created)**
- [ ] Owner approval to implement Stage 3 received.
- [ ] Confirm Supabase tier = Free (B4) and that manual dumps are the accepted backup (no upgrade).
- [ ] Confirm the store owner's admin email for first-admin provisioning.

**Migration authoring (versioned CLI, each with a separate rollback file, §13/§21)**
- [ ] `0000` extensions · `set_updated_at()` · `is_admin()`
- [ ] `0001` enum types (incl. `reservation_status`)
- [ ] `0002` `profiles` + `handle_new_user()` + `prevent_role_escalation()` + triggers
- [ ] `0003` `categories` (+ unique slug)
- [ ] `0004` `box_themes` + `box_theme_categories`
- [ ] `0005` `products` (FK → categories)
- [ ] `0006` `orders` (+ `public_token`, `idempotency_*`, `stock_conflict`) · `order_reference_seq` · `next_order_reference()` · `stock_reservations` · `payment_events`
- [ ] `0007` `store_settings`
- [ ] `0008` `email_settings` · `email_logs` (`order_id` FK)
- [ ] `0009` `create_order` · `get_order_by_token` · `settle_order` · `release_expired_reservations` · `reassign_products_category` (+ hardening: `revoke from public`, grants, pinned `search_path`, schema-qualified)
- [ ] `0010` seed categories · box themes · theme-category links (**6**) · **25** products (verbatim snapshots)
- [ ] `0011` seed `store_settings` singleton (delivery **R100**, null social)
- [ ] `0012` seed `email_settings` (verbatim export if available, else empty — N2)
- [ ] matching `supabase/rollback/NNNN_*.sql` for every migration, with stated preconditions
- [ ] RLS enabled on all **11** tables; policies per §12; column-level + sequence revokes per §20
- [ ] **Gated:** `order_reference_seq` seeding left undone; **checkout disabled** (B2)

**Verification (on a scratch project, §15/§21) — ⚠ all items below are SPECIFIED, NOT YET EXECUTED**
> No database, route or cookie code exists yet, so none of these have been run. They execute during Stage 3 implementation; pass/fail will be reported then.
- [ ] `scripts/verify-schema.ts` passes checklist **A / C / H**
- [ ] anon/customer negative RLS tests pass (**B**)
- [ ] price-tampering + idempotency (scoped key, payload-hash rejection) tests pass (**D**, §17.1)
- [ ] guest-retrieval whitelist tests pass (**E**)
- [ ] concurrency + lifecycle tests pass (**F**)
- [ ] payments: redirect cannot set `paid`; duplicate/invalid-signature events are no-ops (**G**)
- [ ] guest-boundary tests pass: **T1** two sessions → two identical orders, **T2** same-session retry → original order, **T3** renewal keeps idempotency, **T4** invalidation does not expose another guest's order, **T5** CSRF works with the identity cookie HttpOnly; plus forged-owner refusal, HMAC/expiry tamper (§24.6)
- [ ] rollback drill `0012 → 0000` succeeds on a throwaway DB (**H**)

**Env / config (server-only, no secrets committed)**
- [ ] `GUEST_SESSION_SECRET` added to `.env.local.example` + Vercel (server-only; never `NEXT_PUBLIC_*`).
- [ ] No `auth.role()` anywhere in the migration SQL (replaced by `auth.jwt() ->> 'role'`).

**Explicitly NOT in Stage 3**
- [ ] No Yoco Checkout API / webhook wiring (B1 — manual verification only).
- [ ] No checkout sequence seeding or live checkout (B2).
- [ ] No storage buckets, no data/asset migration, no deployment, no domain switch.
- [ ] Base44 site remains online and untouched.

**Reported before any DB change:** confirm this checklist; only then create migrations, apply to the project and run the verification suite.

---

## 24. Guest-session security boundary (v6)

**Principle:** the database never trusts a browser-supplied guest identity. The **server** establishes, signs, validates and forwards it; the DB accepts a guest owner **only** from a `service_role` (server) caller and **refuses** it from `anon`.

### 24.1 Cookie format — HMAC over payload **including expiry** (point 1)
Cookie `gees_guest`, value `"<payload>.<sig>"` where:
- `payload` = base64url(`{"sid":<128-bit random>,"iat":<epoch>,"exp":<epoch>}`) — **`exp` is inside the signed bytes**, so tampering with it invalidates the signature.
- `sig` = base64url(HMAC‑SHA256(`payload`, `GUEST_SESSION_SECRET`)).
- Attributes: `HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=<ttl>`; set **only** by a server action/route handler.

**Server validation (every use):** recompute the HMAC and compare with a **timing-safe** equality; then require `iat ≤ now < exp`. If the signature is invalid, or `exp` has passed, the cookie is **rejected and replaced** — an old cookie **cannot be replayed indefinitely**. `GUEST_SESSION_SECRET` is server-only (never a `NEXT_PUBLIC_*` var, never sent to the browser).

### 24.2 CSRF protection (point 2) — without exposing the identity cookie
`SameSite=Lax` is **not** the only control. The `gees_guest` identity cookie stays **HttpOnly**; the CSRF token never needs to be readable by JavaScript. The token is **derived server-side from the session and delivered inside the server-rendered form**:

1. **Token derivation** — on rendering the checkout page the server computes `csrf = base64url(HMAC‑SHA256("csrf:" + sid, GUEST_SESSION_SECRET))`. Because it is keyed by the (server-only) `sid`, the server can **recompute** it at validation time without storing anything and without a second cookie. `sid` is passed only via the HttpOnly `gees_guest` cookie.
2. **Delivery** — the token is written into a hidden form field `<input type="hidden" name="csrf" value="…">` in the **server-rendered** HTML. No JS read of any cookie is required, so the identity cookie can remain HttpOnly. (If a client-rendered/SDK submit path is ever needed, the fallback is a **separate** cookie explicitly set `HttpOnly=false` holding only the CSRF value — never the guest identity — but the server-rendered field is the default.)
3. **Validation** — on POST the Route Handler re-reads `sid` from the HttpOnly cookie, recomputes the expected `csrf`, and compares with the submitted field using a **timing-safe** equality. Mismatch or missing → **403**, no order created.
4. **Origin check** — `Origin` (or `Referer` when absent) must equal the app's canonical origin and `Sec-Fetch-Site` must be `same-origin`; otherwise **403** (defence in depth, independent of the token).
5. **POST-only** — non-POST methods are rejected.
6. **Idempotency** — a replayed POST is additionally absorbed by the idempotency key (§17).

No state-changing operation is exposed via GET. The CSRF token is bound to the session and rotates with it (§24.4) automatically, because it is derived from `sid`.

### 24.3 Supabase role validation — not `auth.role()` (point 3)
`auth.role()` is deprecated. The function uses the **current recommended claim check** instead:

```sql
elsif coalesce(auth.jwt() ->> 'role', 'anon') = 'service_role' then  -- server route only
```
- `auth.jwt() ->> 'role'` reads the **signed** `role` claim from the verified JWT (the underlying GUC is `request.jwt.claims`).
- The value is **not browser-forgeable**: `anon`/`authenticated` keys yield `anon`/`authenticated`; only the **service-role secret** (server-only) yields `service_role`.
- **Performance note:** wrap the call as `(select auth.jwt() ->> 'role')` to avoid per-row re-evaluation when used in policies.
- The same substitution applies to `prevent_role_escalation()` (§11) and any future definer check.

### 24.4 Session rotation vs idempotency (point 4)
Two distinct operations, deliberately separated:
- **Renewal** — extend `exp` while keeping the **same `sid`**. Safe at any time: the owner (`hash(sid)`) is unchanged, so an in-progress or repeated checkout still maps to the same `(idempotency_owner, idempotency_key)` and returns the same order. Renewal is the default.
- **Invalidation** — issue a **new `sid`**. Only on: sign-in (guest retired in favour of `auth.uid()`), explicit logout/clear, or suspected abuse. **Never issued while a checkout request is in flight, and not until after a successful order has been fully acknowledged.**

Because a new `sid` changes the owner, a post-invalidation retry with the same key must not become a second order. The mechanism is **owner preservation**, never payload/email similarity:

1. **Renewal keeps the owner.** The common case — extending the session — keeps the **same `sid`**, so `(idempotency_owner, idempotency_key)` is unchanged and a retry returns the **same** order. This is the default and needs no grace.
2. **Controlled invalidation keeps the owner via a signed grace cookie.** When a new `sid` is issued (sign-in, logout, abuse), the server also sets a short-lived, signed **grace cookie** containing the **previous `sid` in the same signed format** (owner = `hash(prev_sid)`, nothing else). The idempotency lookup checks the key under the **current owner *and*, if a valid grace cookie is present, the previous owner** — taking whichever already holds that `(owner, key)`. This is required because after invalidation the browser presents the *new* `sid`, so a retry would otherwise resolve to the new owner and miss the original order. The grace cookie is therefore **secondary and additive**: it never overrides the current owner, it only supplies the prior owner for the idempotency conflict lookup. It carries **no order data** and is **never** accepted on any read path (§24.7).
3. **Identity, not similarity.** There is **no** owner-independent dedupe on `(customer_email, payload_hash, …)`. Two different sessions (different owners) with the *same* email and an *identical* basket therefore produce **two separate orders** — correct behaviour. `idempotency_payload_hash` is retained **only** to detect misuse of one key by one owner (`same owner + same key + different payload → reject`, §17.1); it is never used to collapse orders across owners.
4. **After the grace window.** Once the grace cookie has expired, a resubmission is a genuinely new session and creates a new order — the client is expected to retain its `idempotency_key` per attempt and to disable resubmission while a request is in flight, so this case is a last resort, not the happy path.

Net effect: identity (owner + key) is the sole dedupe key; renewal and controlled invalidation preserve the owner; two distinct customers never collapse into one order.

### 24.5 Proposed request flow
```
Browser ──POST /api/checkout──► Route Handler (server-only)
  1. Origin / Sec-Fetch-Site check + server-derived CSRF token match      → else 403
  2. Resolve identity server-side:
       signed-in?  → createClient() [user JWT]         → auth.uid() branch
       else        → read gees_guest cookie → verify HMAC + exp → validated sid
  3. Guest path: createAdminClient() [service_role] ─► create_order(payload, key, hash(sid))
     Signed-in path: createClient() [JWT]            ─► create_order(payload, key)
  4. Function derives owner IN-FUNCTION; refuses forged owner from `anon`
  5. Return order_reference + public_token + total (whitelist only)
```
Files: existing [server.ts](file:///workspace/src/lib/supabase/server.ts) (signed-in), [admin.ts](file:///workspace/src/lib/supabase/admin.ts) (guest, service-role, server-only); **to create** `src/lib/guest/session.ts` (`getOrCreateGuestId`, `verifyGuestCookie`, `rotateGuestId`, `clearGuestId`) and `src/app/api/checkout/route.ts`; **new env** `GUEST_SESSION_SECRET`.

### 24.6 Security test cases (guest boundary) — with expected results
- [ ] **T1 · Two different guest sessions, identical orders.** Guest A and guest B each create an order with the **same email and an identical basket** (different owners, different keys; each with a fresh cookie jar). **Expected:** **two distinct order rows**, two distinct `order_reference`/`public_token`; neither returns the other's order. (Proves no owner-independent dedupe.)
- [ ] **T2 · Retry from the same session returns the original order.** Same guest, same `idempotency_key`, POSTed twice (double-click). **Expected:** **one** order; both responses carry the identical `order_reference`/`public_token`.
- [ ] **T3 · Session renewal does not break idempotency.** Renew the cookie (`exp` extended, **same `sid`**), then repeat the POST with the same key. **Expected:** **one** order; the retry returns the original; owner hash unchanged.
- [ ] **T4 · Invalidation does not let another guest retrieve an existing order.** Guest A orders (token TA). Guest B obtains A's `idempotency_key` and replays it, and also tries `get_order_by_token(TA)`. **Expected:** B's replay creates **B's own** order (different owner) and never returns A's; `get_order_by_token(TA)` from B is a normal token check — B cannot reach A's order except by presenting TA, which B does not legitimately hold. After A's session is invalidated, A's retry within the grace window still resolves to A's original order; **B still cannot**.
- [ ] **T5 · CSRF without exposing the HttpOnly identity.** Confirm the `gees_guest` cookie is `HttpOnly` (JS cannot read it); submit with a **wrong/absent** `csrf` field or a mismatched `Origin` → **403**, no order. Submit with the correct server-rendered token → **one** order. Also assert `document.cookie` never contains the guest identity.
- [ ] **Forged guest owner** — call `create_order` with the **anon** key and a `p_guest_owner` → assert `42501 guest_checkout_requires_server` (nothing inserted).
- [ ] **Service-role path** — call via the server route → assert the order is created with `idempotency_owner` = the server-derived hash, not any client value.
- [ ] **HMAC tamper** — flip a byte of the cookie payload, or change `exp` → assert the server rejects and reissues.
- [ ] **Expired cookie replay** — present a validly-signed cookie whose `exp` is in the past → assert rejection (`exp` is inside the signed payload).
- [ ] **Claim check** — confirm no function references the deprecated `auth.role()` (grep the migration SQL).

### 24.7 Grace-cookie design review (v8)
**What it is:** a second, HttpOnly cookie `gees_guest_prev` holding the **previous `sid` in the identical signed format** as §24.1 (`payload.sig`, `exp` inside the signed bytes), with a **short TTL** (e.g. 10 minutes), set only on the server at invalidation. It exists solely so an idempotency retry that straddles a session change still resolves to the original owner.

| # | Requirement | How the design satisfies it |
|---|---|---|
| 1 | Signed, time-limited, server-validated | Same HMAC + `exp`-in-payload format as §24.1; validated server-side with a timing-safe compare and `iat ≤ now < exp` on **every** use; never trusted raw. |
| 2 | Preserves only the idempotency owner; no access to order details | Its whole content is a prior `sid`; the only value derived is `hash(prev_sid)`. It is consulted **only** inside the idempotency conflict lookup on the **checkout create** path — never on `get_order_by_token` or any read path, and it returns an order **only** for a matching `(prev_owner, key)` (never enumeration, never arbitrary fetch). Reading an order still requires the unguessable `public_token`. |
| 3 | Cannot impersonate the original owner *by another guest* | HttpOnly (JS cannot read it) and HMAC-signed (cannot be forged); it lives only in the original browser that received it, so another guest neither holds nor can mint it. Scope is single-purpose (checkout create), so possession never grants read or admin access. |
| 4 | Not replayable beyond expiry | `exp` is inside the signed bytes; the server rejects an expired or tampered cookie and does not honour it thereafter. |
| 5 | Does not bypass CSRF, Origin or method checks | Origin/`Sec-Fetch-Site`, the server-derived CSRF token and POST-only run **identically** regardless of which cookie supplied the owner. The grace cookie is evaluated **after** those checks and cannot skip them; it never applies to GET. |
| 6 | Renewal / invalidation / concurrency cannot duplicate or cross-expose | Renewal keeps the same `sid` (unchanged owner). Invalidation adds the previous owner as a *secondary* lookup only. Concurrency is handled by the composite unique `(idempotency_owner, idempotency_key)` with `ON CONFLICT DO NOTHING` + re-select, plus deterministic `product_id` lock ordering — so two simultaneous requests yield one row, and two different owners never share a row. |

**Test execution status — nothing has been executed.** No database, routing or cookie code exists yet, so **every** test in §15 and §24.6 is **SPECIFIED ONLY, not executed**. Do not read any of them as passing. They become executable in the Stage 3 implementation step (schema + RPC via `supabase start` / scratch project, then the API route), and results will be reported with pass/fail then. The table above is a **design argument**, not a test result.

**Exact grace-cookie checks to run when implemented (all currently specified, not executed):**
- [ ] **G1** Set the grace cookie with a past `exp` → server rejects it (no idempotency match, new order is created).
- [ ] **G2** Tamper one byte of the grace cookie → rejected; the primary path is unaffected.
- [ ] **G3** Another guest presents a copied grace cookie value → signature still valid for the signer but the guest never holds it; assert it is unusable without the matching `sid`/browser and grants **no** read access.
- [ ] **G4** Post-invalidation retry with the same key → resolves to the **original** order via the grace owner; a *different* key creates a new order.
- [ ] **G5** Grace cookie present + wrong CSRF/Origin → still **403** (proves it does not bypass those checks).
- [ ] **G6** Grace cookie present, then a normal read (`get_order_by_token` with a wrong token) → returns nothing (proves the grace cookie is create-only).
