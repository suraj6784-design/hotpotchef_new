# hotpotchef_new

A Flutter application for HotPotChef.

## Getting Started

This project is a starting point for a Flutter application.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/).

## Configuration

1. Copy `.env.example` to `.env` (`.env` is gitignored).
2. Fill in `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_MAPS_API_KEY`, and `RAZORPAY_KEY_ID`.
3. Optional: `PLAY_STORE_URL` / `APP_STORE_URL` when a real store listing exists. Leave them empty rather than pointing at the unpublished `com.hotpotchef.app` Play page (HTTP 404). The Android applicationId is still `com.hotpotchef.app` for installed-app intents (`hotpotchef://app/cart`).

Password-reset emails use `io.supabase.hotpotchef://reset-callback/`. That scheme is registered in Android / iOS / macOS.

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

KYC on the desk is chef-only for FSSAI + kitchen name. Drivers are scored on identity/payout fields only (no FSSAI in Missing / denominator).

### Ops RPCs not required to open the desk

The desk loads without live ops functions. Missing RPCs show a banner or fall back:

| RPC / table | Used for | If missing |
|---|---|---|
| `ops_transaction_snapshot` | Dashboard GMV | Banner; counts stay 0 |
| `ops_set_fssai_status` | Verify / reject FSSAI | Direct `users.fssai_verification_status` update |
| `platform_ops` / helper invites | Scoped helper seats | Owner/Admin role only on this branch |
| `chef_profiles.local_kitchen_name` | Chef KYC kitchen name | Kitchen name stays empty / missing |

Do not add those RPCs here if [PR #12](https://github.com/suraj6784-design/hotpotchef_new/pull/12) is already exporting core schema. Coordinate there if you want the full ops console (packaging, brands, refunds, helpers).

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
