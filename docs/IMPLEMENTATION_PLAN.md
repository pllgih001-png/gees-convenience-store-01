# GEES Convenience Store — Implementation & Migration Plan

Status: **v2 — approved. Stage 1 (foundation & configuration) complete. The original Base44 site is untouched.**

Legend: **VERIFIED** = read directly from the live app's JavaScript bundle / public API. **DECIDED** = instructed by the store owner.

---

## 0. Delivery stages (DECIDED — staged rollout)

Each stage is implemented, tested and committed separately. The Base44 site stays online and untouched throughout; nothing is deployed to the real domain or made public until reviewed.

| Stage | Scope | Status |
|---|---|---|
| 1 | Project foundation & configuration (Next.js + TS + Tailwind, design tokens, fonts, env template, lint/build) | ✅ complete |
| 2 | Supabase project, schema, RLS, migrations, seed + verification script | pending |
| 3 | Layout shell: header (nav + search), footer, announcement bar, cart provider/drawer skeleton, UI primitives | pending |
| 4 | Home page (hero, promise, categories, New In, experience, delivery, refund) | pending |
| 5 | Shop (filters/sort) + product detail + header search results | pending |
| 6 | Build A Box (sizes 5/10/15, themes) | pending |
| 7 | Auth pages + customer Account | pending |
| 8 | Cart drawer + guest checkout + order creation + Yoco redirect + transactional email | pending |
| 9 | Admin dashboard (Overview/Products/Orders/Emails/Categories/Build a Box/Settings) | pending |
| 10 | Data + asset migration, verification, pixel-parity QA | pending |

---

## 1. Goals, constraints & locked decisions

| # | Requirement | How it is met |
|---|---|---|
| 1 | Base44 site is source of truth | Content/data extracted verbatim from the live app (§6) |
| 2 | Never modify the original | Read-only access; no writes to Base44 |
| 3 | Independent recreation | New Next.js app in this repo, built from scratch |
| 4 | Preserve pages/functionality/nav/type/colour/spacing/identity | Route + component + token parity (§5, §7, §8) |
| 5 | Keep customer accounts + private admin dashboard | Supabase Auth + role-gated Admin (§10) |
| 6 | Keep Build A Box incl. themes + packs of 5/10/15 | §7.4 |
| 7 | Keep cart, guest checkout, order creation, Yoco flow | §9 |
| 8 | Do not invent products/prices/categories/business info | Only the real 25/5/4 + settings (§6) |
| 9 | Never remove or simplify existing functionality | Parity checklist §12 |
| 10 | No Base44 branding | Assets re-hosted; no Base44 SDK/CDN (§6) |

**Stack (DECIDED):** Next.js (App Router) + TypeScript · Supabase (Postgres + Auth + Storage) · Vercel (hosting) · GitHub (source) · Yoco hosted payment link `https://pay.yoco.com/gees-convenience-store`.

**Locked decisions (DECIDED):**

| Item | Decision |
|---|---|
| Transactional email | Keep it, via **Resend**. Dev must work **without a paid subscription** (§10A) |
| First admin | The store owner; secure provisioning, **no hardcoded credentials** (§10B) |
| `payment_status` values | Taken from the bundle only — `unpaid`, `paid`, `failed` (**VERIFIED**) |
| Header product search | Preserved (**VERIFIED** it exists) |
| Social links | Generic/fake links removed; hidden until real handles are supplied (§10C) |
| Existing orders | Migrate only if genuinely accessible; otherwise await owner export (§6) |
| Visual fidelity | Closest reasonably achievable pixel-level fidelity |

**Hard rules (DECIDED, non-negotiable):** service-role keys never in frontend code (§10D) · customer data protected by server-side authorization + RLS (§10E) · never modify the Base44 site · never replace or simplify existing functionality.

---

## 2. Source-of-truth inventory (Base44 app)

- App id `6ad9e0622e1cb646cfcf950f`; host `captured-gees-curated-experience-m-cfcf950f.base44.app`.
- Front-end: React SPA (Vite). Public entity REST API is readable; used only to extract data.
- **Entities:** `Product`, `Category`, `BoxTheme`, `Order`, `StoreSetting`, `EmailSetting`, `EmailLog`, + user auth.
- **Routes (VERIFIED):** `/`, `/Shop`, `/product/:id`, `/BuildABox`, `/Account` (protected), `/Admin` (protected), `/login`, `/register`, `/forgot-password`, `/reset-password`, `*` (404).
- **Data volume (VERIFIED):** 25 products · 5 categories · 4 box themes · `StoreSetting`/`EmailSetting`/`EmailLog`/`Order` rows **all returned empty** (not publicly readable) · settings currently come from built-in defaults.
- **Assets (VERIFIED):** 1 logo PNG + 25 product images on `media.base44.com` = **26 assets**. No hero image; no CSS background images.

