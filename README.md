# hotpotchef_new

A Flutter application for HotPotChef.

## Getting Started

This project is a starting point for a Flutter application.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/).

## Configuration

1. Copy `.env.example` to `.env` (`.env` is gitignored).
2. Fill in `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_MAPS_API_KEY`, and `RAZORPAY_KEY_ID` (Test key `rzp_test_...`). `RAZORPAY_KEY_SECRET` is server-only — see Razorpay Route below.
3. Optional: `PLAY_STORE_URL` / `APP_STORE_URL` when a real store listing exists. Leave them empty rather than pointing at the unpublished `com.hotpotchef.app` Play page (HTTP 404). The Android applicationId is still `com.hotpotchef.app` for installed-app intents (`hotpotchef://app/cart`).

Password-reset emails use `io.supabase.hotpotchef://reset-callback/`. That scheme is registered in Android / iOS / macOS.

Push: FCM tokens sync on login and clear on every role logout. Hosted `orders` webhook SQL is **not** in this repo, so edge functions cannot be claimed live until that webhook is exported.

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
| `release-chef-payout` | `PATCH /v1/transfers/:id` (`on_hold: 0`) after delivery. Looks up `trf_` from the order if the meal only stored `order_id`. | Errors if a real transfer is pending. Skips `skipped_*` statuses. |

Skip reasons (still **not** silent `skipped_standard_mode` when Route is configured):

- `skipped_no_route_account` — chef has no `gateway_account_id`
- `skipped_mock_account` — chef still has `acc_mock_*`
- `skipped_transfer_too_small` — chef share below Razorpay’s ₹1 transfer minimum
- `skipped_standard_mode` — only if meal metadata is persisted without a transfer plan (should not happen on the keyed path)

Blocked without dashboard secrets / Route enablement (not something this repo can invent):

- Creating Test API keys and enabling **Route** on the Razorpay Test-mode dashboard
- Setting `RAZORPAY_KEY_ID` + `RAZORPAY_KEY_SECRET` as **Supabase secrets** for the edge functions
- Optional: KYC / settlement activation on the linked account if Razorpay Test mode asks for it
- Hosted `orders` delivered webhook that invokes `release-chef-payout` (not exported in this repo)

Live (`rzp_live_`) keys are not required and are not the default. If they are set later, the UI labels the account as live instead of Test.

### Configure Test mode

1. Razorpay Dashboard → **Test mode** → Account & Settings → API Keys. Copy `rzp_test_...` and the secret.
2. Flutter `.env`: `RAZORPAY_KEY_ID=rzp_test_...` only. Do not ship `RAZORPAY_KEY_SECRET` in the app bundle.
3. Supabase secrets (edge functions):

```bash
supabase secrets set RAZORPAY_KEY_ID=rzp_test_...
supabase secrets set RAZORPAY_KEY_SECRET=...
```

4. Redeploy `create-chef-account`, `create-split-order`, and `release-chef-payout`.
5. Chef Profile → bank details → **Link**. A real Test `acc_...` is stored on `users.gateway_account_id`. Mock chefs can tap Link again after keys are added.

Handler tests:

```bash
deno test supabase/functions/create-chef-account/handler_test.ts \
  supabase/functions/create-split-order/pricing_test.ts \
  supabase/functions/create-split-order/route_transfers_test.ts \
  supabase/functions/create-split-order/handler_test.ts \
  supabase/functions/release-chef-payout/handler_test.ts
node --test supabase/functions/create-chef-account/*.test.mjs
```
