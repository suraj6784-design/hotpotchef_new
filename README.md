# hotpotchef_new

A Flutter application for HotPotChef.

## Getting Started

This project is a starting point for a Flutter application.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/).

## Configuration

1. Copy `.env.example` to `.env` (`.env` is gitignored).
2. Fill in `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_MAPS_API_KEY`, and `RAZORPAY_KEY_ID` (Test key `rzp_test_...`). `RAZORPAY_KEY_SECRET` is server-only — see Razorpay Route below.
3. Optional: `PLAY_STORE_URL` / `APP_STORE_URL` when a real store listing exists. Leave them empty rather than pointing at the unpublished `com.hotpotchef.app` Play page (HTTP 404). The Android applicationId **and iOS bundle id** are `com.hotpotchef.app`. iOS display name is **HotPotChef**.

### iOS Firebase

There is no live `GoogleService-Info.plist` in git (do not invent an iOS app id). Template: `ios/Runner/GoogleService-Info.plist.example`. After adding an iOS app on Firebase project `hotpotchef-c53fa`:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=hotpotchef-c53fa --platforms=ios,android,web
```

Until that plist exists, `FirebaseBootstrap` uses native config lookup on iOS and reconstructed Dart options on Android/web (`lib/firebase_options.dart`).

Password-reset emails use `io.supabase.hotpotchef://reset-callback/`. That scheme is registered in Android / iOS / macOS. The app listens for the callback (and Supabase `passwordRecovery`) and opens `/reset-password`, then continues to the role hub.

## Admin desk

The in-app Admin desk is `/platform-ops` (`lib/screens/platform_ops_screen.dart`). `AppRole.admin` is a first-class role: `parseRole('admin')` is Admin (not Customer), and RouteAuthz sends everyone except Admin away from the desk.

**Do not offer Admin at signup.** Grant it in the database:

```sql
-- 1) public.users (what login reads)
update public.users
set role = 'Admin'
where email = 'operator@example.com';

-- 2) JWT user_metadata (what GoRouter reads until the next login sync)
-- After the next login, AuthRoleSync.ensureJwtRole writes metadata from users.role.
```

**Owner allowlist:** `suraj6784@gmail.com` is always treated as Admin, even if `users.role` or JWT still says Chef/Customer. Login writes `Admin` into both places.

Login also canonicalizes aliases: `Delivery Partner` / `Delivery` → Driver, `Food Lover` → Customer.

Privacy / Terms / FAQ / Cancellation / Contact are in-app screens (`/legal/...`) plus `website/*.html`. They are working drafts, not lawyer-reviewed DPDP notices.

KYC on the desk is chef-only for FSSAI + kitchen name. Drivers are scored on identity/payout fields only (no FSSAI in Missing / denominator).

### Ops RPCs not required to open the desk

The desk loads without live ops functions. Missing RPCs show a banner or fall back:

| RPC / table | Used for | If missing |
|---|---|---|
| `ops_transaction_snapshot` | Dashboard GMV | Banner; counts stay 0 |
| `ops_set_fssai_status` | Verify / reject FSSAI | Direct `users.fssai_verification_status` update |
| `platform_ops` / helper invites | Scoped helper seats | Owner/Admin role only on this branch |
| `chef_profiles.local_kitchen_name` | Chef KYC kitchen name | Kitchen name stays empty / missing |

