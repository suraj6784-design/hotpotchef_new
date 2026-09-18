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

**P0/P1 code + live Edge deploys in this PR** (`db push` still not applied):

| Fix | Why |
| --- | --- |
| `create-split-order` sold-out now HTTP **400** | Inventory miss previously returned HTTP 200 + `success: false` (git only; live still v24) |
| `razorpay-webhook` v10 | Timing-safe HMAC; missing secret → **503** (was live 500); bad/missing sig → **401**; OPTIONS CORS; `place_customer_order` on `payment.captured` |
| `ai-craving-matcher` v11 | Flattened `index.ts` + empty `deno.json`; esm.sh only. Live v10 was **503 BOOT_ERROR** (nested import_map + `npm:@supabase/server` + duplicate `const supabaseUrl`) |
| `send-push-notification` v17 | Web Crypto FCM (no `npm:google-auth-library`); `verify_jwt=false`; OPTIONS **200**. User-reported v15 **503 BOOT_ERROR** |
| send-push duplicate identifier | Live log `Identifier 'auth' has already been declared` (`authorizeInternalInvoke` + `GoogleAuth` both named `auth`). Git binds `invokeAuth` + `session`; regression in `identifier_test.ts` |
| `push-notifier` v15 | Same flatten; `verify_jwt=false`; OPTIONS **200**. Live v13 nested import_map (booted but fragile) |
| `create-chef-account` chef-role gate | `authorizeChefAccount` + `users.role` (was uid-only; git only) |
| Checkout body locked to pending-checkout contract | Dropped stale `delivery_fee` / Route `chef_transfer` fields |
| Complete-delivery no longer falls back to `orders.update` | Direct write skipped PIN/POD when RPC returned false |
| Driver Start/Complete uses live `orders.status` | Button no longer invents Driver Assigned / Out for Delivery |
| OAuth `hotpotchef://app/auth` → `/auth` | Deep link was unmapped |
| Referral dock | Profile referral cell now `push('/referral')` |
| Guest profile login uses GoRouter `/auth` | Off-router `MaterialPageRoute` |
| Migration `20260918040000_messages_insert_own_sender.sql` | INSERT `sender_id = auth.uid()`; revoke anon `complete_delivery_order` |

Live `RAZORPAY_WEBHOOK_SECRET` is still **unset**. Fail-closed is correct; human must set the secret. Unsigned POST is now **503** `Webhook secret is not configured` (not 500).

---

## 2. Connection establishment (live smoke)

Evidence: `/opt/cursor/artifacts/flow_smoke.json` (REST/auth); `/opt/cursor/artifacts/live_matrix_after_redeploy.json` (Edge after v11/v17/v15/v10). Statuses only; no keys.

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
| Edge OPTIONS (most) | 200 | **200** | create-split-order, cancel-order, create-chef-account, ai-search, ops-cron, matcher v11, send-push v17, push-notifier v15, razorpay-webhook v10 |
| Edge POST no `Authorization` (`verify_jwt=true`) | 401 | **401** `UNAUTHORIZED_NO_AUTH_HEADER` | create-split-order, cancel-order, create-chef-account, release-chef-payout, matcher |
| Edge POST no auth (`verify_jwt=false` push) | 401 handler | **401** `Unauthorized` | send-push v17 / push-notifier v15 reach the function (gateway no longer 401s OPTIONS) |
| Edge POST publishable as Bearer | 401 | **401** `UNAUTHORIZED_INVALID_JWT_FORMAT` or handler Unauthorized | Not a user JWT; cannot mutate |
| `ai-search` POST `{}` + apikey only | 400/401 | **400** `Search prompt is required` | Handler reachable; prompt required |
| `ai-craving-matcher` v10 | boot | **503 BOOT_ERROR** (before) | Nested `deno.json` + `npm:@supabase/server` + duplicate `const supabaseUrl` |
| `ai-craving-matcher` v11 | 401 unauth | **OPTIONS 200 / POST 401** | Flattened; no BOOT_ERROR |
| `send-push-notification` v15 | boot | **503 BOOT_ERROR** (user smoke) | Log: `Identifier 'auth' has already been declared` (invoke `auth` + `GoogleAuth` `auth`); also import_map / google-auth-library |
| `send-push-notification` v17 | 401 unauth | **OPTIONS 200 / POST 401** | Web Crypto FCM; `verify_jwt=false` |
| `push-notifier` v13 | 401 | **401** (booted, nested map) | Same fragile layout as matcher v10 |
| `push-notifier` v15 | 401 unauth | **OPTIONS 200 / POST 401** | Flattened; `verify_jwt=false` |
| `razorpay-webhook` unsigned v8 | 401/503 | **500** secret missing | User smoke; fail-closed but wrong status |
| `razorpay-webhook` unsigned v10 | 503 | **503** secret missing | OPTIONS **200**; still needs human secret |
| `ops-cron` / `release-chef-payout` no secret | 401 | **401** Unauthorized | Internal secret required |
| Razorpay `GET /v1/orders` with KEY_ID only | 401 | **401** | Secret is server-only |
| FCM HTTP v1 unauth | 401 | **401** | Project `hotpotchef-c53fa` reachable |
| Play listing `com.hotpotchef.app` | 404 | **404** | Human store-listing gap |