---

## 3. Target architecture

- **Rendering:** Next.js App Router, server-rendered storefront (SEO) + client interactivity for cart / box builder / admin.
- **Data:** Supabase Postgres via `@supabase/ssr`. RLS for catalog reads; all privileged writes server-side.
- **Auth:** Supabase Auth (email + password, cookie sessions); route protection in `middleware.ts`.
- **Storage:** Supabase Storage buckets `product-images`, `brand`.
- **Payments:** unchanged — create order, redirect to the Yoco hosted link.
- **Email:** Resend behind an abstraction (see §10A).

---

## 4. Project structure

```
gees-convenience-store-01/
├─ package.json · next.config.ts · tsconfig.json · postcss.config.mjs
├─ .gitignore · .env.local.example
├─ docs/IMPLEMENTATION_PLAN.md
├─ public/brand/…                        # migrated logo
├─ migration/
│  ├─ source-snapshot/{products,categories,box_themes}.json   # raw Base44 export (v1, immutable)
│  └─ assets-manifest.json               # filename → SHA-256 → new storage path
├─ scripts/
│  ├─ export-base44.ts                   # one-way read of the public API
│  ├─ verify-migration.ts                # counts, checksums, price parity (§6)
│  └─ promote-admin.ts                   # secure first-admin provisioning (§10B)
├─ supabase/
│  ├─ migrations/0001_init.sql           # tables, enums, RLS, triggers
│  └─ seed/{products,categories,box_themes,store_settings}.json
└─ src/
   ├─ middleware.ts                      # auth + admin guards
   ├─ app/
   │  ├─ layout.tsx · globals.css · page.tsx (Home)
   │  ├─ Shop/page.tsx · product/[id]/page.tsx · BuildABox/page.tsx
   │  ├─ Account/page.tsx (protected) · Admin/page.tsx (admin only)
   │  ├─ login|register|forgot-password|reset-password/page.tsx
   │  └─ not-found.tsx
   ├─ components/
   │  ├─ layout/{Header,Footer,MobileNav}.tsx      # header search lives here
   │  ├─ cart/{CartProvider,CartDrawer}.tsx
   │  ├─ shop/{ProductCard,FilterTabs,SortSelect,ProductGrid,SearchOverlay}.tsx
   │  ├─ home/{Hero,CategoryGrid,NewInGrid,Promise,Experience,DeliveryPolicy}.tsx
   │  ├─ box/{BoxBuilder,SizePicker,ThemePicker,ItemPicker,BoxSummary}.tsx
   │  ├─ admin/{AdminTabs,OverviewTab,ProductsTab,CategoriesTab,BoxThemesTab,OrdersTab,EmailsTab,SettingsTab}.tsx
   │  └─ ui/                                       # Radix/shadcn-style primitives
   └─ lib/
      ├─ supabase/{client,server,admin,middleware}.ts   # admin.ts = service-role, SERVER ONLY
      ├─ cart-store.ts · format.ts · orders.ts · types.ts
      └─ email/{transport.ts,resend.ts,dev.ts,templates.ts}   # §10A
```

**Dependencies (minimal):** `next`, `react`, `react-dom`, `typescript`, `tailwindcss`, `@supabase/supabase-js`, `@supabase/ssr`, `lucide-react`, Radix primitives (sheet, dialog, select, dropdown), `clsx`, `tailwind-merge`, `resend`. **Not** included: Base44 SDK, React Router, react-query, socket.io.

---

## 5. Data model (base44 → Supabase)

