# Audit remediation (2026-09-14)

Full write-up: [`E2E_MARKET_AUDIT_2026-09-14.md`](./E2E_MARKET_AUDIT_2026-09-14.md) (imported from PR #17).

This branch implements the **required Now + 2-week code changes**. Live RLS on `meals`/`orders` is applied separately via Supabase MCP; matching SQL is in `supabase/migrations/20260914120000_rls_lockdown_meals_orders.sql`. **Do not `db push` the reconstructed 202609131330–1333 table dumps onto live.**

## Still needs a human

| Item | Why |
|---|---|
| Rotate `x-ops-cron-secret` | Plaintext in `cron.job`; not rotatable from git |
| Chef Razorpay Route Link | Remaining chefs on `skipped_no_route_account` / `acc_mock_*` |
| Play / App Store listing | `com.hotpotchef.app` Play URL is HTTP 404; listing copy is out of scope |
| `RAZORPAY_WEBHOOK_SECRET` + Vault `edge_webhook_secret` | Set in dashboard / `supabase secrets set` then redeploy functions |
| `flutterfire configure` iOS | Copy `ios/Runner/GoogleService-Info.plist.example` after adding an iOS app in Firebase project `hotpotchef-c53fa` |
| `ops_release_stale_confirmed_holds(false)` | Dry-run default; review JSON then apply as service_role |
| GEMINI embedding backfill | Stub only: `supabase/jobs/embed_meals_backfill.stub.sh` |
| India region migrate / live Razorpay / production keystore | Explicitly out of scope |

## Migrations added (additive, titled)

| File | Purpose |
|---|---|
| `20260914120000_rls_lockdown_meals_orders.sql` | Drop USING(true) write policies; catalog column REVOKE from anon |
| `20260914120100_payout_on_delivered_orders.sql` | Payout trigger on `orders.status` delivered; drop meal-update spam |
| `20260914120200_match_meals_available_only.sql` | Vector search Available-only |
| `20260914120300_normalize_app_roles.sql` | Chef/Customer/Driver/Admin aliases |
| `20260914120400_ops_release_stale_inventory_holds.sql` | Dry-run RPC for stuck confirmed holds |