SQL (service role, aggregates only): 48 meals (5 Available / 43 Archived); 0 embeddings; 2 chef kitchens open; 1 driver available; 76 orders; 19 users.

Live Edge versions after this audit’s redeploy:

| Function | Version | verify_jwt | Note |
| --- | --- | --- | --- |
| create-split-order | 24 | true | Git sold-out 400 not on this build |
| razorpay-webhook | 10 | false | OPTIONS 200; unsigned 503 |
| send-push-notification | 17 | false | OPTIONS 200; Web Crypto FCM |
| push-notifier | 15 | false | OPTIONS 200 |
| ai-craving-matcher | 11 | true | OPTIONS 200; was BOOT_ERROR v10 |
| ai-search | 17 | true | POST `{}` → 400 prompt required |
| create-chef-account | 7 | true | Git role gate not on this build |
| release-chef-payout | 5 | true | OPTIONS 401 at gateway |
| ops-cron | 4 | false | POST no secret → 401 |
| cancel-order | 4 | true | POST no JWT → 401 |

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
| `send-push-notification` / `push-notifier` | OPTIONS **200**; POST anon JWT **401** Unauthorized | `AlertService` / welcome drip / DB webhook → **send-push**; **push-notifier is the working fallback** if send-push fails to boot | table/record or welcome | Fail closed | HMAC, service_role, or party JWT; anon rejected | **OK** live + **FIX** identifier | `identifier_test.ts`; push-notifier 401 with publishable Bearer |
| `razorpay-webhook` | OPTIONS **200**; unsigned **503** | Razorpay events | `payment.captured` → `place_customer_order` | Missing secret 503; bad sig 401 | HMAC required | **GAP** set secret | live v10 body `Webhook secret is not configured` |
| `ai-craving-matcher` | OPTIONS **200**; POST 401 | Not called from Flutter (`ai-search` is) | Gemini embed + `match_meals` | 0 embeddings → empty | User JWT | **OK** live v11 | was BOOT_ERROR v10 |
| Chef packaging store | REST `packaging_inventory` stream | Hub overflow **Packaging supplies** → tab 8 / `?tab=supplies` | Supply request insert | Crashlytics + copy | Chef role | **OK** | `chef_hub.dart` + `packaging_store_screen.dart` |
| Chef ads / academy | GoRouter | Overflow → `/chef-advertise` `/chef-academy` | Boost edge `meal-boost` | Function errors | JWT chef | **STATIC** | `chef_boost_sheet.dart` |
| Ops helpers | `manage-helper-account` | Desk create helper | `{ action, ... }` | “Could not update helper” | Ops JWT | **STATIC** | `platform_ops_desk_tabs.dart` |
| Kitchen online switch | `chef_profiles` upsert | Hub switch / setup strip Go online | `is_open`; going live fires `AlertService.notifyKitchenLive` | Snackbar + revert switch | Own-row RLS | **STATIC** | `chef_hub.dart` `_toggleKitchenStatus` |
| Chef Confirm → Ready | `orders.update` via `OrderLifecycle.advanceKitchen` | Orders card **Advance**; packed-box camera gate | Title Case status; `dispatch_photo_url` | Prep-window hint; photo required | Own chef_id row | **STATIC** | `_advanceKitchen` + `order_lifecycle_test.dart` |
| Chef decline / diner cancel | `cancel-order` edge | Chef cancel button; diner “Cancel Full Order” | `{ order_id, reason }` | Refund copy until cooking/slot | JWT + actor | **OK** | `customer_orders_tab.dart` / `order_repository.dart` |
| Chat send | `messages.insert` + send-push | Chat composer | `{ meal_id, sender_id, content }` | Network snackbar | INSERT own sender **FIX** | **STATIC** + **FIX** | `in_app_chat_screen.dart` |
| Diner rate meal | `reviews` upsert/insert | Delivered sheet **Rate** | meal/order/chef ids | Silent catch on duplicate | JWT diner | **STATIC** | `meal_review_dialog.dart` |
| Reorder | Local cart merge | Delivered/cancelled **Reorder these meals** | Cart lines | Kitchen closed later at checkout | Same as cart | **STATIC** | `customer_orders_tab.dart` |
| Driver accept job | RPC `accept_delivery_order` | Open-job Accept | `p_order_id` | Race snackbar | Driver JWT | **STATIC** | `driver_dashboard_provider.dart` |
| Driver Start / Mark delivered | `orders.update` then `complete_delivery_order` | Gradient **Start Delivery** / **Mark Delivered** | Live `orders.status`; OTP + POD photo | Door photo required | **FIX** no complete bypass | **FIX** | `driver_hub.dart` + `order_complete_rpc_test.dart` |
| Driver navigate | Maps / Geolocator | Nav + external Maps icons | Dropoff vs kitchen | Maps key human gap | Location permission | **STATIC** | `driver_hub.dart` |
| Coins-only checkout | `place-coins-order` | Checkout when coins cover total | `{ cart_items, ... }` | JWT 401 | User JWT | **STATIC** | `checkout_screen.dart` |
| Membership flash | RPC `diner_flash_membership_offer` | Home banner / checkout add-on | plan_id + offer price | Ineligible silent | JWT diner | **STATIC** | `membership_flash_banner.dart` |
| Shared cart join | RPC `join_shared_cart` | Cart import / room code | `p_room_code` | Host-only pay | JWT | **STATIC** | `shared_cart_service.dart` |
| Daily streak | RPC `claim_daily_streak` | Home streak banner | `p_user_id` | Already-claimed | JWT | **STATIC** | `daily_streak_banner.dart` |
| Meal publish + AI tags | meals insert + `ai-tag-meal` | `/chef-publish-meal` Save | meal row; optional tags | AI skip on error | Own chef meals | **STATIC** | `chef_publish_meal_screen.dart` |
| Meal boost | `meal-boost` | Menu boost sheet | campaign create/confirm | Function error | Chef JWT | **STATIC** | `chef_boost_sheet.dart` |

