# Stage 3 — Supabase schema, RLS & migration plan (FOR REVIEW)

Status: **proposed — not applied.** No database objects have been created. Awaiting explicit approval.
Base44 site untouched. No credentials are stored in this repo.

---

## 1. Inspection of the existing Supabase project — BLOCKED (needs credentials)

Requirement #1 asks me to confirm the project's current state. I could not run any inspection because
there are currently **no credentials available** in this workspace:

- `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` → **unset**
- no `.env.local` present (only `.env.local.example`)
- Supabase CLI not installed / project not linked

**How to unblock (no secrets in chat):** put the values in a git-ignored `.env.local`
(copied from `.env.local.example`). For CLI-based migrations, run `npx supabase login` and
`npx supabase link --project-ref <ref>` locally (the DB password stays in your machine's Supabase
CLI credential store, never in this repo or chat).

**Read-only inspection I will run once credentials exist** (tables/enums/policies only — no writes):

```sql
-- schema objects
select table_name from information_schema.tables where table_schema = 'public';
select typname from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typtype = 'e';
select tablename, policyname, cmd, roles from pg_policies where schemaname = 'public';
select relname, relrowsecurity from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r';
select id, name from storage.buckets;
select count(*) from auth.users;
```

**Expected result:** a brand-new, empty project (no public tables, no buckets, 0 users).
The plan below assumes that; if the inspection shows otherwise (e.g. tables created from the
dashboard), the migrations are additive and will not disturb them.

---

## 2. Design principles

- **Faithful to the reference data shape** (§5 of IMPLEMENTATION_PLAN.md) — same entities, same enums,
  same field names/semantics. Nothing invented.
- **Additive & reversible** — only `CREATE …`; every migration has a documented `-- DOWN` block.
  No destructive `DROP`/`ALTER` of pre-existing objects.
- **RLS as backstop, server as authority** — privileged work runs server-side (§10E); the
  service-role key is never in the browser and never committed.
- **Postgres conventions** — `uuid` PKs (`gen_random_uuid()`), `timestamptz`, `numeric(10,2)` for money,
  `snake_case`, explicit `search_path` on all functions.

---

## 3. Enums (VERIFIED from the reference bundle)

| Enum | Values |
|---|---|
| `order_status` | `pending_payment`, `paid`, `processing`, `shipped`, `delivered`, `cancelled` |
| `payment_status` | `unpaid`, `paid`, `failed` |
| `email_type` | `order_confirmation`, `payment_confirmation`, `status_received`, `status_processing`, `status_dispatched`, `status_delivered`, `status_cancelled`, `welcome` |
| `user_role` | `customer`, `admin` |
| `email_log_status` | `sent`, `failed`, `skipped` |

---

## 4. Tables

### `profiles` — 1:1 with `auth.users`
| Column | Type | Constraints |
|---|---|---|
| `id` | uuid | PK, FK → `auth.users(id)` ON DELETE CASCADE |
| `role` | user_role | NOT NULL, default `'customer'` |
| `full_name` | text | NOT NULL, default `''` |
| `created_at` | timestamptz | NOT NULL, default `now()` |
| `updated_at` | timestamptz | NOT NULL, default `now()` |

### `categories`
| Column | Type | Constraints |
|---|---|---|
| `id` | uuid | PK |
| `name` | text | NOT NULL |
| `slug` | text | NOT NULL, **UNIQUE** |
| `sort_order` | int | NOT NULL, default 0 |
| `created_at` / `updated_at` | timestamptz | NOT NULL, default `now()` |

### `box_themes`
| Column | Type | Constraints |
|---|---|---|
| `id` | uuid | PK |
| `name` | text | NOT NULL |
| `description` | text | NOT NULL, default `''` |
| `categories` | text[] | NOT NULL, default `'{}'` — logical list of `categories.slug` |
| `sort_order` | int | NOT NULL, default 0 |
| `created_at` / `updated_at` | timestamptz | NOT NULL, default `now()` |

