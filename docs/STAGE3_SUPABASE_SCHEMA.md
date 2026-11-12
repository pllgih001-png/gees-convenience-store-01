# Stage 3 — Supabase schema, RLS & migration plan (FINAL v3, FOR REVIEW)

Status: **proposed — not applied.** No database objects created. No credentials used or committed. Base44 site untouched.
Supersedes v1 and v2. Awaiting explicit approval before implementation.
v2 architecture approved in principle; v3 applies the eleven final amendments and adds a security test checklist (§15).

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

Preserves the four existing assignments exactly (§9). Query for a theme's pool:
```sql
select p.* from products p
join box_theme_categories bt on bt.category_slug = p.category_slug
where bt.box_theme_id = $1 and p.box_eligible and p.visible and p.stock > 0;
```

### 4.5 `orders`
`id uuid PK` · `order_reference text NOT NULL UNIQUE` · **`public_token uuid NOT NULL UNIQUE DEFAULT gen_random_uuid()`** · `user_id uuid NULL → auth.users(id) ON DELETE SET NULL` · `customer_name`, `customer_email`, `phone`, `address`, `city`, `province`, `postal_code`, `gift_note` · `items jsonb NOT NULL DEFAULT '[]'` · `subtotal`, `delivery_fee`, `total` `numeric(10,2) NOT NULL DEFAULT 0` · `status order_status NOT NULL DEFAULT 'pending_payment'` · `payment_status payment_status NOT NULL DEFAULT 'unpaid'` · **`paid_at timestamptz NULL`** · `created_at`, `updated_at`.
Indexes: unique `order_reference`, unique `public_token`, `(customer_email)`, `(created_at desc)`.

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

---

## 5. Relationships

```
auth.users 1─1 profiles
auth.users 1─* orders                      (user_id NULL = guest)
categories 1─* products                    (products.category_slug → categories.slug, UNIQUE)
box_themes *─* categories                  (via box_theme_categories)
orders 1─* email_logs                      (email_logs.order_id, NULL for welcome)
orders 1─* stock_reservations              (CASCADE; products 1─* stock_reservations, RESTRICT)
store_settings (single row)   ·   email_settings (one row per email_type)
```

---

## 6. Server-side order creation, validation & stock (points 3, 5)

### 6.1 Validation & pricing
**No client `INSERT` on `orders`.** The policy is revoked for `anon`/`authenticated`; the only path is the `create_order()` RPC:

```sql
create function public.create_order(payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_fee numeric; v_sub numeric(10,2) := 0; it jsonb; v_line jsonb; ...
begin
  -- Fee: server-side only. R100 standard charge from store settings; NO free-delivery threshold.
  select public.store_settings.delivery_fee into v_fee from public.store_settings where id = 1;

  for it in select * from jsonb_array_elements(payload->'items') loop
    v_line := public.resolve_line(it);      -- looks up public.products by id
    v_sub  := v_sub + (v_line->>'line_total')::numeric;   -- prices from DB, NOT the client
  end loop;

  insert into public.orders ( ... , status, payment_status )   -- forced literals
  values ( public.next_order_reference(), auth.uid(), ..., v_sub, v_fee, v_sub + v_fee,
           'pending_payment', 'unpaid' )
  returning id, order_reference, public_token, total into ...;

  return jsonb_build_object('order_reference', ..., 'public_token', ..., 'total', ...);
end $$;
```

Guarantees:
- **Prices/subtotal** come from `public.products` (`COALESCE(sale_price, price)`) — client-supplied prices are ignored.
- **Delivery fee** comes from `public.store_settings` (default **R100**) — not client-supplied, and **no free-delivery threshold** is introduced (point 5).
- **Total** = `subtotal + delivery_fee`, computed in the function.
- **Ownership**: `user_id` is set from `auth.uid()` only; the client cannot choose it.
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

1. **Revoke the implicit PUBLIC grant** first: `revoke all on function public.<fn>(<args>) from public;`
2. **Grant only to intended roles** — least privilege:
   - `create_order(jsonb)`, `get_order_by_token(uuid)` → `grant execute … to anon, authenticated;`
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
- On verified `paid`: `settle_order(order_id, outcome)` is called server-side — it sets `payment_status='paid'`, commits the order's `held` reservations to `committed`, and decrements `products.stock` (pending reference confirmation, §16).
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
| 0006 | `orders` + `public_token` + `order_reference_seq` + `next_order_reference()` + `stock_reservations` + RLS | drop table/sequence/functions |
| 0007 | `store_settings` + RLS | drop table |
| 0008 | `email_settings` + `email_logs` (+ `order_id` FK) + RLS | drop tables |
| 0009 | `create_order()`, `get_order_by_token()`, `settle_order()`, `release_expired_reservations()`, `reassign_products_category()` + grants/hardening | drop functions |
| 0010 | seed: 5 categories, 4 box themes, 4 theme-category links, 25 products | delete seeded rows |
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

---

## 15. Security test checklist (run after applying; `scripts/verify-schema.ts`)

**A. Schema integrity**
- [ ] All 10 tables exist with **RLS enabled** (`relrowsecurity = true`).
- [ ] Enums present with exact values, incl. `reservation_status` and `email_log_status`.
- [ ] Seed counts: `categories=5`, `box_themes=4`, `box_theme_categories=7` links, `products=25`, `store_settings=1`.
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

**H. Migrations**
- [ ] each migration has a matching `supabase/rollback/NNNN_*.sql`; applying the rollback restores the prior state on a scratch DB.
- [ ] `order_reference_seq` is **unseeded** until §9 is confirmed; checkout remains disabled.

---

## 16. Decisions / inputs needed before implementation

1. **Build-a-Box pricing rule** — pack sizes **5/10/15** and **individual product prices** are preserved; still to confirm whether the reference applies **any** pack discount (if not, pack total = sum of individual prices).
2. **Order-reference samples or backend function source** — **blocking**; the sequence is not seeded (and checkout stays off) until verified (§9). No guessed number.
3. **`EmailSetting` export** (or the backend's default copy) — to preserve template copy verbatim; otherwise templates stay empty (§10).
4. **Stock decrement timing** — confirm whether the reference decrements `products.stock` at order creation or only on verified payment, so reservation-commit timing matches (§6.2, §8). *(Ratified: `ON DELETE SET NULL` for categories, with an admin warning + reassign path — no longer open.)*
5. **`payment_status='failed'`** — confirm it is ever used, and by what (nothing in the current flow sets it).
6. **Payment verification method** — confirm the Yoco verification route (manual admin check vs a server-side verification/webhook) that will authorise `paid`.
7. **Supabase tier** (Free/Pro) — required before any backup recommendation (§14).
8. **Apply method** — CLI migrations (preferred, versioned) vs dashboard SQL.
