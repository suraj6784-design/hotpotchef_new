# HotPotChef Supabase schema

Migrations under `supabase/migrations/` recreate the RPCs and push triggers the Flutter app and Edge Functions call. They are written to apply to a **fresh** Supabase project (`supabase db push` / `supabase db reset`) and are idempotent enough to add missing columns on the linked hosted project `tpcykyaumvqtwhuiiomg`.

## What is in this folder

| File | Purpose |
|---|---|
| `migrations/20260913133000_core_tables_for_rpcs.sql` | `users`, `meals`, `orders`, `chef_profiles`, `user_gamification`, addresses, carts, holds, wallets, RLS, realtime |
| `migrations/20260913133100_rpc_cart_orders_streak.sql` | `calculate_cart_total`, `place_customer_order`, `cancel_and_restock_order`, `claim_daily_streak` (+ hold / packaging helpers) |
| `migrations/20260913133200_rpc_match_meals.sql` | `match_meals` (Gemini `text-embedding-004` / 768-d) |
| `migrations/20260913133300_order_meal_push_webhooks.sql` | `orders.status` → `send-push-notification`; **legacy** `meals.status` → `release-chef-payout` (superseded) |
| `migrations/20260914120000_rls_lockdown_meals_orders.sql` | Drop USING(true) meals/orders writes; hide payout/FSSAI columns from anon |
| `migrations/20260914120100_payout_on_delivered_orders.sql` | Payout webhook on **delivered orders**; drop meal-update spam |
| `migrations/20260914120200_match_meals_available_only.sql` | `match_meals` Available-only |
| `migrations/20260914120300_normalize_app_roles.sql` | Chef/Customer/Driver/Admin aliases |
| `migrations/20260914120400_ops_release_stale_inventory_holds.sql` | Dry-run RPC for stuck confirmed holds |
| `functions/` | Edge Functions (already in repo) |
| `config.toml` | Local CLI config (`project_id = hotpotchef_new`) |

**Do not `db push` the reconstructed 202609131330–1333 dumps onto the live project.** Apply the 20260914* files (or the matching MCP lockdown) only.

## How to apply

```bash
# 1. Install the CLI: https://supabase.com/docs/guides/local-development/cli/getting-started
supabase login
supabase link --project-ref tpcykyaumvqtwhuiiomg   # or a new empty project
supabase db push
```

Local:

```bash
supabase start
supabase db reset   # applies migrations + seed.sql
```

## Secrets that are still live-only

These are **not** in git. Migrations no-op HTTP calls until Vault is populated.

| Secret | Where | Used for |
|---|---|---|
| `edge_service_role_key` | `vault.create_secret('<service_role JWT>', 'edge_service_role_key')` | `Authorization: Bearer …` on trigger → Edge Function |
| `edge_webhook_secret` | `vault.create_secret('<random>', 'edge_webhook_secret')` | **Required** `X-Webhook-Secret` for `send-push-notification` / `release-chef-payout` (service_role bearer also accepted) |
| `RAZORPAY_WEBHOOK_SECRET` | Edge Function secrets (`supabase secrets set RAZORPAY_WEBHOOK_SECRET=...`) | HMAC for `razorpay-webhook`. Unsigned requests return **HTTP 401**. |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function secrets | Admin client inside functions |
| `FCM_SERVER_KEY` | Edge Function secrets | Legacy `push-notifier` |
| `FIREBASE_SERVICE_ACCOUNT` | Edge Function secrets | `send-push-notification` (FCM HTTP v1) |
| `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` | Edge Function secrets | `create-split-order`, `release-chef-payout` |
| `GEMINI_API_KEY` | Edge Function secrets | `ai-search`, `ai-craving-matcher`, `ai-tag-meal` |

After push, confirm Edge Functions are deployed:

```bash
supabase functions deploy send-push-notification
supabase functions deploy push-notifier
supabase functions deploy release-chef-payout
supabase functions deploy razorpay-webhook
supabase functions deploy create-split-order
supabase functions deploy ai-search
supabase functions deploy ai-craving-matcher
```

## Dumped vs reconstructed

Live dump was **not** possible here: the Cloud Agent env has no `SUPABASE_ACCESS_TOKEN`, no service-role key, and the committed anon key is a placeholder (hosted PostgREST returns 401).

SQL was reconstructed from:

1. Flutter / Edge call sites on `main` @ `e011912` (argument names + return shapes)
2. Prior migration files recovered from orphan git history on this repo (same project ref) — `place_customer_order`, `cancel_and_restock_order`, `claim_daily_streak`, packaging helpers, Vault-backed push trigger

`match_meals` had **no** historical SQL. It is a standard pgvector cosine match over `meals.embedding vector(768)`.

## Apply risks

- Hosted `orders.items` / `meals` column types may differ (text vs jsonb, extra NOT NULL). `CREATE TABLE IF NOT EXISTS` will not reshape existing tables; `ADD COLUMN IF NOT EXISTS` only adds missing names.
- `place_customer_order` is **authenticated + service_role**. A later fork locked it to service_role only; this repo's Checkout still calls it with the user JWT, so that lock is not applied.
- `meals.embedding` is unused until a backfill. `ai-search` already falls back to `ILIKE`.
- Push triggers silently skip if Vault `edge_service_role_key` is missing. Orders still write.
- Do not treat this as a byte-for-byte clone of production. Diff against a live `supabase db dump` before applying to the production ref.

## RPCs still unknown / out of scope

This repo's Flutter + `supabase/functions/` only call the five RPCs above (plus hold helpers used by `place_customer_order`). Admin-desk RPCs (`ops_*`), password recovery UI, and Razorpay Route are out of scope.
