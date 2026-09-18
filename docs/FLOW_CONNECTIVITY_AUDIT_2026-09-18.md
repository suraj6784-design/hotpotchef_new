# Flow connectivity audit — 2026-09-18

**Repo:** hotpotchef_new  
**Base:** `main` @ `90b6785` (cream storefront + audit security)  
**Live Supabase:** `tpcykyaumvqtwhuiiomg` · `ap-northeast-1` · Postgres 17.6 · `ACTIVE_HEALTHY`  
**Auditor:** Cloud Agent on branch `cursor/flow-connectivity-audit-fbfe`  
**Constraint:** no secrets/PII printed; no live paid charges; no security weakening to make tests pass.

Guest REST used the gitignored `.env` **publishable** anon key (`sb_publishable_…`). A dummy `SUPABASE_ANON_KEY` in the agent process environment is **not** the live key and was ignored.

---

## 1. Executive verdict

Guest catalog, kitchen-open flags, mutating-edge JWT gates, Razorpay KEY_ID-only 401, FCM unauth 401, and Play listing 404 were **live-smoked**. Chef/driver/admin hubs were validated by **static contract + unit tests** (no role sessions in this environment).

**P0/P1 code fixes in this PR** (not yet deployed to hosted Edge / not yet `db push`):

| Fix | Why |
| --- | --- |
| `create-split-order` sold-out now HTTP **400** | Inventory miss previously returned HTTP 200 + `success: false` |
| `razorpay-webhook` uses `verifyRazorpaySignature` | Timing-safe HMAC; missing secret / bad sig → **401** (not 500/400); OPTIONS CORS |
| `create-chef-account` chef-role gate | `authorizeChefAccount` + `users.role` (was uid-only) |
| Checkout body locked to pending-checkout contract | Dropped stale `delivery_fee` / Route `chef_transfer` fields |
| Complete-delivery no longer falls back to `orders.update` | Direct write skipped PIN/POD when RPC returned false |
| Driver Start/Complete uses live `orders.status` | Button no longer invents Driver Assigned / Out for Delivery |
| OAuth `hotpotchef://app/auth` → `/auth` | Deep link was unmapped |
| Referral dock | Profile referral cell now `push('/referral')` |
| Guest profile login uses GoRouter `/auth` | Off-router `MaterialPageRoute` |
| Migration `20260918040000_messages_insert_own_sender.sql` | INSERT `sender_id = auth.uid()`; revoke anon `complete_delivery_order` |

**Do not treat this PR as deployed.** Hosted functions still run the previous builds until `supabase functions deploy`. Live `RAZORPAY_WEBHOOK_SECRET` is **unset** (unsigned POST → HTTP 500 `Webhook secret is not configured`).

---

## 2. Connection establishment (live smoke)

Evidence: `/opt/cursor/artifacts/flow_smoke.json` (statuses only; no keys).

| Surface | Expected | Live | Evidence |
| --- | --- | --- | --- |
| REST `GET /meals?status=eq.Available` | 200 | **200** | Veg Biryani / Gulab Jamun rows |
| REST archived meals | 200 + `[]` | **200 `[]`** | RLS `meals_select_available_or_own` |
| REST `PATCH meals` anon | 4xx | **401** `42501` permission denied | Grant UPDATE not given to anon |
| REST `POST orders` anon | 4xx | **401** `42501` | Grant INSERT not given to anon |
| REST `GET users` bank/PAN anon | 4xx | **401** `42501` | Anon cannot SELECT `users` |
| REST `GET chef_profiles` `is_open` | 200 | **200** | 2 kitchens `is_open=true`, `is_live=false` |
| RPC `place_customer_order` anon | 4xx / not executable | **401** | `auth.role() = service_role` in function |
| RPC `calculate_cart_total` | 200 with `p_items` | Smoke used wrong `p_cart_items` → 404; **client uses `p_items`** | Flutter `checkout_screen.dart` matches live args `p_items jsonb, p_user_id uuid` |
| Auth settings | 200 | **200** (with publishable key) | Dummy env key 401s |
| Realtime WS via GET | upgrade 4xx | **500** Cloudflare 1101 | HTTP GET is not a WebSocket upgrade; client plugin still used in-app |
| Edge OPTIONS (most) | 200 | **200** | create-split-order, cancel-order, create-chef-account, recover-payment, ai-search, place-coins-order, ops-cron |
| Edge POST no `Authorization` (`verify_jwt=true`) | 401 | **401** `UNAUTHORIZED_NO_AUTH_HEADER` | create-split-order, cancel-order, recover-payment, release-chef-payout, create-chef-account |
| Edge POST publishable as Bearer | 401 | **401** `UNAUTHORIZED_INVALID_JWT_FORMAT` | Not a user JWT; cannot mutate |
| `ai-search` POST `{}` + apikey only | 400/401 | **400** `Search prompt is required` | Handler reachable; prompt required |
| `razorpay-webhook` unsigned | 400/401 | **500** secret missing | **Human: set `RAZORPAY_WEBHOOK_SECRET`** |
| `razorpay-webhook` OPTIONS | 200 | **500** (live handler has no OPTIONS) | Fixed in this PR |
| `send-push-notification` / `push-notifier` OPTIONS | 200 | **401** | Live `verify_jwt=true`; git `config.toml` is `false` |
| `ops-cron` no JWT | 401 | **401** | Internal secret required |
| Razorpay `GET /v1/orders` with KEY_ID only | 401 | **401** | Secret is server-only |
| FCM HTTP v1 unauth | 401 | **401** | Project `hotpotchef-c53fa` reachable |
| Play listing `com.hotpotchef.app` | 404 | **404** | Human store-listing gap |

