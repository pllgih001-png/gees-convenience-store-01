# GEES Convenience Store — Implementation & Migration Plan

Status: **DRAFT — awaiting approval. No implementation has started. The original Base44 site is untouched.**

---

## 1. Goals & constraints

| # | Requirement | How it is met |
|---|---|---|
| 1 | Base44 site is source of truth | Content/data extracted verbatim from the live app (see §6) |
| 2 | Do not modify the original | We only read it; no writes to Base44 |
| 3 | Independent recreation | New Next.js app in this repo, built from scratch |
| 4 | Preserve pages/functionality/nav/type/colour/spacing/identity | Route + component + token parity (§5, §7, §8) |
| 5 | Keep customer accounts + private admin dashboard | Supabase Auth + role-gated Admin (§10) |
| 6 | Keep Build A Box incl. themes + packs of 5/10/15 | §7.4 |
| 7 | Keep cart, guest checkout, order creation, Yoco flow | §9 |
| 8 | Do not invent products/prices/categories/business info | Only the real 25 products / 5 categories / 4 themes / settings |
| 9 | Do not remove or simplify functionality | Parity checklist §12 |
| 10 | No Base44 branding | Assets re-hosted in Supabase Storage; no Base44 SDK/CDN |

**Stack:** Next.js (App Router) + TypeScript · Supabase (DB + Auth + Storage) · Vercel (hosting) · GitHub (source) · Yoco hosted payment link `https://pay.yoco.com/gees-convenience-store`.

---

## 2. Source-of-truth inventory (Base44 app)

- App id: `6ad9e0622e1cb646cfcf950f`; host `captured-gees-curated-experience-m-cfcf950f.base44.app`
- Front-end: React SPA (Vite). Public REST API for entities is readable (used only to extract data).
- **Entities:** `Product`, `Category`, `BoxTheme`, `Order`, `StoreSetting`, `EmailSetting`, `EmailLog`, plus user auth.
- **Routes found:** `/`, `/Shop`, `/product/:id`, `/BuildABox`, `/Account` (protected), `/Admin` (protected), `/login`, `/register`, `/forgot-password`, `/reset-password`, `*` (404).
- **Data volume:** 25 products · 5 categories · 4 box themes · store settings (defaults) · orders/email logs returned empty publicly.
- **Assets:** 1 logo PNG + 25 product images on `media.base44.com` (no hero image; no CSS background images).

---

## 3. Target architecture

- **Rendering:** Next.js App Router. Storefront pages render on the server (SEO) with client interactivity for cart/box/admin.
- **Data:** Supabase Postgres, accessed with `@supabase/ssr` (server + browser clients). RLS for public read of catalog and protected writes.
- **Auth:** Supabase Auth (email + password), session via cookies, route protection in `middleware.ts`.
- **Storage:** Supabase Storage buckets `product-images` and `brand` for migrated assets.
- **Payments:** unchanged — create order, then redirect the customer to the Yoco hosted link (`payment_link`).
- **Emails:** Base44 previously handled transactional email; Supabase does not. Requires a provider (see §13, open item).

---

## 4. Project structure

```
gees-convenience-store-01/
├─ package.json · next.config.ts · tsconfig.json · postcss.config.mjs
├─ .gitignore · .env.local.example
├─ docs/IMPLEMENTATION_PLAN.md
├─ public/brand/…                       # migrated logo
├─ supabase/
│  ├─ migrations/0001_init.sql          # tables, enums, RLS, triggers
│  └─ seed/{products,categories,box_themes,store_settings}.json
└─ src/
   ├─ middleware.ts                     # auth + admin guards
   ├─ app/
   │   ├─ layout.tsx                    # fonts, Providers, Header, Footer
   │   ├─ globals.css                   # design tokens (§8)
   │   ├─ page.tsx                      # / Home
   │   ├─ Shop/page.tsx                 # /Shop
   │   ├─ product/[id]/page.tsx         # /product/:id
   │   ├─ BuildABox/page.tsx            # /BuildABox
   │   ├─ Account/page.tsx              # protected
   │   ├─ Admin/page.tsx                # protected (role = admin)
   │   ├─ login|register|forgot-password|reset-password/page.tsx
   │   └─ not-found.tsx                 # 404
   ├─ components/
   │   ├─ layout/{Header,Footer,MobileNav}.tsx
   │   ├─ cart/{CartProvider,CartDrawer}.tsx
   │   ├─ shop/{ProductCard,FilterTabs,SortSelect,ProductGrid}.tsx
   │   ├─ home/{Hero,CategoryGrid,NewInGrid,Promise,Experience,DeliveryPolicy}.tsx
   │   ├─ box/{BoxBuilder,SizePicker,ThemePicker,ItemPicker,BoxSummary}.tsx
   │   ├─ admin/{AdminTabs,OverviewTab,ProductsTab,CategoriesTab,BoxThemesTab,OrdersTab,EmailsTab,SettingsTab}.tsx
   │   └─ ui/                           # shadcn/Radix primitives (button, input, textarea, sheet, dialog, select, badge…)
   └─ lib/
      ├─ supabase/{client,server,middleware}.ts
      ├─ cart-store.ts                  # localStorage persistence
      ├─ format.ts                      # ZAR formatter (reference uses `R${n}`)
      ├─ orders.ts                      # createOrder + reference generation
      └─ types.ts
```

