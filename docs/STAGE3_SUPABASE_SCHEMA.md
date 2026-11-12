# Stage 3 — Supabase schema, RLS & migration plan (REVISED v2, FOR REVIEW)

Status: **proposed — not applied.** No database objects created. No credentials used or committed. Base44 site untouched.
Supersedes v1. Awaiting explicit approval before implementation.

---

## 0. What changed in v2 (mapped to your review points)

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

### 4.4 `box_themes` + `box_theme_categories` (point 1)
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

### 4.8 `email_logs` (point 5)
`id uuid PK` · **`order_id uuid NULL → orders(id) ON DELETE SET NULL`** (authoritative link; `NULL` for non-order mail such as `welcome`) · `order_reference text NULL` (display snapshot, survives order deletion) · `type email_type NOT NULL` · `to_email text NOT NULL` · `status email_log_status NOT NULL` · `error text NULL` · `attempts int NOT NULL DEFAULT 0` · `created_at`.

---

## 5. Relationships

```
auth.users 1─1 profiles
auth.users 1─* orders                      (user_id NULL = guest)
categories 1─* products                    (products.category_slug → categories.slug, UNIQUE)
box_themes *─* categories                  (via box_theme_categories)
orders 1─* email_logs                      (email_logs.order_id, NULL for welcome)
store_settings (single row)   ·   email_settings (one row per email_type)
```

---

## 6. Server-side order creation & validation (point 3)

**No client `INSERT` on `orders`.** The policy is revoked for `anon`/`authenticated`; the only path is:

```sql
create function public.create_order(payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_fee numeric; v_sub numeric(10,2) := 0; it jsonb; v_line jsonb; ...
begin
  select delivery_fee into v_fee from store_settings where id = 1;   -- fee: server-side only

  for it in select * from jsonb_array_elements(payload->'items') loop
    v_line := public.resolve_line(it);      -- looks up products by id
    v_sub  := v_sub + (v_line->>'line_total')::numeric;   -- prices from DB, NOT the client
  end loop;

  insert into orders (
    order_reference,
    user_id,                                -- = auth.uid() when signed in, else NULL
    customer_name, customer_email, phone, address, city, province, postal_code, gift_note,
    items, subtotal, delivery_fee, total,
    status, payment_status                  -- forced
  ) values (
    public.next_order_reference(),
    auth.uid(),
    payload->>'customer_name', payload->>'customer_email', ...,
    v_sub, v_fee, v_sub + v_fee,
    'pending_payment', 'unpaid'
  ) returning id, order_reference, public_token, total into ...;

  return jsonb_build_object('order_reference', ..., 'public_token', ..., 'total', ...);
end $$;
```

Guarantees:
- **Prices/subtotal** come from `products` (`COALESCE(sale_price, price)`) — client-supplied prices are ignored.
- **Delivery fee** comes from `store_settings` — not client-supplied.
- **Total** = `subtotal + delivery_fee`, computed in the function.
- **Ownership**: `user_id` is set from `auth.uid()` only; the client cannot choose it.
- **Payment state**: `status`/`payment_status` are literals inside the function; unreachable from the client.
- `revoke all on function public.create_order(jsonb) from public; grant execute … to anon, authenticated;`

**Open dependency:** Build-a-Box line pricing (pack sizes **5 / 10 / 15**) and any free-delivery threshold must be confirmed from the reference before the checkout stage; `resolve_line` will encapsulate that rule. Until then it handles normal items only. See §16.

---

## 7. Guest confirmation & retrieval (point 4)