### `products`
| Column | Type | Constraints |
|---|---|---|
| `id` | uuid | PK |
| `name` | text | NOT NULL |
| `description` | text | NOT NULL, default `''` |
| `price` | numeric(10,2) | NOT NULL, CHECK `>= 0` |
| `category_slug` | text | FK → `categories(slug)` ON UPDATE CASCADE ON DELETE SET NULL, nullable |
| `image_url` | text | NOT NULL, default `''` |
| `stock` | int | NOT NULL, default 0, CHECK `>= 0` |
| `is_new` | bool | NOT NULL, default false |
| `is_trending` | bool | NOT NULL, default false |
| `box_eligible` | bool | NOT NULL, default false |
| `sort_order` | int | NOT NULL, default 0 |
| `created_at` / `updated_at` | timestamptz | NOT NULL, default `now()` |

Indexes: `products(category_slug)`, `products(is_new)`, `products(is_trending)`, and a
`to_tsvector`-free simple `name ILIKE` GIN/`pg_trgm` index for header search (added in the search stage).

### `orders`
| Column | Type | Constraints |
|---|---|---|
| `id` | uuid | PK |
| `order_reference` | text | NOT NULL, **UNIQUE** |
| `user_id` | uuid | FK → `auth.users(id)` ON DELETE SET NULL, **nullable (guest checkout)** |
| `customer_name` | text | NOT NULL |
| `customer_email` | text | NOT NULL |
| `phone` | text | nullable |
| `address` | text | nullable |
| `city` | text | nullable |
| `province` | text | nullable |
| `postal_code` | text | nullable |
| `gift_note` | text | nullable |
| `items` | jsonb | NOT NULL, default `'[]'` |
| `subtotal` | numeric(10,2) | NOT NULL, default 0 |
| `delivery_fee` | numeric(10,2) | NOT NULL, default 0 |
| `total` | numeric(10,2) | NOT NULL, default 0 |
| `status` | order_status | NOT NULL, default `'pending_payment'` |
| `payment_status` | payment_status | NOT NULL, default `'unpaid'` |
| `created_at` / `updated_at` | timestamptz | NOT NULL, default `now()` |

Indexes: `orders(order_reference)` (unique), `orders(customer_email)`, `orders(created_at desc)`.

### `store_settings` — singleton row (`id = 1`)
| Column | Type | Constraints |
|---|---|---|
| `id` | int | PK, CHECK `id = 1` (enforces single row) |
| `delivery_fee` | numeric(10,2) | NOT NULL, default 100 |
| `store_name` | text | NOT NULL, default `'GEES Convenience Store'` |
| `slogan` | text | NOT NULL, default `'Everything you didn''t know you needed.'` |
| `delivery_info` | text | NOT NULL, default `'Standard delivery R100. Estimated delivery up to two weeks within South Africa.'` |
| `refund_policy` / `privacy_policy` / `terms` | text | NOT NULL, default `''` |
| `contact_email` | text | NOT NULL, default `'geesconveniencestore01@gmail.com'` |
| `contact_phone` | text | NOT NULL, default `''` |
| `payment_link` | text | NOT NULL, default `'https://pay.yoco.com/gees-convenience-store'` |
| `social_instagram` / `social_facebook` / `social_tiktok` | text | **nullable** (§10C — hidden until real handles exist) |
| `updated_at` | timestamptz | NOT NULL, default `now()` |

### `email_settings`
| Column | Type | Constraints |
|---|---|---|
| `id` | uuid | PK |
| `type` | email_type | NOT NULL, **UNIQUE** |
| `subject` | text | NOT NULL, default `''` |
| `html` | text | NOT NULL, default `''` |
| `enabled` | bool | NOT NULL, default true |
| `updated_at` | timestamptz | NOT NULL, default `now()` |