**Dependencies (kept minimal):** `next`, `react`, `react-dom`, `typescript`, `tailwindcss`, `@supabase/supabase-js`, `@supabase/ssr`, `lucide-react` (icons used by reference), Radix primitives for sheet/dialog/select/dropdown (as in reference), `clsx` + `tailwind-merge`. **Not** included: Base44 SDK, React Router, react-query, socket.io (all Base44-runtime only).

---

## 5. Data model (base44 → Supabase)

| Reference entity | Supabase table | Columns |
|---|---|---|
| `Product` | `products` | `id uuid`, `name text`, `description text`, `price numeric(10,2)`, `category_slug text → categories.slug`, `image_url text`, `stock int`, `is_new bool`, `is_trending bool`, `box_eligible bool`, `created_at`, `updated_at` |
| `Category` | `categories` | `id uuid`, `name text`, `slug text unique`, `sort_order int` |
| `BoxTheme` | `box_themes` | `id uuid`, `name text`, `description text`, `categories text[]` |
| `Order` | `orders` | `id uuid`, `order_reference text unique`, `user_id uuid null → auth.users`, `customer_name`, `customer_email`, `phone`, `address`, `city`, `province`, `postal_code`, `gift_note`, `items jsonb`, `subtotal numeric`, `delivery_fee numeric`, `total numeric`, `status order_status`, `payment_status payment_status`, `created_at`, `updated_at` |
| `StoreSetting` | `store_settings` | singleton: `id`, `delivery_fee numeric`, `payment_link text`, (other fields as found in Admin → Settings) |
| `EmailSetting` | `email_settings` | `id`, `type email_type`, `subject text`, `body text`, `enabled bool` |
| `EmailLog` | `email_logs` | `id`, `type email_type`, `to_email`, `order_reference`, `status text(sent/failed)`, `error text`, `created_at` |
| `User` | `auth.users` + `profiles` | `profiles(id → auth.users, role text('customer'|'admin'), full_name, …)` |

**Enums (from the reference build):**
- `order_status`: `pending_payment`, `paid`, `processing`, `shipped`, `delivered`, `cancelled`
- `email_type`: `order_confirmation`, `payment_confirmation`, `status_received`, `status_processing`, `status_dispatched`, `status_delivered`, `status_cancelled`, `welcome`
- `payment_status` options: **to confirm** from Admin UI (values not yet captured).

**RLS:** `products`, `categories`, `box_themes`, public `store_settings` → public `SELECT`; writes admin-only. `orders` → insert public (guest checkout), select owner-or-admin, update admin-only. `email_*` → admin-only.

---

## 6. Data migration

**Captured from the live app (verbatim, not invented):**