- Every order gets a random `public_token` (122-bit UUID). `order_reference` stays as the human/payment-matching reference only.
- **Creation response** returns `order_reference`, `public_token`, `total` → the confirmation screen renders from this; no `SELECT` needed.
- **Later retrieval** (e.g. reopening the confirmation link) uses:
  ```sql
  create function public.get_order_by_token(p_token uuid) returns jsonb
  language sql stable security definer set search_path = public as $$
    select to_jsonb(o) - 'user_id' from orders o where o.public_token = p_token;
  $$;
  ```
  `security definer` + token match only; returns a **whitelisted** projection (no `user_id`, no other customers' rows). Tokens are not enumerable.
- Signed-in customers additionally have the RLS `SELECT` (owner-or-admin) path.

---

## 8. Payments (point 7)

- `payment_status` starts `unpaid` and is **never** settable by the client (no INSERT policy; not a parameter of `create_order`).
- The Yoco redirect/return is treated as **informational only** — it does not set `paid`. The return page may *show* "awaiting payment confirmation".
- `paid` is only ever written server-side by the service-role client: by an admin action (Admin → Orders) and, in future, by a Yoco webhook/verification call. `paid_at` records when verification happened.
- `failed` remains available for a rejected/failed payment recorded server-side.

---

## 9. Order references (point 8)

**Confirmed:** `order_reference` is produced by a Base44 **backend function**; the client receives it read-only. The rule is not present in the public bundle, and no literal `gees<number>` exists in it.

**Proposed reproduction of the observed format** (`gees1007`, `gees1008` = prefix `gees` + a 4-digit sequential number):
- A dedicated Postgres sequence `order_reference_seq`; `next_order_reference()` = `'gees' || nextval('order_reference_seq')`.
- Sequence initialised to `max(numeric suffix of existing references) + 1`, i.e. continuing the live series; default **1001** if the table is empty.
- A sequence (not `count+1`) guarantees uniqueness under concurrent checkout.
- Uniqueness enforced by `UNIQUE(order_reference)`.

**Still to confirm before checkout development (see §16):** the exact starting number and step. Please supply either a few real references (e.g. the gees1007/1008 values seen in production) **or** the Base44 backend function source, so the sequence can be seeded identically. I will not invent a starting point.

---

## 10. Email templates & logs (point 9)

**Confirmed:** the reference's template copy is stored in the `EmailSetting` table (`subject`, `html`) and rendered by a backend function; the public table is **empty (0 rows)**, and no default copy exists in the client bundle.

Therefore:
- If the owner can export the `EmailSetting` rows (or the backend's default copy), we seed them **verbatim** — zero rewriting.
- Until then, `email_settings` rows are seeded with `subject = ''`, `html = ''`, which is exactly the reference's own fallback behaviour when unset.
- `email_logs` uses `order_id` as the authoritative link (§4.8), with `status` ∈ `sent|failed|skipped`; the dev transport records `skipped` so development needs no subscription.

---

## 11. Admin security (point 6)

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
| `orders` | ❌ | ✅ `customer_email = auth.jwt()->>'email' OR is_admin()` | **❌ (revoked — only `create_order`)** | admin | admin |
| `profiles` | ❌ | ✅ `id = auth.uid() OR is_admin()` | ❌ | ✅ `id = auth.uid()` + role trigger | ❌ |
| `email_settings` | ❌ | admin | admin | admin | admin |
| `email_logs` | ❌ | admin | ❌ (server writes) | admin | admin |

Function grants: `create_order` and `get_order_by_token` → `EXECUTE` to `anon, authenticated`; all `SECURITY DEFINER` functions pinned with `set search_path`.

---

## 13. Migration sequence (point 10)

Versioned Supabase CLI migrations under `supabase/migrations/`, each with a **separate, independently reviewed** rollback under `supabase/rollback/`.

| Ver | Migration | Rollback (separate file, reviewed) |
|---|---|---|
| 0000 | extensions + `set_updated_at()` + `is_admin()` | drop functions |
| 0001 | 5 enum types | drop enum types |
| 0002 | `profiles` + `handle_new_user()` + `prevent_role_escalation()` + triggers | drop triggers/functions + table |
| 0003 | `categories` (+ unique slug) + RLS | drop table |
| 0004 | `box_themes` + `box_theme_categories` + RLS | drop tables (child first) |
| 0005 | `products` + FK + indexes + RLS | drop table |
| 0006 | `orders` + `public_token` + `order_reference_seq` + `next_order_reference()` + RLS | drop table/sequence/functions |
| 0007 | `store_settings` + RLS | drop table |
| 0008 | `email_settings` + `email_logs` (+ `order_id` FK) + RLS | drop tables |
| 0009 | `create_order()` + `get_order_by_token()` + grants | drop functions |
| 0010 | seed: 5 categories, 4 box themes, 4 theme-category links, 25 products | delete seeded rows |
| 0011 | seed: `store_settings` singleton (+ null social columns) | delete row |
| 0012 | seed: `email_settings` rows (empty copy pending owner export) | delete rows |

Applied via `supabase db push` / `migration up`. Rollbacks are executed explicitly by filename — never as inline comments. Storage buckets (`product-images`, `brand`) remain **out of Stage 3**.

---

## 14. Backup options — document before recommending an upgrade (point 11)

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

**Please confirm** your current tier (Free or Pro) so I can state the exact automated-backup position; an upgrade is only worth discussing if you want automated daily backups or PITR.

---

## 15. Verification (after applying)

`scripts/verify-schema.ts`: 9 tables exist with RLS enabled; 5 enums with exact values; expected policy set; seed counts (`categories=5`, `box_themes=4`, `box_theme_categories=7` links across the 4 themes, `products=25`, `store_settings=1`); **negative tests with the anon key**: cannot `INSERT` an order directly, cannot set `status='paid'`, cannot change own `profiles.role`, cannot read another email's orders; `create_order` ignores client-supplied prices (totals recomputed); duplicate `order_reference` rejected; no `media.base44.com` strings in rows.

---

## 16. Decisions / inputs needed before implementation

1. **Build-a-Box pricing rule** (pack sizes 5/10/15) and any free-delivery threshold — required for `resolve_line`.
2. **Order-reference samples or backend function source** — to seed the sequence identically (§9).
3. **`EmailSetting` export** (or the backend's default copy) — to preserve template copy verbatim (§10).
4. **Category delete behaviour** — proposed `ON DELETE SET NULL`; confirm or choose `RESTRICT`.
5. **`payment_status='failed'`** — confirm it is ever used, and by what (nothing in the current flow sets it).
6. **Stock decrement on order** — does the reference reduce `products.stock` when an order is placed? (Not observed in the bundle.)
7. **Supabase tier** (Free/Pro) for the backup statement (§14).
8. **Apply method** — CLI migrations (preferred, versioned) vs dashboard SQL.