Do not add those RPCs here — core schema is already on `main` via [PR #12](https://github.com/suraj6784-design/hotpotchef_new/pull/12). Coordinate there if you want the full ops console (packaging, brands, refunds, helpers).

Marketing cart links (`hotpotchef://app/cart` and `/app/cart`) use the same `app_links` listener so a warm start opens the cart tab. Custom schemes do not work on web; use `/app/cart` or `/reset-password` there.

Push: FCM tokens sync on login and clear on every role logout. Order-status → FCM is an in-repo trigger (`supabase/migrations/20260913133300_order_meal_push_webhooks.sql`) that POSTs to `send-push-notification`. It stays a no-op until Vault `edge_service_role_key` is set. See `supabase/README.md`.

Do not commit live secrets. `.env` is already listed in `.gitignore`.

### Google Maps API key

The app already reads `GOOGLE_MAPS_API_KEY` via `flutter_dotenv` for Places / Directions calls.

- **Android Maps SDK:** Gradle injects the same key into `AndroidManifest.xml` from, in order:
  1. the `GOOGLE_MAPS_API_KEY` environment variable
  2. `android/local.properties` (`GOOGLE_MAPS_API_KEY=...`)
  3. the project `.env` file
- **Web Maps JS:** `web/index.html` does **not** contain a live key. After `.env` loads, Flutter injects the Maps JavaScript API so the map widgets still work when a real key is supplied.
- **iOS:** `google_maps_flutter` still expects `GMSServices.provideAPIKey` in the iOS runner if you ship iOS maps. That is unchanged here.

Restrict keys in Google Cloud Console:

- Android: package name + SHA-1
- Web: HTTP referrers for your deployed origins

**Rotate any Maps key that was previously committed** in `web/index.html` or `AndroidManifest.xml`. Treat that key as public and create a restricted replacement.

## Razorpay Route (Test mode)

Chef payouts use Razorpay **Route linked accounts** in Test mode. Production activation is not required.

### What is real vs still blocked

| Piece | With Test keys (`rzp_test_` + secret) | Without keys |
| --- | --- | --- |
| `create-chef-account` | `POST /v2/accounts` (Route) + product/settlements, or `POST /v1/beta/accounts` if v2 is unavailable. Persists a real `acc_...` id. | Labeled mock only: `acc_mock_*`. UI says sandbox, not verified. |
| `create-split-order` / checkout | Parent Razorpay order is created. Route `transfers[]` are attached when the chef has a real `acc_*` (not `acc_mock_*`). `transfer_status` is `on_hold`. | Parent order cannot be created (`Payment gateway configuration missing`). |
| `release-chef-payout` | `PATCH /v1/transfers/:id` (`on_hold: 0`) after **order delivered**. Looks up `trf_` from the order if only `order_id` was stored. Catalog meal pause/archive does **not** trigger this. | Errors if a real transfer is pending. Skips `skipped_*` statuses. |

Skip reasons (still **not** silent `skipped_standard_mode` when Route is configured):

- `skipped_no_route_account` — chef has no `gateway_account_id`
- `skipped_mock_account` — chef still has `acc_mock_*`
- `skipped_transfer_too_small` — chef share below Razorpay’s ₹1 transfer minimum
- `skipped_standard_mode` — only if meal metadata is persisted without a transfer plan (should not happen on the keyed path)

Blocked without dashboard secrets / Route enablement (not something this repo can invent):

- Creating Test API keys and enabling **Route** on the Razorpay Test-mode dashboard
- Setting `RAZORPAY_KEY_ID` + `RAZORPAY_KEY_SECRET` as **Supabase secrets** for the edge functions
- Optional: KYC / settlement activation on the linked account if Razorpay Test mode asks for it
- Hosted `orders` delivered trigger that invokes `release-chef-payout` (`supabase/migrations/20260914120100_payout_on_delivered_orders.sql`)
- `RAZORPAY_WEBHOOK_SECRET` on the `razorpay-webhook` function (unsigned posts return HTTP 401)

Live (`rzp_live_`) keys are not required and are not the default. If they are set later, the UI labels the account as live instead of Test.

### Configure Test mode

1. Razorpay Dashboard → **Test mode** → Account & Settings → API Keys. Copy `rzp_test_...` and the secret.
2. Flutter `.env`: `RAZORPAY_KEY_ID=rzp_test_...` only. Do not ship `RAZORPAY_KEY_SECRET` in the app bundle.
3. Supabase secrets (edge functions):

```bash
supabase secrets set RAZORPAY_KEY_ID=rzp_test_...
supabase secrets set RAZORPAY_KEY_SECRET=...
```

4. Redeploy `create-chef-account`, `create-split-order`, `release-chef-payout`, and `razorpay-webhook`.
5. Razorpay Dashboard → Webhooks → add `https://<project>.supabase.co/functions/v1/razorpay-webhook` with a secret. Set the same value:

```bash
supabase secrets set RAZORPAY_WEBHOOK_SECRET=...
```

6. Chef Profile → bank details → **Link**. A real Test `acc_...` is stored on `users.gateway_account_id`. Mock chefs can tap Link again after keys are added.

Market-readiness audit (2026-09-14): [`docs/E2E_MARKET_AUDIT_2026-09-14.md`](docs/E2E_MARKET_AUDIT_2026-09-14.md). Remediation notes: [`docs/AUDIT_REMEDIATION_2026-09-14.md`](docs/AUDIT_REMEDIATION_2026-09-14.md).

Handler tests:

```bash
deno test supabase/functions/create-chef-account/handler_test.ts \
  supabase/functions/create-split-order/pricing_test.ts \
  supabase/functions/create-split-order/route_transfers_test.ts \
  supabase/functions/create-split-order/handler_test.ts \
  supabase/functions/release-chef-payout/handler_test.ts \
  supabase/functions/razorpay-webhook/signature_test.ts \
  supabase/functions/_shared/webhook_auth_test.ts
node --test supabase/functions/create-chef-account/*.test.mjs
```