- **25 products** — see `supabase/seed/products.json` to be generated from the captured export. Fields: name, description, price, category, image_url, stock, is_new, is_trending, box_eligible. Price range R69–R624; 21 of 25 are `box_eligible`; 1 product has `stock = 0`.
- **5 categories** (sort order): 1 Gifts `gifts` · 2 Books & Stationery `books-stationery` · 3 Home `home` · 4 Beauty `beauty` · 5 Accessories `accessories`.
- **4 box themes:** Shine On `[accessories,beauty]` · Cosy Home `[home]` · Desk & Dream `[books-stationery]` · Self-Care Sunday `[beauty,gifts]`.
- **Store settings:** `delivery_fee = 100`, `payment_link = https://pay.yoco.com/gees-convenience-store` (defaults; the `StoreSetting` row is empty, so these are the app defaults).
- **Orders / email logs:** not publicly readable → nothing to migrate (confirm with owner whether any real orders exist).
- **Assets:** 25 product images + 1 logo → download from `media.base44.com`, upload to Supabase Storage, rewrite all URLs (satisfies "no Base44 branding/dependency").

**Migration steps (executed only after approval):**
1. Export entity JSON → transform to seed SQL/JSON (`supabase/seed/*`).
2. Download assets → `public/brand/` + Supabase Storage `product-images`.
3. Apply `0001_init.sql`, run seed, verify counts (25/5/4) and price parity.

---

## 7. Routes & page specs

### 7.1 `/` Home
Announcement bar ("GEES GOES WHERE YOU GO. DELIVERY ACROSS SOUTH AFRICA") · Header (logo "GEES / CONVENIENCE STORE", nav, search, account, bag) · Hero ("EVERYTHING YOU DIDN'T KNOW YOU NEEDED." + SHOP NOW) · "The Gees Promise" (HAND-PICKED / GIFT-READY) · **Shop by category** (5 categories + "Build a Box" card) · **New In** (JUST LANDED, up to 12 latest, VIEW ALL → `/Shop?sort=new`) · "The Gees Experience" (4 promise items) · "GEES goes where you go" delivery/refund block · Footer (The Gees List signup, contact email, socials).

### 7.2 `/Shop`
Tabs: ALL · NEW IN (`?view=new`) · TRENDING (`?view=trending`) · categories (`?category=…`). Sort: Featured / Price ↑ / Price ↓. Product count ("25 products"). Grid of product cards (image, NEW IN badge, name, price, stock).

### 7.3 `/product/[id]`
Category label · name · price · stock state (In stock / Out of stock) · description · delivery note · **ADD TO BAG**. Image gallery.

### 7.4 `/BuildABox`
Step 1 box size: **5 / 10 / 15 items** · Step 2 optional theme (4 themes, filtered to their categories) · Step 3 add products (category filter, per-item qty counters, "add same product more than once") · sticky "Your Box" panel (`n / size items`, remaining count, box total, delivery R100 note). Box added to bag as a single line item (contents incl. item counts).

### 7.5 `/Account` (protected)
Signed-in order history: reference, date, item count, total, status badge; expandable item/address detail. Logout.

### 7.6 `/Admin` (protected, admin only)
Tabs (labels from reference): **Overview** (analytics) · **Products** · **Orders** · **Emails** · **Categories** · **Build a Box** · **Settings**.
- Orders: list + `payment_status` and `status` selects, detail view.
- Products/Categories/Box Themes: full CRUD.
- Emails: `EmailSetting` list + `EmailLog` (sent/failed, retry).
- Settings: store settings (delivery fee, Yoco payment link).

### 7.7 Auth pages
`/login`, `/register`, `/forgot-password`, `/reset-password` — Supabase Auth, same layout/tokens.

### 7.8 `/not-found`
404 styled to match.

---

## 8. Design system (tokens from reference CSS)

```
--primary            hsl(348 68.2% 17.3%)   #4A0E20 (deep wine)
--primary-foreground hsl(40 39.1% 95.5%)    cream
--background / --card hsl(40 39.1% 95.5%)   #F5F1E8
--border / --muted   hsl(37.5 32% 90.2%)
--accent             hsl(34.8 50.6% 65.9%)  gold
--muted-foreground   hsl(348 68.2% 17.3%)
--foreground         hsl(260 6.4% 9.2%)
--destructive        hsl(0 84.2% 60.2%)
--radius             0                      (sharp corners)
```
- **Headings:** Cormorant Garamond 300–700 · **Body:** Jost 300–700 (Google Fonts, self-hosted or via `next/font`).
- Signature patterns: zero radius, uppercase micro-labels with wide tracking (`tracking-[0.25em]`), serif headings, cream/wine/gold palette, hover `bg-primary/90`.
- Map tokens to Tailwind theme so all components use semantic classes.

---

## 9. Cart, checkout & Yoco flow (preserved exactly)