| Reference entity | Supabase table | Columns |
|---|---|---|
| `Product` | `products` | `id uuid`, `name`, `description`, `price numeric(10,2)`, `category_slug → categories.slug`, `image_url`, `stock int`, `is_new bool`, `is_trending bool`, `box_eligible bool`, `created_at`, `updated_at` |
| `Category` | `categories` | `id`, `name`, `slug unique`, `sort_order int` |
| `BoxTheme` | `box_themes` | `id`, `name`, `description`, `categories text[]` |
| `Order` | `orders` | `id`, `order_reference unique`, `user_id → auth.users (null for guest)`, `customer_name`, `customer_email`, `phone`, `address`, `city`, `province`, `postal_code`, `gift_note`, `items jsonb`, `subtotal`, `delivery_fee`, `total`, `status order_status`, `payment_status payment_status`, `created_at`, `updated_at` |
| `StoreSetting` | `store_settings` | singleton: `delivery_fee numeric`, `store_name`, `slogan`, `delivery_info`, `refund_policy`, `privacy_policy`, `terms`, `contact_email`, `contact_phone`, `payment_link`, + `social_instagram/social_facebook/social_tiktok` (nullable, §10C) |
| `EmailSetting` | `email_settings` | `id`, `type email_type`, `subject text`, `html text`, `enabled bool` |
| `EmailLog` | `email_logs` | `id`, `type email_type`, `to_email`, `order_reference`, `status text`, `error text`, `attempts int`, `created_at` |
| `User` | `auth.users` + `profiles` | `profiles(id → auth.users, role 'customer'\|'admin', full_name, created_at)` |

**Enums (VERIFIED from the bundle):**
- `order_status`: `pending_payment`, `paid`, `processing`, `shipped`, `delivered`, `cancelled`
- `payment_status`: `unpaid`, `paid`, `failed`
- `email_type`: `order_confirmation`, `payment_confirmation`, `status_received`, `status_processing`, `status_dispatched`, `status_delivered`, `status_cancelled`, `welcome`

**Store defaults (VERIFIED, `wz` object in bundle):**
```
delivery_fee   100
store_name     "GEES Convenience Store"
slogan         "Everything you didn't know you needed."
delivery_info  "Standard delivery R100. Estimated delivery up to two weeks within South Africa."
refund_policy  ""            privacy_policy ""      terms ""
contact_email  "geesconveniencestore01@gmail.com"   contact_phone ""
payment_link   "https://pay.yoco.com/gees-convenience-store"
```

**RLS summary (detail in §10E):** catalog + public store fields → public `SELECT`; catalog writes admin-only; `orders` → public `INSERT` (guest checkout), `SELECT` owner-or-admin, `UPDATE` admin-only; `email_*` → admin-only; `profiles` → self-read, role change blocked for non-service callers.

---

## 6. Data migration & verification

**Captured from the live app (verbatim, not invented — DECIDED to migrate as-is):**

- **25 products** (VERIFIED) — name, description, price, category, image_url, stock, is_new, is_trending, box_eligible. Price range **R69–R624**; **21/25** `box_eligible`; **1** product `stock = 0`.
- **5 categories** (VERIFIED, sort order): 1 Gifts `gifts` · 2 Books & Stationery `books-stationery` · 3 Home `home` · 4 Beauty `beauty` · 5 Accessories `accessories`.
- **4 box themes** (VERIFIED): Shine On `[accessories,beauty]` · Cosy Home `[home]` · Desk & Dream `[books-stationery]` · Self-Care Sunday `[beauty,gifts]`.
- **Store settings:** the built-in defaults above (no `StoreSetting` row exists).
- **Orders / email logs:** currently **empty / not publicly readable**. There is nothing accessible to migrate. **DECIDED:** migrate genuine existing orders **if** the owner supplies an authenticated export from Base44 (see §6.2). Until then, `orders`/`email_logs` start empty.
- **Assets:** 26 files → `media.base44.com`.