SQL (service role, aggregates only): 48 meals (5 Available / 43 Archived); 0 embeddings; 2 chef kitchens open; 1 driver available; 76 orders; 19 users.

---

## 3. Flow matrix

Legend: **OK** live or tests pass · **FIX** patched in this PR · **GAP** human/deploy remaining · **STATIC** code+tests only.

| Flow | Connection | Trigger | Data | Errors | Security | Status | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Guest feed / search / Live·Pre-order·Healthy | REST meals 200; `ai-search` JWT 401 then local fallback | Home chips → `mealMatchesHomeMode`; search → `ai-search` if signed in | Catalog Available-only RLS | Offline banner + network copy | Anon cannot PATCH meals | **OK** | smoke + `customer_feed_tab.dart` |
| Guest cart → login merge → checkout | Cart local; checkout edges 401 without user JWT | FAB / `?tab=cart`; guest checkout → auth sheet | `CartMerge.merge` snake/camel via `checkoutCartPayload` | Kitchen closed / sold-out copy | Checkout JWT required | **OK** | `cart_merge_test.dart`, smoke 401 |
| Signup / login / OTP / OAuth | Auth settings 200 | Email+password; diner OTP; Google/Apple | `users` upsert; role metadata | `friendlyAuthError` | JWT session | **OK** / OAuth **FIX** | `auth_screen.dart`; `hotpotchef://app/auth` now routed |
| Password reset deep link | GoTrue + `io.supabase.hotpotchef://reset-callback/` | Forgot password → `/reset-password` | `updateUser(password)` | Invalid password copy | Recovery session kept by router | **OK** | `app_deep_links_test.dart`, `reset_password_screen_test.dart` |
| Role routing Customer/Chef/Driver/Admin | n/a | `AuthSession.goToHub` / `ensureHubRole` | `users.role` over JWT; owner email → Admin | Wrong APK → `/wrong-app` | `RouteAuthz` + router redirect | **OK** | `route_authz_test.dart`, `hub_role_integrity_test.dart` |
| Logout + FCM clear | FCM project 401 unauth | Hub/profile confirm | `clearTokenOnLogout` then `signOut` | Crashlytics on failure | Token nulled before signOut | **OK** | `auth_session.dart` |
| Customer orders / track / chat / inbox | Realtime in-app; orders RLS participants | Orders tab → `/tracking` → `chatPath`; FCM `alertOpenPath` | Order status Title Case | PIN/POD messages | Chat INSERT **FIX** (migration) | **STATIC** + **FIX** | `order_lifecycle_test.dart`; messages SELECT still USING true |
| Checkout `create-split-order` | Live 401 no JWT | Place order | Pending checkout + holds; **FIX** contract | **FIX** parse 400 sold-out / kitchen / 401 | JWT + rate limit | **FIX** | `create_split_order_contract_test.dart` |
| `recover-payment` | Live 401 no JWT | Post-pay + retry banner | payment_id + signature | Refund copy | User JWT + checkout HMAC | **OK** | `checkout_retry_banner.dart` |
| `cancel-order` | Live 401 no JWT | Chef decline / diner cancel | `order_id`, `reason` | FunctionException mapped | JWT + RPC actor check | **OK** | `order_repository.dart` |
| Chef `is_open` toggle | `chef_profiles` SELECT 200 | Hub kitchen switch | `is_open` / `is_live` upsert own row | Snackbar | RLS write own uid | **STATIC** | `chef_hub.dart`; live 2 kitchens open |
| Chef publish / accept / ready | meals RLS own chef | `/chef-publish-meal`; `_advanceKitchen` | meals + `OrderLifecycle` | Packed photo required | Own-row meals | **STATIC** | `order_lifecycle_test.dart` |
| Chef payout `create-chef-account` | Live 401 no JWT | Profile payout form | snake bank fields | IFSC validation | **FIX** chef role + uid match | **FIX** | `authorize.test.mjs` + `index.ts` |
| `release-chef-payout` | Live 401 no JWT; OPTIONS 401 at gateway | After delivered | `{ order_id }` | Crashlytics swallow | Chef/driver or internal | **OK** / OPTIONS **GAP** | live verify_jwt |
| Driver `is_available` | 1 driver available (SQL) | Online toggle | `driver_profiles` own row | Offline snackbar | Role-gated write | **STATIC** | SQL count + `driver_hub.dart` |
| Driver jobs realtime / navigate / complete | Realtime channel in code | Accept / Maps / Mark delivered | **FIX** live status; OTP+POD RPC | Door photo required | **FIX** no direct complete | **FIX** | `order_complete_rpc_test.dart` |
| Admin `/platform-ops` | n/a | Login ops seat; invite `/ops-invite` | `platform_ops` row | “Ops access required” | JWT Admin ≠ desk | **STATIC** | `platform_ops_access.dart` |
| `send-push-notification` / `push-notifier` | OPTIONS 401 live; POST no JWT 401 | Order status / chat / welcome | table/record or welcome | Fail closed | HMAC or service_role; anon rejected | **GAP** deploy `verify_jwt=false` | `webhook_auth_test.ts` + live |
| `razorpay-webhook` | **500 secret missing** | Razorpay events | `payment.captured` → `place_customer_order` | **FIX** 401 HMAC locally | HMAC required | **GAP** set secret + deploy | live body `Webhook secret is not configured` |