- **Cart state:** persisted client-side (localStorage) via `CartProvider`; bag icon with count.
- **Cart drawer** (right sheet), 3 states: **Your Bag → Checkout → Order received**.
  - Bag: line items (image, name, qty ±, remove; box items show "n items inside"), Subtotal, Standard delivery, Total (ZAR), note "Estimated delivery: up to 2 weeks. All sales final — no refunds.", CHECKOUT.
  - Checkout (guest): Full name, Email (validated), Phone, Street address, City, Province, Postal code, Gift note (optional) → PLACE ORDER.
  - Result: "Order received — awaiting payment", order reference, amount due, **PAY WITH YOCO** (opens `payment_link`), "use your reference when you pay", CONTINUE BROWSING. Bag retained until payment confirmed.
- **Order creation:** insert `orders` row with `status = pending_payment`, generated `order_reference`, item snapshot, subtotal/delivery/total. (In the reference this was a client helper; here it becomes a server action / route handler to protect the write.)
- **Payment:** no webhook — confirmation is manual by admin (unchanged from reference). Admin marks `payment_status`/`status`.

---

## 10. Auth & roles

- Supabase Auth (email/password) with cookie sessions.
- `profiles.role`: `customer` (default) | `admin`.
- `middleware.ts` guards `/Account` (any signed-in user) and `/Admin` (admin only).
- Preserve reference behaviours: register, login, forgot/reset password, account order list, admin dashboard access.

---

## 11. Environment & configuration

```
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=          # server-only (admin writes / seed)
NEXT_PUBLIC_PAYMENT_LINK=https://pay.yoco.com/gees-convenience-store
# Email provider (see open items) — e.g. RESEND_API_KEY=
```
Vercel: project linked to this GitHub repo; env vars set in Vercel. Supabase migrations applied via CLI.

---

## 12. Migration / parity checklist

- [ ] Repo scaffolded (Next.js + TS + Tailwind), no Base44 dependencies
- [ ] `0001_init.sql` applied (tables, enums, RLS, triggers)
- [ ] Seed: 25 products, 5 categories, 4 box themes, store settings (R100 / Yoco link)
- [ ] 26 assets migrated to Supabase Storage / `public`; no `media.base44.com` references remain
- [ ] Design tokens + fonts match (palette, radius 0, Cormorant/Jost)
- [ ] Routes: `/`, `/Shop`, `/product/:id`, `/BuildABox`, `/Account`, `/Admin`, auth pages, 404
- [ ] Header (logo, nav, search, account, bag), announcement bar, footer
- [ ] Home sections: hero, promise, categories, New In, experience, delivery, footer
- [ ] Shop filters (new/trending/category/sort) + counts
- [ ] Product detail (stock states incl. out-of-stock)
- [ ] Build A Box (sizes 5/10/15, 4 themes, qty, box line item)
- [ ] Cart drawer 3 states; guest checkout + validation
- [ ] Order creation + reference; Yoco redirect
- [ ] Accounts: register/login/reset + order history
- [ ] Admin: Overview/Products/Orders/Emails/Categories/Build a Box/Settings
- [ ] Route-by-route visual comparison vs. reference (desktop + mobile)

---

## 13. Open items / risks (need decisions)

1. **Transactional email** — Base44 sent order/status/welcome emails. Supabase doesn't. Need a provider (Resend/SMTP) + edge/server function, or mark as out-of-scope. Affects `EmailSetting`/`EmailLog`/Admin → Emails parity.
2. **Admin user provisioning** — who is the first admin, and how the role is set.
3. **`payment_status` enum values** — confirm exact options from Admin UI.
4. **Search** — confirm scope (products search overlay in header).
5. **Social links** — reference uses generic `instagram.com/`, `facebook.com/`, `tiktok.com/`; confirm real handles or keep placeholders.
6. **Existing orders** — confirm whether any real orders exist in Base44 to migrate.
7. **Category card visuals on Home** — no images found in the build; verify whether text-only cards are correct.
8. **Fidelity target** — confirm pixel-parity expectation vs. structural parity.

---

## 14. Out of scope

- Any change to the Base44 site (source of truth stays read-only).
- Inventing products, prices, categories, copy, or business info.
- Nothing from Base44's runtime/branding is carried into the new app.