---

## 4. Action-trigger log (missing / dead)

| Trigger | Finding | This PR |
| --- | --- | --- |
| `/referral` registered, unused | Loyalty cell copied code only | Tap → `/referral` |
| OAuth `hotpotchef://app/auth` | Not in `AppDeepLinks.locationFor` | Mapped to `/auth` |
| Guest profile “Go to Login” | `MaterialPageRoute(AuthScreen)` | `context.go('/auth')` |
| Cart not on dock | FAB / `?tab=cart` only | By design; noted |
| Partner browse-as-guest | Early return | By design |
| Promo-only inbox rows | `_openRow` → `alertOpenPath` returns null without order/meal/kyc | Remaining (marks read only) |
| Packaging store | Chef hub tab 8 / `?tab=supplies` (not a standalone GoRoute) | Wired; not dead |

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
| Razorpay webhook secret unset | Live **503** fail-closed (was 500 on v8) |
| Recovery | `recover-payment` + `CheckoutRetryBanner` |

---

## 7. Cross-flow integration (static + tests)

```
login/OTP/OAuth → resolveRole → ops seat? /platform-ops : role hub
guest cart → auth sheet → CartMerge → checkout JWT → create-split-order
  → Razorpay (KEY_ID client) → recover-payment and/or razorpay-webhook
chef Confirm/Ready (photo) → orders.update → AlertService + send-push
  (push-notifier is DB-webhook fallback if send-push BOOT_ERRORs)
diner cancel / chef decline → cancel-order
chat composer → messages.insert → notifyChat → send-push
driver Accept RPC → Start (status) → Mark delivered (PIN+POD RPC) → release-chef-payout
kitchen is_open → notifyKitchenLive → follower FCM
logout → FCM clear → diner /customer-hub or partner /auth
```

Covered by `cart_merge_test.dart`, `route_authz_test.dart`, `hub_role_integrity_test.dart`, `auth_recovery_referral_test.dart`, `deep_link_coordinator_test.dart`, live Edge matrix.

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

- Webhook HMAC timing-safe + **503** when secret unset (live v10).
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
| `ai-craving-matcher` unused by Flutter | Diner search uses `ai-search` + ILIKE fallback | Keep matcher for semantic RPC; 0 embeddings |
| `spatial_ref_sys` RLS off | PostGIS catalog; advisor noise | Do not enable blindly |
| Owner email allowlist in client RouteAuthz | Must stay in sync with `is_platform_ops()` | Server still gates the desk |

---

## 9. Human-only gaps

1. **Set and rotate `RAZORPAY_WEBHOOK_SECRET`** on the hosted function; confirm Razorpay dashboard webhook URL. Live unsigned POST is **503** until then.
2. **Deploy** remaining git-only edges (`create-split-order` sold-out 400, `create-chef-account` role gate) and **`db push`** `20260918040000_messages_insert_own_sender.sql`.
   Matcher / send-push / push-notifier / razorpay-webhook **already redeployed** (v11 / v17 / v15 / v10).
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

deno test --allow-env --allow-read supabase/functions/razorpay-webhook/signature_test.ts \
  supabase/functions/_shared/webhook_auth_test.ts \
  supabase/functions/_shared/fcm_test.ts \
  supabase/functions/send-push-notification/identifier_test.ts

node --test supabase/functions/create-chef-account/*.test.mjs
```