---

## 4. Action-trigger log (missing / dead)

| Trigger | Finding | This PR |
| --- | --- | --- |
| `/referral` registered, unused | Loyalty cell copied code only | Tap → `/referral` |
| OAuth `hotpotchef://app/auth` | Not in `AppDeepLinks.locationFor` | Mapped to `/auth` |
| Guest profile “Go to Login” | `MaterialPageRoute(AuthScreen)` | `context.go('/auth')` |
| Cart not on dock | FAB / `?tab=cart` only | By design; noted |
| Partner browse-as-guest | Early return | By design |
| Promo-only inbox rows | `_openRow` no-op if no path | Remaining |
| Packaging store | Embed-only, no GoRoute | Remaining |

---

## 5. Data-flow / JSON contracts

- Checkout wire format is **snake_case** (`cart_items`, `dropoff_lat`, `apply_coins`). Cart models are camelCase; `checkoutCartPayload` / `quotePaidCheckout` accept both.
- Deployed `create-split-order/index.ts` is **pending_checkouts + Razorpay order**, not Route transfers at create time. `CreateSplitOrderRequest` now matches checkout + `index.ts`.
- `handler.ts` / `handler_test.ts` still describe the legacy Route-at-checkout path — not the `config.toml` entrypoint.
- Live `calculate_cart_total(p_items, p_user_id)` matches Flutter. Smoke 404 was a wrong parameter name.
- Phone-only emails: `resolveCustomerEmail` avoids `user.email!`.

---

## 6. Error handling

| Case | Behavior |
| --- | --- |
| Invalid input | Auth validators; IFSC regex; checkout slot/kitchen/promo |
| Sold-out / kitchen closed | Server `code` + diner copy; **FIX** HTTP 400 + parse non-200 body |
| Offline / timeout | `NetworkTimeouts`, `OfflineBannerHost`, retry queue |
| Auth 401 | “Please sign in to continue.” |
| Recovery | `recover-payment` + `CheckoutRetryBanner` |