**6.1 Assets & verification (REQUIREMENT #4)**

1. Download all 26 assets → `migration/assets/` + upload to Supabase Storage (`product-images`, `brand`).
2. Record `migration/assets-manifest.json`: original URL → local filename → **SHA-256** → new public URL.
3. Rewrite every `image_url` to the Supabase URL; assert **zero** `media.base44.com` references remain in code/data.
4. `scripts/verify-migration.ts` asserts: products = **25**, categories = **5**, box themes = **4**, assets = **26**, every stored asset returns HTTP 200, and a per-product **price parity** diff (old vs. new) is empty.

**6.2 Orders migration (DECIDED, conditional)**

- Path A (preferred if owner can export): owner exports `Order` rows (CSV/JSON) from Base44 admin → `scripts/import-orders.ts` maps to the `orders` schema (status/payment_status preserved verbatim from the allowed enums), assigning `user_id` where the email matches a registered profile, else guest.
- Path B (no export): start empty; historical order history is not fabricated.
- Either way, verify imported count against the owner-supplied source before going live.

**6.3 Backups before migration (REQUIREMENT #3)**

- **Source snapshot (immutable):** commit the raw Base44 entity export to `migration/source-snapshot/` (v1) — never edited afterwards, so the migration is always reproducible.
- **Assets:** archive the 26 originals + SHA-256 manifest before any upload; keep the archive outside git (storage bucket / owner drive).
- **Supabase DB:** take a `supabase db dump` (schema + data) **before** first seed and **after** each migration; enable scheduled backups / PITR per plan tier; keep all SQL migrations in git.
- **Secrets:** `.env.local` and Vercel env vars are backed up to the owner's password manager; `.env*` is git-ignored.
- **Rollback:** because seed data is reproducible from the snapshot, rollback = drop/re-seed on a fresh project.

---

## 7. Routes & page specs

### 7.1 `/` Home
Announcement bar ("GEES GOES WHERE YOU GO. DELIVERY ACROSS SOUTH AFRICA") · Header (logo "GEES / CONVENIENCE STORE", nav, **search**, account, bag) · Hero ("EVERYTHING YOU DIDN'T KNOW YOU NEEDED." + SHOP NOW) · "The Gees Promise" (HAND-PICKED / GIFT-READY) · Shop by category (5 categories + "Build a Box" card) · New In (JUST LANDED, up to 12 latest, VIEW ALL → `/Shop?sort=new`) · "The Gees Experience" ("You came for one thing. You're leaving with five." + 4 items: Carefully packed / Hand-picked / Gift-ready / Nationwide delivery) · "GEES goes where you go" delivery block + refund policy · Footer (contact `geesconveniencestore01@gmail.com`, socials per §10C).

### 7.2 `/Shop`
Tabs: ALL · NEW IN (`?view=new`) · TRENDING (`?view=trending`) · categories (`?category=…`). Sort: Featured / Price ↑ / Price ↓. Count line ("25 products"). Product grid (image, NEW IN badge, name, price, stock).

### 7.3 `/product/[id]`
Category label · name · price · stock state (In stock / Out of stock) · description · delivery note · **ADD TO BAG**.

### 7.4 `/BuildABox`
1 Box size **5 / 10 / 15** · 2 optional theme (4 themes, filtered to their categories) · 3 add products (category filter, per-item qty, same product repeatable) · sticky "Your Box" panel (`n / size`, remaining, box total, R100 delivery note). Box is added to the bag as one line item with contents.

### 7.5 `/Account` (protected)
Order history: reference, date, item count, total, status badge; expandable item/address detail. Logout.

### 7.6 `/Admin` (admin only)
Tabs (VERIFIED labels): **Overview** · **Products** · **Orders** · **Emails** · **Categories** · **Build a Box** · **Settings**.
- Orders: list + `status` and `payment_status` selects (`unpaid`/`paid`/`failed`) + detail.
- Products / Categories / Box Themes: full CRUD (add, edit, duplicate, hide, delete).
- Emails: `email_settings` (subject/html/enabled per type) + `email_logs` (sent/failed + Retry).
- Settings: all `store_settings` fields above.

### 7.7 Auth pages
`/login`, `/register`, `/forgot-password`, `/reset-password` — Supabase Auth, same layout/tokens.

### 7.8 `/not-found`
404 styled to match (the reference 404 also shows a "Search products" box — reproduce it).

---

## 8. Design system (tokens VERIFIED from reference CSS)

```
--primary             hsl(348 68.2% 17.3%)   deep wine
--primary-foreground  hsl(40 39.1% 95.5%)    cream
--background / --card hsl(40 39.1% 95.5%)    cream
--border / --muted    hsl(37.5 32% 90.2%)
--accent              hsl(34.8 50.6% 65.9%)  gold
--muted-foreground    hsl(348 68.2% 17.3%)
--foreground          hsl(260 6.4% 9.2%)
--destructive         hsl(0 84.2% 60.2%)
--radius              0                      sharp corners
```
Headings **Cormorant Garamond**, body **Jost** (via `next/font`). Signature patterns: zero radius, uppercase micro-labels with wide tracking (`tracking-[0.25em]`), serif headings, hover `bg-primary/90`. Tokens mapped into the Tailwind theme.

---

## 9. Cart, checkout & Yoco flow (preserved exactly)

- **Cart state:** localStorage via `CartProvider`; bag icon with count badge.
- **Cart drawer** (right sheet), 3 states **Your Bag → Checkout → Order received**:
  - Bag: line items (image, name, qty ±, remove; box items show "n items inside"), Subtotal, Standard delivery, Total (ZAR), "Estimated delivery: up to 2 weeks. All sales final — no refunds.", CHECKOUT.
  - Checkout (guest): Full name, Email (validated), Phone, Street address, City, Province, Postal code, Gift note (optional) → PLACE ORDER.
  - Result: "Order received — awaiting payment", reference, amount due, **PAY WITH YOCO** → `payment_link`, "use your reference when you pay", CONTINUE BROWSING; bag retained until payment confirmed.
- **Order creation:** server action / route handler inserts the `orders` row (`status = pending_payment`, generated `order_reference`, item snapshot, subtotal/delivery/total) so the write is authorized server-side (§10E), then fire-and-forget email (§10A).
- **Payment:** no webhook (unchanged); admin confirms manually via `status`/`payment_status`.

---

## 10. Security, accounts & email

### 10A. Transactional email architecture & failure handling (DECIDED — Resend, no paid subscription required)

- **Abstraction:** `lib/email/transport.ts` exposes `send({type, to, order_reference, data})`. Implementations:
  - `resend.ts` — used when `RESEND_API_KEY` is set (Resend free tier is sufficient; domain verification optional in dev).
  - `dev.ts` — default when no key: renders the template, **records the email in `email_logs` with `status = 'skipped'`**, logs to console. **No purchase or subscription needed for development.**
- **Templates:** one per `email_type` (order_confirmation, payment_confirmation, status_*, welcome), editable in Admin → Emails (`subject`, `html`, `enabled`), mirroring the reference's `EmailSetting`.
- **Trigger points:** order created · payment marked paid · status changed (received/processing/dispatched/delivered/cancelled) · welcome on registration.
- **Never blocks the customer flow:** sending is fire-and-forget after the DB write commits; an email failure must not fail checkout or a status change.
- **Failure handling:** every attempt writes an `email_logs` row (`sent` | `failed` | `skipped`) with `error` + `attempts`. Admin → Emails lists failures and offers **Retry** (idempotent, increments `attempts`). Failures never surface as customer-facing errors.
- **Env:** `RESEND_API_KEY`, `EMAIL_FROM` (e.g. `GEES <no-reply@…>`), `EMAIL_REPLY_TO` (defaults to the store contact email).

### 10B. Secure first-admin provisioning (DECIDED, REQUIREMENT #1)

- On signup, a DB trigger creates `profiles` with `role = 'customer'` (default). RLS **blocks** any client from changing its own `role`.
- The store owner registers normally via `/register`, then is promoted **once** using `scripts/promote-admin.ts`:
  - Requires `SUPABASE_SERVICE_ROLE_KEY` from the environment (server-side only; never bundled).
  - Usage: `npm run make-admin -- owner@example.com` → sets `role = 'admin'` for that user by email lookup.
- **No credentials, emails or keys are hardcoded.** The owner's email is passed as a CLI argument at runtime; the script refuses to run without the service-role env var.
- Documented alternative (equivalent, for operators without the script): a one-time SQL statement in the Supabase SQL editor, e.g.
  `update public.profiles set role = 'admin' where id = (select id from auth.users where email = 'owner@example.com');`
- Admin access is additionally re-checked server-side on every `/Admin` request and in every privileged action (§10E).

### 10C. Social links (DECIDED)

- The reference's generic `instagram.com/`, `facebook.com/`, `tiktok.com/` placeholders are **not** carried over.
- `store_settings` gains nullable `social_instagram` / `social_facebook` / `social_tiktok`.
- The footer renders a social icon **only if** its URL is set; with none set, **no social links are shown** — until the owner supplies real handles.

### 10D. Service-role key handling (REQUIREMENT #6)

- `SUPABASE_SERVICE_ROLE_KEY` exists **only** in server env (never `NEXT_PUBLIC_*`) and is imported exclusively by `src/lib/supabase/admin.ts`.
- `admin.ts` is used only inside server actions / route handlers / `scripts/`; it is never imported by a client component (enforced by review + an ESLint `no-restricted-imports` boundary).
- Any accidental `NEXT_PUBLIC_`-prefixed secret is treated as a leak and rotated.

### 10E. Customer-data privacy: server-side authorization + RLS (REQUIREMENT #5)

- **RLS is the backstop; the server is the authority.** Every privileged action re-verifies the caller's session + role server-side (never trusting client state).
- Policies: catalog/`store_settings` public `SELECT`; catalog writes admin-only; `orders` public `INSERT`, `SELECT` restricted to `customer_email = auth.jwt()->>'email'` **or** admin, `UPDATE` admin-only; `email_settings`/`email_logs` admin-only; `profiles` self-read with role immutable by clients.
- Guest checkout inserts with an explicit column allow-list (no client-chosen `status`/`payment_status`); the server sets `pending_payment`/`unpaid`.
- `orders` never expose other customers' data; admin reads use the service-role server client.

---

## 11. Environment & configuration

```
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=            # SERVER ONLY — never exposed to the frontend
NEXT_PUBLIC_PAYMENT_LINK=https://pay.yoco.com/gees-convenience-store
RESEND_API_KEY=                       # optional in dev (§10A); email falls back to dev transport
EMAIL_FROM=GEES <no-reply@example.com>
EMAIL_REPLY_TO=geesconveniencestore01@gmail.com
```
Vercel: project linked to this GitHub repo; env vars set in Vercel (Production/Preview/Development). Supabase migrations applied via CLI.

---

## 12. Migration / parity checklist

- [ ] Repo scaffolded (Next.js + TS + Tailwind), no Base44 dependencies
- [ ] `0001_init.sql` applied (tables, 3 enums, RLS, `profiles` trigger)
- [ ] Source snapshot committed to `migration/source-snapshot/` (immutable)
- [ ] DB + asset backups taken before migration (§6.3)
- [ ] Seed: **25 products**, **5 categories**, **4 box themes**, store settings (R100 / Yoco link)
- [ ] **26 assets** migrated; manifest with SHA-256; zero `media.base44.com` references
- [ ] `verify-migration.ts` green (counts 25/5/4/26, asset HTTP 200, price parity)
- [ ] Existing orders migrated **iff** owner export supplied (§6.2), history preserved
- [ ] Design tokens + fonts match (palette, radius 0, Cormorant/Jost)
- [ ] Routes: `/`, `/Shop`, `/product/:id`, `/BuildABox`, `/Account`, `/Admin`, auth pages, 404
- [ ] Header (logo, nav, **search**, account, bag), announcement bar, footer
- [ ] Home sections: hero, promise, categories, New In, experience, delivery, refund, footer
- [ ] Shop filters (new/trending/category/sort) + counts
- [ ] Product detail (incl. out-of-stock)
- [ ] Build A Box (sizes 5/10/15, 4 themes, qty, box line item)
- [ ] Cart drawer 3 states; guest checkout + validation
- [ ] Order creation + reference; Yoco redirect
- [ ] Accounts: register/login/reset + order history
- [ ] Admin: Overview/Products/Orders/Emails/Categories/Build a Box/Settings (full CRUD + retry)
- [ ] Email transport (§10A) with dev fallback; failure retry works
- [ ] First admin promoted via `promote-admin.ts`; no credentials in code (§10B)
- [ ] RLS + server-side authz verified (cross-customer reads blocked) (§10E)
- [ ] No service-role key in any client bundle (§10D)
- [ ] Social links hidden until real handles supplied (§10C)
- [ ] Route-by-route visual comparison vs. reference at pixel level (desktop + mobile)

---

## 13. Open items / remaining inputs

1. **Owner's Base44 order export** — needed to migrate real order history (§6.2). Until supplied, orders start empty.
2. **Resend domain** — which sending domain (for `EMAIL_FROM`) once configured; dev works without it.
3. **Real social handles** — until supplied, social links stay hidden (§10C).
4. **Category cards on Home** — no images found in the build (VERIFIED); confirm text-only cards match the live site during the pixel-parity pass.
5. **Supabase plan tier** — determines whether PITR vs. scheduled backups are available (§6.3).

---

## 14. Out of scope

- Any change to the Base44 site (read-only source of truth).
- Inventing products, prices, categories, copy, business info, or fake links.
- Carrying any Base44 runtime/branding into the new app.
