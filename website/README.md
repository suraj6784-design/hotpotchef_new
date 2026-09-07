# HotPotChef marketing site (`hotpotchef.com`)

Static site synced to the same Supabase catalog as the Flutter app.
Phase 1–2: browse, web cart, hybrid app handoff, and web Razorpay checkout.

## What it does

| Path | Purpose |
|------|---------|
| `/` | Brand landing + searchable Available meals |
| `/meal/{id}` | Dish preview + add to web cart / open app |
| `/chef/{id}` | Kitchen preview + Available plates |
| `/cart` | Web cart → **Pay on web** or **Checkout in app** |
| `/auth` | Email/password (same Supabase Auth as the app) |
| `/checkout` | Razorpay Checkout.js via `create-split-order` + `recover-payment` |
| `/terms` `/privacy` `/faq` `/cancellation` | Help docs (same copy as in-app Account links) |
| `/help` | Index of the policy pages |
| `/.well-known/assetlinks.json` | Android App Links verification |
| `/.well-known/apple-app-site-association` | iOS Universal Links stub |

## Setup

```bash
cp js/config.example.js js/config.js
```

Fill in `js/config.js`:

- `supabaseUrl` / `supabaseAnonKey` (same as Flutter `.env`)
- `razorpayKeyId` (publishable Key ID only — secret stays on Edge Functions)
- `playStoreUrl`

`js/config.js` is **gitignored**.

Deploy the `website/` folder as the site root (Vercel/Netlify rewrites included).

## Phase 2 flows

1. **Catalog** — search + veg filter + matching kitchens on `/`
2. **Hybrid** — add plates to web cart → **Checkout in app** opens `/cart?items=id:qty,…` → `CartImportScreen` → customer cart tab
3. **Web pay** — sign in → `/checkout` → Razorpay → same Edge Functions as Android

## App Links note

Replace `REPLACE_WITH_*` SHA-256 values in `assetlinks.json` before expecting verified App Links for `/meal`, `/chef`, and `/cart`.

## Local preview

```bash
cd website
npx --yes serve -p 5173
```

Use `/meal.html?id=…`, `/chef.html?id=…`, `/cart.html`, `/auth.html`, `/checkout.html` when path rewrites are unavailable locally.