### `email_logs`
| Column | Type | Constraints |
|---|---|---|
| `id` | uuid | PK |
| `type` | email_type | NOT NULL |
| `to_email` | text | NOT NULL |
| `order_reference` | text | nullable (logical link to `orders.order_reference`; not a hard FK) |
| `status` | email_log_status | NOT NULL |
| `error` | text | nullable |
| `attempts` | int | NOT NULL, default 0 |
| `created_at` | timestamptz | NOT NULL, default `now()` |

---

## 5. Relationships

```
auth.users 1───1 profiles
auth.users 1───0..* orders           (user_id nullable → guest orders)
categories 1───0..* products         (via category_slug → categories.slug)
categories.slug  <· ··>  box_themes.categories[]   (logical, array of slugs — validated in app)
orders.order_reference  <· ··>  email_logs.order_reference   (logical, for admin traceability)
store_settings  (exactly one row)
email_settings  (one row per email_type)
```

---

## 6. Functions & triggers

| Object | Purpose |
|---|---|
| `public.set_updated_at()` | BEFORE UPDATE trigger → `new.updated_at = now()` (all tables with `updated_at`) |
| `public.handle_new_user()` | AFTER INSERT ON `auth.users` → create `profiles` row with `role='customer'`, `full_name` from metadata. `SECURITY DEFINER`, `search_path=''` |
| `public.prevent_role_escalation()` | BEFORE UPDATE ON `profiles` → raise if `role` changes and `auth.role() <> 'service_role'` (blocks clients promoting themselves; the service-role script may promote) |
| `public.is_admin()` | `STABLE SECURITY DEFINER` → `exists(select 1 from profiles where id = auth.uid() and role='admin')`; used by write policies |

`order_reference` is **generated server-side** (never client-supplied). Its exact format is preserved
from the reference and will be confirmed from the bundle during the checkout stage — flagged in §12.

---

## 7. RLS policy plan

RLS **enabled on every table**. `anon`/`authenticated` get only what is listed; everything else is
denied by default. The service role bypasses RLS (server-side only).

| Table | Role | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|---|
| `products` | anon, authenticated | ✅ `true` | admin | admin | admin |
| `categories` | anon, authenticated | ✅ `true` | admin | admin | admin |
| `box_themes` | anon, authenticated | ✅ `true` | admin | admin | admin |
| `store_settings` | anon, authenticated | ✅ `true` | admin | admin | admin |
| `orders` | anon | ❌ | ✅ **with check** `status='pending_payment' AND payment_status='unpaid'` | ❌ | ❌ |
| `orders` | authenticated | ✅ `customer_email = auth.jwt()->>'email' OR is_admin()` | ✅ (same check as anon) | admin | admin |
| `profiles` | authenticated | ✅ `id = auth.uid() OR is_admin()` | ❌ (created by trigger) | ✅ `id = auth.uid()` **+ role-escalation trigger** | ❌ |
| `email_settings` | authenticated | admin | admin | admin | admin |
| `email_logs` | authenticated | admin | ❌ (server writes via service role) | admin | admin |

Notes:
- **Guests cannot read orders** (no session). The confirmation/result step uses the row returned by the
  server-side insert, and delivery of history is via the confirmation email — same behaviour as the reference.
- **Clients cannot choose `status`/`payment_status`** on insert (policy `WITH CHECK`), so nobody can
  self-mark an order as paid. Totals are recomputed server-side.
- **`store_settings.social_*`** are public to read but the UI hides them when null (§10C).
- Admin `SELECT` on orders reads through the **server** client (service role) per §10E; the RLS admin
  clause exists as a defence-in-depth backstop.

---

## 8. Migration sequence (additive, each with a documented DOWN)

