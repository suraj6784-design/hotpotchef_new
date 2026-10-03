# HotPotChef

Home-kitchen marketplace: chefs publish meals on their schedule, customers browse as guests and sign in at checkout, and delivery partners only join when the chef offers **Delivery Partner**.

## Roles

| Role | Hub | What they do |
| --- | --- | --- |
| Customer | `/customer-hub` | Guest feed → cart → login at checkout (`place_customer_order`) → orders |
| Chef | `/chef-hub` | Publish meals with date/day/daily slots and fulfillment options; kitchen → Ready for Pickup → dispatch |
| Driver | `/driver-hub` | Accept **Delivery Partner** jobs → Out for Delivery → Delivered |

Logout always clears the FCM token, signs out of Supabase, and returns to `/auth`.

## Time slots & fulfillment

Chefs set availability as **Daily**, **specific days**, or a **one-time date**, plus a start/end window. Customers pick a sub-slot inside that window.

Delivery options: Chef-Self, Delivery Partner, Customer Pickup, Dine In.

## Run

Configure `.env` with `SUPABASE_URL` and `SUPABASE_ANON_KEY`, then:

```bash
# --flavor selects the Android product flavor *and* the Dart storefront
# (FLUTTER_APP_FLAVOR + Gradle-injected APP_FLAVOR). Do not omit --flavor on
# Partner; a flavor-less build defaults to diner even if you install the
# com.hotpotchef.partner APK from an older artifact.
flutter run --flavor diner --dart-define-from-file=.env
flutter run --flavor partner --dart-define-from-file=.env
```

iOS has a single `Runner` scheme (no diner/partner Xcode flavors). `--flavor`
is Android-only until matching iOS schemes exist.

Verify Partner compiles as Partner (must not skip):

```bash
flutter test test/app_flavor_partner_compile_test.dart --flavor partner
cd android && ./gradlew :app:assertStorefrontFlavorDefines
```

Release APKs (diner **HotPotChef** + partner **HotPotChef Partner**; Razorpay keys stay from `.env`):

```bash
# Windows: powershell -File tool/build_release_apk.ps1
# macOS/Linux:
bash tool/build_release_apk.sh
```

Local `.env` is also read at startup if present. Do not list `.env` as a Flutter asset — that would ship secrets in the APK.

## Configuration

1. Copy `.env.example` to `.env` (`.env` is gitignored).
2. Fill in `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_MAPS_API_KEY`, and `RAZORPAY_KEY_ID` (Test key `rzp_test_...`). `RAZORPAY_KEY_SECRET` is server-only — see Razorpay Route below.
3. Optional: `PLAY_STORE_URL` / `APP_STORE_URL` when a real store listing exists. Leave them empty rather than pointing at the unpublished `com.hotpotchef.app` Play page (HTTP 404). The diner Android applicationId is `com.hotpotchef.app`; the partner flavor is `com.hotpotchef.partner`. iOS display name is **HotPotChef**.

### iOS Firebase

There is no live `GoogleService-Info.plist` in git (do not invent an iOS app id). Template: `ios/Runner/GoogleService-Info.plist.example`. After adding an iOS app on Firebase project `hotpotchef-c53fa`:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=hotpotchef-c53fa --platforms=ios,android,web
```

Until that plist exists, `FirebaseBootstrap` uses native config lookup on iOS and reconstructed Dart options on Android/web (`lib/firebase_options.dart`).

Password-reset emails use `io.supabase.hotpotchef://reset-callback/`. That scheme is registered in Android / iOS / macOS. The app listens for the callback (and Supabase `passwordRecovery`) and opens `/reset-password`, then continues to the role hub.

## Admin desk

The in-app Admin desk is `/platform-ops` (`lib/screens/platform_ops_screen.dart`). `AppRole.admin` is a first-class role. Do not offer Admin at signup; grant it in the database. Owner allowlist: `suraj6784@gmail.com` is always treated as Admin.

Privacy / Terms / FAQ / Cancellation / Contact are in-app screens (`/legal/...`) plus `website/*.html`. Cream storefront copy is the richer in-app text; audit drafts remain available via `LegalDocuments`.

KYC on the desk is chef-only for FSSAI + kitchen pin. Drivers are scored on identity/vehicle/payout fields only (no FSSAI).

Marketing cart links (`hotpotchef://app/cart` and `/app/cart`) use the same `app_links` listener. Custom schemes do not work on web; use `/app/cart` or `/reset-password` there.

Push: FCM tokens sync on login and clear on every role logout. Order-status → FCM uses cream's alert dispatcher plus audit webhook HMAC (`X-Webhook-Secret` or service role). See `supabase/README.md`.

Do not commit live secrets. `.env` is already listed in `.gitignore`.

### Google Maps API key

The app already reads `GOOGLE_MAPS_API_KEY` via `flutter_dotenv` / `--dart-define`.

- **Android Maps SDK:** Gradle injects the same key into `AndroidManifest.xml`.
- **Web Maps JS:** `web/index.html` does **not** contain a live key. After env loads, Flutter injects the Maps JavaScript API.
- **iOS:** `google_maps_flutter` still expects `GMSServices.provideAPIKey` in the iOS runner if you ship iOS maps.

Restrict keys in Google Cloud Console. **Rotate any Maps key that was previously committed.**

## Razorpay Route (Test mode)

Chef payouts use Razorpay **Route linked accounts** in Test mode. Production activation is not required.

`RAZORPAY_WEBHOOK_SECRET` is required on `razorpay-webhook` (unsigned posts return HTTP 400/401). Payouts release after **order delivered** (`supabase/migrations/20260914120100_payout_on_delivered_orders.sql`).

Market-readiness audit (2026-09-14): [`docs/E2E_MARKET_AUDIT_2026-09-14.md`](docs/E2E_MARKET_AUDIT_2026-09-14.md). Remediation notes: [`docs/AUDIT_REMEDIATION_2026-09-14.md`](docs/AUDIT_REMEDIATION_2026-09-14.md).

Handler tests:

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
deno test supabase/functions/_shared/order_status_test.ts \
  supabase/functions/_shared/webhook_auth_test.ts \
  supabase/functions/_shared/meal_catalog_test.ts \
  supabase/functions/_shared/app_role_test.ts \
  supabase/functions/razorpay-webhook/signature_test.ts \
  supabase/functions/release-chef-payout/handler_test.ts \
  supabase/functions/create-split-order/pricing_test.ts \
  supabase/functions/create-split-order/route_transfers_test.ts \
  supabase/functions/create-split-order/handler_test.ts \
  supabase/functions/create-chef-account/handler_test.ts
node --test supabase/functions/create-chef-account/*.test.mjs
```