---

## 7. Cross-flow integration (static + tests)

```
login/OTP/OAuth → resolveRole → ops seat? /platform-ops : role hub
guest cart → auth sheet → CartMerge → checkout JWT
order → tracking → chatPath → inbox/FCM alertOpenPath
chef is_open / driver is_available → feed + job pool
logout → FCM clear → diner /customer-hub or partner /auth
```

Covered by `cart_merge_test.dart`, `route_authz_test.dart`, `hub_role_integrity_test.dart`, `auth_recovery_referral_test.dart`, `deep_link_coordinator_test.dart`.

---

## 8. Security & privacy

**Still good (live):**

- Meals/orders writes are not `USING (true)` for anon.
- Anon cannot SELECT `users` or UPDATE `meals`.
- `place_customer_order` requires `service_role`.
- Mutating edges (`verify_jwt=true`) reject missing JWT (401).
- Internal push helper rejects anon JWT (`webhook_auth_test.ts`).
- RouteAuthz + GoRouter role hubs.

**Fixed in git (apply/deploy to take effect):**

- Webhook HMAC timing-safe + 401 contract.
- Chef payout role gate.
- Chat INSERT own `sender_id`.
- Revoke anon EXECUTE on `complete_delivery_order`.
- No client complete-delivery bypass.

**Remaining (do not “fix” by opening RLS):**

| Item | Risk | Action |
| --- | --- | --- |
| `messages` SELECT USING `(true)` | Any signed-in user can read all chats | Needs room-membership policy; not applied live (could break group/bulk rooms) |
| `users` SELECT USING `(true)` for authenticated + column SELECT on bank/PAN/Aadhaar | Signed-in diner can read other users’ KYC columns | Split KYC table or column-secure view; chef/driver profile still `select()` own row |
| Live `RAZORPAY_WEBHOOK_SECRET` unset | Captures never record via webhook; recover-payment is the only path | `supabase secrets set RAZORPAY_WEBHOOK_SECRET=…` |
| Live `send-push-notification` / `push-notifier` `verify_jwt=true` vs git `false` | OPTIONS 401; DB webhook must send a JWT | Redeploy with git `config.toml` |
| `spatial_ref_sys` RLS off | PostGIS catalog; advisor noise | Do not enable blindly |
| Owner email allowlist in client RouteAuthz | Must stay in sync with `is_platform_ops()` | Server still gates the desk |

---

## 9. Human-only gaps

1. **Set and rotate `RAZORPAY_WEBHOOK_SECRET`** on the hosted function; confirm Razorpay dashboard webhook URL.
2. **Deploy** this PR’s edge functions (`create-split-order`, `razorpay-webhook`, `create-chef-account`) and **`db push`** `20260918040000_messages_insert_own_sender.sql`.
3. **Maps:** `GOOGLE_MAPS_API_KEY` is present in `.env`; restrict in Cloud Console; iOS still needs `GMSServices.provideAPIKey`. Rotate if the key was ever committed.
4. **Store listings:** Play `com.hotpotchef.app` HTTP 404; `PLAY_STORE_URL` / `APP_STORE_URL` empty.
5. **iOS Firebase:** no live `GoogleService-Info.plist`.
6. **FCM send path:** needs `FIREBASE_SERVICE_ACCOUNT` + Vault `edge_service_role_key` / `edge_webhook_secret` (not verified here).
7. **Logged-in chef/driver/admin UI** and a Test-mode Razorpay charge were not run (no role passwords; no paid probe).
8. **0 meal embeddings** — `match_meals` / semantic `ai-search` stay ILIKE fallback.
9. **Tokyo region** for an India marketplace (latency / data-residency product decision).

---

## 10. How to re-run

```bash
# Uses gitignored .env publishable key; do not export a dummy SUPABASE_ANON_KEY.
python3 /tmp/hpc_flow_smoke.py   # or the copy under tool/ if added later

flutter test test/create_split_order_contract_test.dart \
  test/order_complete_rpc_test.dart \
  test/order_lifecycle_test.dart \
  test/app_deep_links_test.dart \
  test/cart_merge_test.dart \
  test/route_authz_test.dart

deno test supabase/functions/razorpay-webhook/signature_test.ts \
  supabase/functions/_shared/webhook_auth_test.ts

node --test supabase/functions/create-chef-account/*.test.mjs
```