| # | File | Up | Down (rollback) |
|---|---|---|---|
| 0000 | `0000_helpers.sql` | `pgcrypto` (if needed), `set_updated_at()`, `is_admin()` | drop the two functions |
| 0001 | `0001_enums.sql` | create the 5 enum types (guarded `IF NOT EXISTS`) | drop the 5 types |
| 0002 | `0002_profiles.sql` | `profiles` table + RLS + `handle_new_user()` + `prevent_role_escalation()` + updated_at trigger | drop triggers/functions then table |
| 0003 | `0003_catalog.sql` | `categories`, `box_themes`, `products` + FKs + indexes + RLS + updated_at triggers | drop tables (children first) |
| 0004 | `0004_orders.sql` | `orders` + indexes + RLS + updated_at trigger | drop table |
| 0005 | `0005_store_settings.sql` | `store_settings` + RLS + seed singleton row (`insert … on conflict do nothing`) | `delete from store_settings`; drop table |
| 0006 | `0006_email.sql` | `email_settings`, `email_logs` + RLS | drop tables |
| 0007 | `0007_seed_catalog.sql` | seed **5 categories**, **4 box themes**, **25 products** from the captured snapshot (idempotent upsert by natural key) | delete seeded rows by slug/name |
| 0008 | `0008_seed_email_templates.sql` | seed one `email_settings` row per `email_type` with the reference's default copy (empty until the owner supplies text) | delete rows |

Applied with the Supabase CLI (`supabase migration up`) or `psql -f`. Every file is re-runnable where
practical (`create … if not exists`, `on conflict do nothing`).

**Storage buckets are intentionally NOT part of Stage 3** — `product-images` and `brand` are created in
the asset-migration stage (§6.1), after approval.

---

## 9. Seed data (from the captured, verbatim snapshot)

- 5 categories: Gifts `gifts`, Books & Stationery `books-stationery`, Home `home`, Beauty `beauty`, Accessories `accessories` (sort order 1–5)
- 4 box themes: Shine On `[accessories,beauty]`, Cosy Home `[home]`, Desk & Dream `[books-stationery]`, Self-Care Sunday `[beauty,gifts]`
- 25 products with the captured name/description/price/category/image_url/stock/is_new/is_trending/box_eligible
  (price range R69–R624, 21 box-eligible, 1 out of stock)
- `store_settings` singleton with the reference defaults
- `email_settings`: one row per type (subject/html empty pending owner copy)

Source: `migration/source-snapshot/` (immutable v1 export, committed separately in the migration stage).

---

## 10. Verification (to run after applying)

`scripts/verify-schema.ts` asserts:
1. All 8 tables exist; **RLS enabled** on each.
2. All 5 enums exist with the exact value sets in §3.
3. Expected policy set present (count + names per table).
4. Seed counts: `categories = 5`, `box_themes = 4`, `products = 25`, `store_settings = 1`.
5. Negative tests with the **anon** key: `orders` SELECT returns nothing; a client cannot set
   `status='paid'` on insert; a client cannot change its own `profiles.role`.
6. No `media.base44.com` strings in DB rows.

---

## 11. Rollback strategy

- Apply order is child-last on teardown; each migration's `-- DOWN` block reverses exactly its objects.
- Because the schema + seed are reproducible from the snapshot, a full rollback = drop `public` objects
  (or a fresh project) and re-run migrations.
- `supabase db dump` (schema + data) captured before the first seed and after each migration (§6.3).

---

## 12. Decisions needing your review / confirmation

1. **`products.category_slug` FK vs `category_id` uuid** — proposed: keep the reference's **slug** FK
   (faithful, minimal transformation). Alternative: uuid `category_id` + unique slug.
2. **`box_themes.categories` as `text[]`** (reference shape) vs a join table. Proposed: `text[]`, validated in app + verify script.
3. **`order_reference` format** — generated server-side; exact pattern to be confirmed from the bundle before the checkout stage.
4. **`payment_status = 'failed'`** — kept in the enum (reference has it); confirm how/when it is set (Yoco has no callback in the current flow).
5. **Email template defaults** — seed with empty subject/html (owner supplies), or capture the reference's built-in copy?
6. **Supabase plan tier** — affects PITR vs scheduled backups (§6.3).
7. **Apply method** — Supabase CLI (`supabase link` + `migration up`) vs pasted SQL in the dashboard. CLI is preferred (versioned in git); it requires linking the project locally.
