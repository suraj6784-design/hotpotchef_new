# HotPotChef 360° E2E Market-Readiness Audit

**Repo:** https://github.com/suraj6784-design/hotpotchef_new  
**Base reviewed:** `main` @ `2c99808` (merge of PR #16; includes PRs #11–#16)  
**Live Supabase:** `tpcykyaumvqtwhuiiomg` · region `ap-northeast-1` (Tokyo) · Postgres `17.6.1` · status `ACTIVE_HEALTHY`  
**Audit date:** 2026-09-14  
**Auditor posture:** senior Android/iOS/web architect + product auditor  
**Constraint honored:** no paid live charges; Test-mode probes only; no production row mutations with real IDs

---

## 1. Executive verdict

**Market ready for a public India launch? No.**  
**Ready for closed Test-mode dogfood on Android? Yes, with security caveats.**

The product is a real three-sided marketplace (customer / chef / driver) plus an Admin desk, with a working Test Razorpay split-order path, guest browse/cart, password recovery, FCM order-status pushes, and FSSAI columns/triggers. That is further along than a typical prototype.

It is **not** production-grade for a public food marketplace. Live RLS still allows anonymous `PATCH` on `meals` and `orders`. Catalog rows expose chef payout math and FSSAI numbers to the anon key. A `SECURITY DEFINER` view returns account emails to anon. Seventy-three privileged RPCs are executable by `anon`. iOS is not store-shaped (`com.example.hotpotchefNew`, no `GoogleService-Info.plist`). Play listing `com.hotpotchef.app` is HTTP 404. Privacy/Terms in the app are placeholder snacks. The git repo exports 4 reconstructed migrations and 8 edge functions; live has ~80 applied migrations and 17 functions. Vector search is inert (`0/47` meal embeddings). Region is Tokyo for an India product.

**Overall score: 2.5 / 5.**  
**Confidence: High** on backend/security/payments (live SQL + HTTP + 24h function logs + 120 Flutter tests). **Medium** on chef/driver/admin UX (code + schema; those hubs were not logged-in in this session). **N/A** for native iOS/Android device-farm and live Razorpay settlement KYC.

| Gate | Verdict |
|---|---|
| Guest feed + cart + auth-gated checkout (Flutter web) | **Pass** |
| `create-split-order` without user JWT | **Pass** (HTTP 401) |
| `create-split-order` with user JWT (24h logs) | **Pass** (7 × HTTP 200, Test mode) |
| Public catalog / PII / write RLS | **Fail** |
| Store listing + iOS Firebase + release signing | **Fail** |
| AI semantic search | **Fail** (no embeddings; craving matcher HTTP 503) |
| FSSAI ops data model | **Partial** (2 verified chefs; 17 unsubmitted users) |
| CI/CD + rollback | **Fail** (no GitHub Actions) |

---

## 2. Scorecard (1–5)

| # | Section | Score | Rationale |
|---|---|---:|---|
| 1 | Technical audit | **3** | Coherent Flutter + Supabase + Edge stack; indexes and realtime exist; repo≠live drift, no CI, debug release signing, Tokyo region. |
| 2 | Functional validation | **3** | Core guest→cart→auth gate works; Test checkout and FCM fire in logs; many live tables/RPCs are not in this Flutter tree; search leaks non-Available meals. |
| 3 | UI/UX | **3** | Material 3 diner hub is usable on web; empty states and auth gates are clear; 0 `Semantics`; legal links are stubs; web pay blocked; marketing `website/` is a fragment. |
| 4 | AI / interactive layer | **2** | `ai-search` / `ai-tag-meal` deploy and 200; 0 embeddings; `ai-craving-matcher` 503; in-app “AI recommendations” are category-frequency heuristics. |
| 5 | Market readiness | **2** | Feature ideas approach local-food startups, not Swiggy/Zomato parity; FSSAI is modeled but weakly enforced at the API; no public store; DPDP/privacy gap. |
| 6 | Transformation posture | **2** | Live already has ops RPCs, cron, coins, disputes — but this `main` client is a thin slice; no observability product, no multi-region plan. |
| — | **Weighted overall** | **2.5** | Ship as private Test beta; do not open the marketplace. |

Judgment labels used below: **Pass / Partial / Fail / Blocked / N/A**.

---

## 3. Section 1 — Technical audit

### 3.1 Architecture, modularity, maintainability — **Partial**

**Flutter (`lib/`):** 73 Dart files, screen-centric (not feature-sliced). Heaviest screens: `customer_orders_tab.dart` (~1248 LOC), `customer_feed_tab.dart` (~986), `customer_profile_screen.dart` (~929), `checkout_screen.dart` (~832). Riverpod is used for cart/favorites/driver dashboard only. Pure logic that is tested (`route_authz.dart`, `cart_merge.dart`, `order_status.dart`, `create_split_order_contract.dart`) is the maintainable core.

**GoRouter:** hubs and profiles are registered; checkout, addresses, referral, bulk request, packaging store are `Navigator.push` only. No `refreshListenable` on auth session change.

**Supabase live vs git:**

| Surface | In git `main` | Live project |
|---|---|---|
| SQL migrations | 4 reconstructed files under `supabase/migrations/` | 80+ applied versions (2026-09-02 through 2026-09-14) |
| Edge functions | 8 directories | 17 ACTIVE functions |
| Public tables | 11 in reconstructed SQL | 44 (`spatial_ref_sys` RLS off) |

Live functions **not** in this repo: `recover-payment`, `cancel-order`, `razorpay-webhook`, `meal-boost`, `retry-failed-refunds`, `set-ad-campaign-status`, `manage-helper-account`, `ops-cron`, `place-coins-order`.

This is the single largest maintainability risk: **the hosted system of record is not reproducible from `main`**. `supabase/README.md` already warns the SQL is reconstructed, not dumped.

**Dead / unused in client:** `local_auth` and `flutter_secure_storage` in `pubspec.yaml` with no `lib/` imports; `skeleton_loaders.dart` unused; `flutter_screenutil` wrapped in `main.dart` but no `.w/.h/.sp` usage.

### 3.2 Backend performance signals — **Partial** (measured)

What was measured (not invented):

- Table live tuples (`pg_stat_user_tables`): `meals` 47, `orders` 76, `users` 19, `inventory_holds` 40 live + 40 dead, `carts` 0.
- `inventory_holds.status`: 37 `confirmed`, 3 `released` — holds are accumulating.
- Indexes: present on `orders` (`idempotency_key` unique, `payment_id` unique, chef/status/driver) and `meals` (chef, status, available/created, boosts, hampers). **No `meals.embedding` IVFFlat/HNSW in live index list** (repo migration would add one; live has none because embeddings are unused).
- Advisor **performance** (2026-09-14): `unindexed_foreign_keys` **23**; `auth_rls_initplan` **WARN**; `multiple_permissive_policies` **WARN** (`meals` has **10** policies, `orders` 8, `user_addresses` 8); `duplicate_index` **WARN**; `unused_index` **INFO**.
- Realtime publication: `orders`, `meals`, `messages`, `shared_carts`, `customer_requests`, `customer_request_quotes`, `kitchen_live_signals`, `ad_campaigns`, `user_notifications`.
- Edge traffic last ~24h (`function_edge_logs`, 297 lines): `send-push-notification` 105×200 + 2×503; `ops-cron` 83×200 + 10×400 + 1×504; `release-chef-payout` 33×200; `cancel-order` 27×200; `create-split-order` 7×200 / 5×401 / 1×400.
- Caching: no CDN/app-level catalog cache in repo. Customer feed loads all `status = 'Available'` meals (currently 7). Fine at this scale; not a high-traffic design.
- Postgres error log lines matching `%error%`: **2** in 24h (query_logs). Not a throughput crisis.

High-traffic code-level: no job queue (pgmq available but not installed), no read replicas, `max_rows = 1000` in `config.toml`, client does full-table meal selects. **N/A** as a load-test (none run).

### 3.3 CI/CD, deploy, rollback — **Fail**

- `.github/workflows/`: **absent** (GitHub API 404 on `.github`).
- No documented deploy pipeline for Flutter (Play/App Store/web hosting) or `supabase functions deploy`.
- Release Android signing is **debug** (`android/app/build.gradle.kts` `signingConfig = debug`).
- Rollback: only git revert + manual function/SQL. Live migration history cannot be replayed from this repo.
- Handler tests exist (Deno + Node) but **deno is not in this Cloud Agent image**; Flutter tests are the only automated suite run here.

### 3.4 Security — **Fail** (blockers)

**What is good (Pass):**

- `public.users` **SELECT is revoked from `anon`** (REST 401 `42501`). Reconstructed migration `users_select USING (true)` is **not** what live anon sees.
- `create-split-order` without Authorization: HTTP **401** `{"success":false,"error":"Unauthorized"}`. Same with the publishable key used as Bearer (anon JWT is not a user). Matches PR #16.
- `ops-cron` without secret: HTTP **401**.
- Live Edge `verify_jwt`: **true** on most functions (including `send-push-notification`, `ai-search`, `ai-craving-matcher`). Repo `config.toml` still sets `verify_jwt = false` for push/AI — **do not redeploy from git config blindly**.
- Plaintext Aadhaar count: **0** (masked column has 1 row). Migration `clear_plaintext_aadhaar` appears to have worked.
- Leaked-password protection: advisor **WARN** (HaveIBeenPwned **disabled**).
- Vault has `edge_service_role_key` (push triggers are actually firing). `edge_webhook_secret` is **not** in Vault names.

**Blockers (Fail):**

1. **Anonymous writes on catalog and orders.**  
   `PATCH /rest/v1/meals?id=eq.00000000-0000-0000-0000-000000000000` with anon key → **HTTP 204**. Same for `orders`. Policies include `Allow all operations on meals USING (true)` and `Chefs and Drivers update orders USING (true)`. A fake UUID updates 0 rows; the request is **authorized**. This is a marketplace-kill bug.

2. **PII / commercial data on public catalog.**  
   Anon `GET meals` returns `fssai_number`, `platform_fee`, `chef_payout_amount`, `transfer_status` (5/5 sample rows nonempty for those commercial fields). REST meals count: **47** unfiltered, **7** `status=eq.Available`.

3. **`formatted_accounts_view` SECURITY DEFINER.**  
   Advisor ERROR. Anon `GET /rest/v1/formatted_accounts_view` **HTTP 200** returned account **email + role** for a customer. Treat as an account-directory leak. Rotate any assumption that emails are private.

4. **Privileged RPCs callable as anon.** Advisor: **73** `anon_security_definer_function_executable`, **77** authenticated. Probe: `claim_daily_streak` as anon ran until FK 409; `deduct_user_coins` as anon executed (HTTP 400 missing column — function still entered).

5. **`verify_jwt` does not bind webhooks to service role.** Anon JWT is a valid JWT. `POST send-push-notification` with publishable Bearer → **HTTP 200** `No target user found in record`. `POST release-chef-payout` → **HTTP 200** `skipped: not_delivered`. Gateway auth is not caller auth.

6. **`razorpay-webhook`:** `verify_jwt=false`, unsigned POST → **HTTP 500** `Webhook secret is not configured`. Payment recovery webhook cannot verify Razorpay signatures until the secret is set.

7. **Cron secret stored in `cron.job.command` plaintext.** Anyone with SQL (dashboard, this MCP, leaked service role) can read `x-ops-cron-secret`. **Rotate it** (value not repeated here). Job: `*/15 * * * *` → `ops-cron`, active.

8. **JWT `user_metadata.role` for GoRouter.** Client-editable metadata until `AuthRoleSync` runs. Owner allowlist email is hardcoded in `lib/utils/platform_ops_access.dart`.

9. **`user_addresses` readable by anon** (`id`, `user_id`, `city` returned HTTP 200). Combined with `chef_profiles` public read.

10. Tables with RLS enabled and **zero policies** (API lockout, not a leak): `wallets`, `favorites`, `remote_ui_config`, `platform_settings`, `api_rate_events`, `email_lookup_attempts`. Wallets inaccessible to the user JWT via PostgREST unless RPCs are used.

11. Grants: `anon` has INSERT/UPDATE/DELETE/**TRUNCATE** on `users` (SELECT revoked). TRUNCATE is not RLS-gated in Postgres; PostgREST does not expose TRUNCATE, but the grant is still wrong.

Advisor security summary: 2 ERROR (`security_definer_view`, `rls_disabled_in_public` on PostGIS `spatial_ref_sys`), 5 WARN, 1 INFO.

### 3.5 Android / iOS / web compatibility — **Partial**

| Platform | Evidence | Verdict |
|---|---|---|
| Android | `applicationId` `com.hotpotchef.app`; `minSdk = flutter.minSdkVersion` = **24**; `targetSdk` 37; `google-services.json` project `hotpotchef-c53fa`; Maps key injected; deep links `hotpotchef://app` + `io.supabase.hotpotchef://reset-callback`; biometric permission present but `local_auth` unused | **Partial** — release uses debug keystore |
| iOS | URL schemes registered; **bundle id `com.example.hotpotchefNew`**; display name **“Hotpotchef New”**; no `GoogleService-Info.plist`; `DefaultFirebaseOptions` throws on iOS; no `GMSServices.provideAPIKey` wiring found; no Privacy Manifest | **Fail** for App Store |
| Web Flutter | Guest hub works (this audit); Firebase web uses **Android appId**; Razorpay explicitly blocked (`checkout_screen.dart` `kIsWeb`); Maps JS injected from `.env` | **Partial** |
| Marketing site | `website/` has 4 files (`cart.html` + css + 2 js). Links to `/terms`, `/privacy`, `/js/config.js` that are **not in repo** | **Fail** |
| Stores | Play `https://play.google.com/store/apps/details?id=com.hotpotchef.app` → **HTTP 404**. `PLAY_STORE_URL` empty by design | **Fail** |

---

## 4. Section 2 — Functional validation

### 4.1 Role workflows — **Partial**

| Workflow | Evidence | Verdict |
|---|---|---|
| Customer browse (guest) | Flutter web: 7 meals, categories, search, add-to-cart | **Pass** |
| Customer signup/login | `AuthScreen` chips Customer/Chef/Driver only; Sign In sheet works; no Admin chip | **Pass** (UI) / **N/A** live signup this session |
| Password recovery | PR #13; scheme `io.supabase.hotpotchef://reset-callback/`; widget tests pass | **Partial** (not email-round-tripped here) |
| Chef onboarding / publish | FSSAI 14-digit gate in publish screen; live `meals_enforce_fssai_available` trigger; 2 chefs, 1 real Route `acc_*`, 1 with no account | **Partial** |
| Driver onboarding | `driver_profiles`, availability columns, hub online toggle; role strings in DB are inconsistent (see below) | **Partial** |
| Admin KYC / FSSAI | `/platform-ops` on main (PR #15); live RPCs `ops_set_fssai_status`, `ops_list_kyc_queue`, `ops_transaction_snapshot` exist; Flutter desk is a subset (Dashboard / FSSAI / KYC) vs permission keys for packaging/brands/refunds/tickets | **Partial** |
| Core paid order | Contract: server recomputes amount; 24h logs 7×200 `create-split-order`; JWT required | **Pass** (Test create) |
| Route transfers | Skip `skipped_no_route_account` still expected for chefs without `acc_*`. 1/2 chefs have a real Test account | **Partial** |
| Delivery / driver gate | `OrderStatus` snake_case + Title Case parse; live **orders still store Title Case** (`Delivered` 28, `Cancelled` 46, `Out for Delivery` 2) | **Partial** |
| Cancel / recover | Live functions `cancel-order` 27×200, `recover-payment` 12×400 / 2×200 in 24h — **not in this git tree** | **Blocked** to audit from `main` source |

**Live identity mess (must normalize before scale):**

`users.role` values: Driver 5, customer 4, Delivery 3, Customer 2, Chef 2, Delivery Partner 1, Food Lover 1, Admin 1.  
`RouteAuthz` maps unknown → customer, so “Food Lover” and mixed-case “customer” happen to land on diner hub, but “Delivery” vs “Driver” vs “Delivery Partner” is a support incident waiting to happen.

**FSSAI:** `fssai_verification_status` verified **2**, unsubmitted **17**. `fssai_number` populated on **2** users. Catalog meals still expose those numbers to anon.

### 4.2 Integrations — **Partial**

| Integration | Live / code | Verdict |
|---|---|---|
| Razorpay Route Test | `create-split-order` 7×200 in 24h; `RAZORPAY_KEY_ID` in agent `.env` (Test). Web checkout blocked. `razorpay-webhook` secret missing | **Partial** |
| FCM | Client token sync on login (code). `send-push-notification` **105×200** in 24h → Vault + FCM service account are configured. 2×503. iOS options missing | **Partial** |
| Maps | Android manifest placeholder + `.env` injection; web JS loader; iOS native key **unverified** | **Partial** |
| Gemini | `ai-search` 1×200 (empty meals when prompt has no ILIKE hit); `ai-tag-meal` 3×200 (this probe returned `tags: []`); `ai-craving-matcher` **503 BOOT_ERROR** | **Partial** / matcher **Fail** |
| Firebase Crashlytics | Android+web options reconstructed; iOS throws; web Crashlytics skipped in bootstrap | **Partial** |

### 4.3 Missing vs redundant

**Missing for a public food app:** web payments, iOS Firebase, store listings, real Privacy/Terms, connectivity/offline queue, rate limits on anon RPCs, catalog status filter on AI search, payout release tied to `orders.status`, embedding backfill, CI, production signing, India region, helper-seat UI (RPCs exist live).

**Present in live DB but thin or absent on this `main` client:** `meal_plans`, `meal_boosts`, `ad_campaigns`, `support_tickets`, `order_disputes`, `coin_holds`, `chef_academy_progress`, `packaging_*`, `platform_ops_invites`, `ops_admin_hq`. The hosted product is broader than the app the repo ships.

**Redundant:** `push-notifier` (legacy, unwired); heuristic `AiRecommendationsSection` named as AI; duplicate RLS policies on `meals`/`orders`.

### 4.4 Scenarios

| Scenario | Verdict | Evidence |
|---|---|---|
| High traffic | **Fail** (code-level) | Full catalog fetch, 10 permissive policies per meal row, 23 unindexed FKs, 37 stuck holds, no cache, single Tokyo region |
| Offline | **Partial** | Guest cart in `SharedPreferences`; no `connectivity_plus`; chef/driver “offline” is availability, not network |
| Error recovery | **Partial** | Live `recover-payment` / `cancel-order` exist and run; checkout idempotency unique index exists; Flutter web shows auth errors raw; Razorpay webhook 500 |
| Guest checkout abuse | **Pass** | Proceed to Checkout opens Sign In; `create-split-order` 401 without user JWT |

### 4.5 Search catalog leak (found in UI)

Feed filters `.eq('status', 'Available')` (7 rows). Search for `"biryani"` returned **Veg Biryani** dated **Sat, 22nd Aug** — not in the Available feed. Cause: `ai-search` ILIKE path does not filter `Available`; Flutter then only drops paused/cancelled. **Archived meals are searchable.** Verdict: **Fail** for catalog hygiene.

---

## 5. Section 3 — UI/UX evaluation

### 5.1 Consistency — **Partial**

Diner hub is a coherent Material 3 orange system (`AppTheme.primary = Colors.deepOrange`), dark mode defined. Marketing `website/cart.html` uses Figtree/Fraunces and a different visual language, and is incomplete. iOS display name “Hotpotchef New” vs Android “HotPotChef”. Web `index.html` description still says “A new Flutter project.”

### 5.2 Accessibility — **Fail**

Zero `Semantics` / `semanticLabel` matches in `lib/`. Bottom nav is icon-only. Favorite hearts are small. Contrast of “TIME PASSED” overlays is weak. No TalkBack/VoiceOver pass was run (**N/A** device a11y lab).

### 5.3 Responsiveness — **Partial**

Flutter web at desktop (~1280×800) rendered a usable card grid without horizontal overflow (manual session). `ScreenUtil` is not applied. No dedicated mobile-web breakpoint testing beyond this desktop viewport.

### 5.4 Engagement — **Partial**

Streak banner, loyalty badge, referral screen, HotPot coins, bulk/catering broadcast banner are in the diner UI. Live `user_gamification` exists; `claim_daily_streak` is a live RPC. Coins mint was recently locked (`lock_hotpot_coin_mint` 2026-09-14). Animations are standard Material; no motion system. Gamification is **feature-present, not loop-proven** (19 users, 2 reviews).

### 5.5 vs Swiggy / Zomato / Uber Eats (qualitative)

| Leader expectation | HotPotChef today |
|---|---|
| Instant catalog, ETA, live tracking polish | Tracking screen exists; Maps iOS unverified; 6/7 visible meals were **TIME PASSED** in this session — feed feels stale |
| One-tap reorder, ratings depth | 2 reviews; recommendations are naive |
| Trust: FSSAI badge, hygiene, billed entity | FSSAI on meals is a raw number leaked to anon, not a trust badge UX |
| Payments everywhere (UPI, cards, web) | Mobile Razorpay Test only; **web pay blocked** |
| Support, refunds, disputes | Live tables/RPCs; app uses placeholder “Contact Us” |
| Localized city ops (India) | DB in **Tokyo** |

Delight suggestions (not implemented here): hide expired slots from “Fresh from the Kitchen”; show kitchen name + verified FSSAI checkmark instead of raw license; add text labels on tabs; replace placeholder legal with hosted policies; don’t surface Archived dishes in search.

Guest-flow screenshots from this audit:

- Meal feed  
- Search  
- Cart  
- Auth gate  

---

## 6. Section 4 — AI / interactive layer

| Component | Deployed | This audit | Verdict |
|---|---|---|---|
| `ai-search` | ACTIVE v16, `verify_jwt=true` | No JWT → 401; anon JWT + `{prompt}` → 200 `meals: []` for “spicy biryani”; UI search “biryani” showed 1 stale dish via ILIKE merge | **Partial** |
| `match_meals` | Live RPC | **0/47** meals have `embedding` | **Fail** (vector path) |
| `ai-craving-matcher` | ACTIVE v10 | HTTP **503** `BOOT_ERROR` | **Fail** |
| `ai-tag-meal` | ACTIVE v7 (old, not updated since create) | HTTP 200 `tags: []` on dal tadka probe; 3×200 in 24h | **Partial** |
| In-app recommendations | `AiRecommendationsSection` | Counts `meals.category` where `customer_name = email` (orders stored on meal rows) | Heuristic, not Gemini |
| Speech / NLP mic | — | No speech packages or code | **N/A** |
| Feedback loop | — | No thumbs-up on search, no embedding refresh on publish | **Fail** |

`ai-search` uses service_role internally and CORS `*`. Threshold 0.1 is extremely broad once embeddings exist (noise risk).

**Enhancements:** backfill `text-embedding-004` on publish (`ai-tag-meal` should write vectors, not only tags); filter Available; fix craving-matcher boot; log rank + click; add “not relevant” feedback; consider rerank on cuisine + distance (`get_nearby_meals_json` already exists live).

---

## 7. Section 5 — Market readiness & benchmarking

### 7.1 Feature parity (honest)

HotPotChef’s **ambition** (home chefs, FSSAI, Route splits, coins, society/group, catering quotes, ads) is closer to a hyperlocal “cloud home kitchen” than to Swiggy’s logistics machine. Execution on `main` is a **diner MVP + chef/driver hubs + thin admin**. Live DB is a **wider ops console** the current app does not fully expose.

Parity score vs leaders: **~2/5** on consumer app quality, **~3/5** on unique home-chef concepts, **~1/5** on trust/compliance UX.

### 7.2 Monetization, retention, onboarding

- Monetization hooks live: platform fee + chef payout columns on meals, Route on_hold, meal boosts, ad campaigns, coins, packaging store. **Measured GMV: not computed** (would require summing orders; skipped to avoid PII-adjacent dumps). 28 Delivered / 46 Cancelled is a **60% cancel rate** on 76 orders — treat as test-data noise unless product confirms otherwise.
- Retention: streaks, referrals, coins, follows. 19 users / 2 reviews — **too small to claim retention**.
- Onboarding: role chips at signup; KYC is profile-gated not hub-gated; Admin is DB-grant + owner email allowlist.

### 7.3 Compliance (India)

| Topic | Verdict | Notes |
|---|---|---|
| FSSAI display / verification | **Partial** | Columns, trigger `enforce_meal_fssai_for_available`, ops notify trigger, 2 verified. Anon can read license numbers. Publish gate is client + trigger, not a public trust UI. |
| Privacy / DPDP | **Fail** | In-app Privacy/Terms/FAQ/Cancellation are `_showPlaceholderSnack`. `website` links 404 in-repo. Addresses and emails leak via view/tables. |
| Payments | **Partial** | Test Route only; webhook secret missing; no live keys (by design this audit). PCI: Razorpay checkout native — **Pass pattern**; web gap. |
| Store / legal entity | **Fail** | Unpublished package; iOS example bundle id. |
| Auth hygiene | **Partial** | Recovery flow exists; leaked-password protection off. |

### 7.4 Transformation alignment

Recent PRs #11–#16 correctly targeted checkout contract, Route Test, recovery, admin desk, migrations export, paid-order P1s. That roadmap is **tactical ship-work**, not yet a production hardening program (RLS, CI, region, stores, AI backfill).

---

## 8. Section 6 — Transformation recommendations

### Technical upgrades (Now)

1. Drop permissive `USING (true)` write policies on `meals` and `orders`; chef writes `chef_id = auth.uid()`, orders via DEFINER RPCs only.  
2. Replace public `meals` select with a **catalog view** (title, price, cuisine, kitchen display name, verified-FSSAI boolean — not license, not fees).  
3. `security_invoker` on `formatted_accounts_view` or revoke anon/authenticated.  
4. `REVOKE EXECUTE` on DEFINER RPCs from `anon`; grant only to `authenticated`/`service_role` as intended.  
5. Validate `X-Webhook-Secret` / Razorpay signature; do not trust anon JWT on push/payout.  
6. Rotate `x-ops-cron-secret` (plaintext in `cron.job`).  
7. `supabase db dump` → replace reconstructed 4-file migrations so git can recreate live.  
8. Align `config.toml` `verify_jwt` with live before any mass deploy.

### UX redesign (2–6 weeks)

- Hide expired/Archived from feed and search.  
- Trust row: kitchen name, verified badge, ETA.  
- Real Privacy/Terms (DPDP + FSSAI consumer notice).  
- Web checkout (Razorpay Standard Checkout.js) or stop advertising “Pay on web” in `website/cart.html`.  
- Accessibility pass (Semantics, labeled tabs, 48dp targets).  
- Rename iOS bundle/display from example/New.

### AI/ML

- Embed on publish; nightly backfill; store model version.  
- Filter `Available` + in-window `time_slot`.  
- Repair `ai-craving-matcher`.  
- Personalize from `orders`, not `meals.customer_name`.

### Ops / monitoring

- GitHub Actions: `flutter analyze` + `flutter test` + `deno test` on PR; protected `main`.  
- Sentry/Crashlytics on iOS after `flutterfire configure`.  
- Alerts on `ops-cron` 400/504, push 503, hold count, cancel rate.  
- Admin desk: wire live `ops_*` RPCs already on the project.

### Scalability / multi-region

Current primary is **Tokyo (`ap-northeast-1`)**. For India (Mumbai/Hyderabad/Chennai users, UPI, FSSAI ops), latency and data-residency optics are wrong. Plan: **Supabase Mumbai or Singapore** as primary before public launch; keep Tokyo only if the operator is JP-based (no evidence of that). Not multi-region-active until RLS and idempotency are solid — splitting a broken policy set is worse.

---

## 9. Section 7 — Outcome: action plan, KPIs, cadence

### Now (this week) — security freeze

- RLS write lockdown on `meals`/`orders`.  
- Catalog column lockdown + kill/fix `formatted_accounts_view`.  
- Revoke anon EXECUTE on DEFINER RPCs.  
- Set Razorpay webhook secret; reject unsigned.  
- Rotate cron secret; stop storing it in `cron.job` SQL text if possible (Vault).  
- Filter AI/search to Available.  
- Do **not** `db push` the 4 reconstructed migrations onto live.

### 2 weeks

- Dump live schema into git; delete drift.  
- CI on PRs.  
- iOS Firebase + bundle id `com.hotpotchef.app`.  
- Release signing (upload key).  
- Privacy/Terms URLs that actually open.  
- Expire/release the 37 confirmed inventory holds.  
- Normalize `users.role` enum.  
- Chef Route: get remaining chefs off `skipped_no_route_account`.  
- Fix payout trigger to `orders.status` delivered (today it fires on `meals` updates — 33×200 `release-chef-payout` in 24h is suspiciously high vs 28 delivered all-time).

### 30 days

- Embedding backfill + publish hook.  
- Web Razorpay or explicitly “app-only pay”.  
- Admin desk feature-parity with live `ops_*`.  
- Region decision (India).  
- Closed Android Test track (internal testing), not public production.

### 60–90 days

- Play production + App Store with FSSAI/trust UX.  
- Observability SLOs.  
- Load test checkout/idempotency.  
- Enable HaveIBeenPwned.  
- Live Razorpay (only after webhook + RLS + Route KYC).  
- Accessibility + localization (hi-IN).

### KPIs (measure after hardening; baselines from this audit)

| KPI | Baseline now | Target after transformation |
|---|---|---|
| Available meals (REST `status=eq.Available`) | **7** | Ops-set (not vanity); quality > count |
| Guest feed crash-free session | Pass in this web session | ≥99.5% Crashlytics |
| `create-split-order` 401 without JWT | **Pass** | Keep 100% |
| Anon PATCH meals/orders | **204 (Fail)** | **401/403** |
| Meals with embeddings | **0/47** | 100% of Available |
| FSSAI verified chefs | **2** | 100% of kitchens with Available meals |
| Route real `acc_*` among chefs | **1/2** | 100% before Live payouts |
| Inventory holds `confirmed` | **37** | ~0 stale |
| Cancelled / all orders | **46/76** | Investigate; <15% in real ops |
| Flutter tests | **120 passed** | Keep + add checkout/RLS integration |
| `flutter analyze` issues | **36** (0 errors, warnings+info) | 0 warnings |
| Play listing | **404** | 200 |
| Edge push 200s / 503s (24h) | 105 / 2 | Alert on 503 |
| p95 API (not measured) | **N/A** | Measure from Tokyo vs future IN region |

### Continuous improvement

- Weekly: advisor security+performance, RLS probe pack (the HTTP checks in the appendix), cancel/hold dashboards.  
- Per release: `flutter test`, Deno function tests, migration diff vs live.  
- Monthly: FSSAI expiry job (`expire_lapsed_fssai_licences` exists — **revoke anon execute**), embedding drift, Razorpay Test settlement recon.  
- Do not treat reconstructed SQL as production.

---

## 10. Top 10 risks (ranked)

| Rank | Risk | Why it matters | Likelihood now |
|---|---|---|---|
| 1 | Anon can PATCH `meals` and `orders` | Catalog price/status fraud, order hijack | **Confirmed** HTTP 204 |
| 2 | SECURITY DEFINER view + catalog columns leak email, FSSAI, payout math | DPDP, chef hostility, competitor scraping | **Confirmed** |
| 3 | Anon-executable DEFINER RPCs (streak, coins, claim delivery, …) | Privilege escalation / economic abuse | **Confirmed** probes + advisor 73 |
| 4 | Git `main` cannot rebuild live (4 vs 80 migrations; 8 vs 17 functions) | Irreversible prod drift, failed rollback | **Confirmed** |
| 5 | Webhook/payout functions accept anon JWT; Razorpay webhook has no secret | Fake push, payout release attempts, missed captures | **Confirmed** 200/500 |
| 6 | iOS example bundle id + no Firebase plist + debug Android signing + Play 404 | Cannot ship stores | **Confirmed** |
| 7 | Payout automation tied to `meals` updates, not delivered orders | Chefs unpaid or spurious release calls (33×/day) | **High** |
| 8 | Privacy/Terms placeholders + Tokyo residency | India launch legal/trust block | **Confirmed** |
| 9 | Vector AI dead; search returns Archived dishes | Bad UX, “AI” claim false | **Confirmed** |
| 10 | Stuck inventory holds (37) + 60% cancelled orders | Silent stock bugs, untrustworthy ops metrics | **Confirmed** counts |

---

## 11. Evidence appendix

### 11.1 Git / product slice

- `git log -1`: `2c99808` Merge PR #16 “Fix paid-order P1 gaps…”.  
- Merged PRs #11–#16 via `gh pr list` (titles match known ship work).  
- `flutter test`: **All tests passed — 120**.  
- `flutter analyze --no-fatal-infos`: **36 issues**, exit 0 (warnings + infos; deprecated APIs, unused imports, dead code).  
- Deno tests: **Blocked** (`deno: command not found` on this agent).  
- Flutter SDK: 3.44.8 / Dart 3.12.2.

### 11.2 Live project

```
id: tpcykyaumvqtwhuiiomg
name: HotPotChef
region: ap-northeast-1
status: ACTIVE_HEALTHY
postgres: 17.6.1.147
created_at: 2026-07-23
```

Installed extensions used: `vector 0.8.2`, `postgis 3.3.7`, `pg_net 0.20.4`, `pg_cron 1.6.4`, `supabase_vault 0.3.1`, `pg_stat_statements 1.11`.

Vault secret **names**: `edge_service_role_key` only.

### 11.3 HTTP probes (publishable key, 2026-09-14)

| Call | Code | Body (truncated, no PII) |
|---|---|---|
| `GET /rest/v1/meals` count | 206 | `content-range: 0-0/47` |
| `GET meals?status=eq.Available` | 206 | `0-0/7` |
| `GET meals?status=eq.available` | 200 | `*/0` (case-sensitive) |
| `GET /rest/v1/users?select=id` | **401** | GRANT SELECT denied to anon |
| `PATCH meals` fake UUID | **204** | authorized no-op |
| `PATCH orders` fake UUID | **204** | authorized no-op |
| `GET user_addresses?select=id,user_id,city` | **200** | rows returned |
| `GET formatted_accounts_view` | **200** | emails/roles returned |
| `POST functions/v1/create-split-order` no JWT | **401** | Unauthorized |
| `POST create-split-order` anon Bearer | **401** | Unauthorized |
| `POST ai-search` no JWT | **401** | UNAUTHORIZED_NO_AUTH_HEADER |
| `POST ai-search` `{prompt:"spicy biryani"}` | **200** | `{success:true,meals:[]}` |
| `POST ai-tag-meal` | **200** | `{tags:[]}` |
| `POST ai-craving-matcher` | **503** | BOOT_ERROR |
| `POST razorpay-webhook` unsigned | **500** | Webhook secret is not configured |
| `POST ops-cron` no secret | **401** | Unauthorized |
| `POST send-push-notification` anon JWT | **200** | No target user found |
| `POST release-chef-payout` anon JWT | **200** | skipped not_delivered |
| `POST rpc/claim_daily_streak` anon | **409** | FK to users (function ran) |
| Play Store package URL | **404** | unpublished |

### 11.4 Function logs ~24h (`function_edge_logs`, n=297)

Top: push 105×200, ops-cron 83×200, release-chef-payout 33×200, cancel-order 27×200, create-split-order 7×200 + 5×401.

### 11.5 Flutter web guest session (localhost:8080)

Video: guest feed → empty cart → sign-in sheet → search biryani → add Veg Jumbo Thali → checkout auth gate → orders login prompt.

Console: `TypeError: _JsonMap is not a subtype of List<Object>` in webdev injected client (did not crash the flow).

### 11.6 What this audit did **not** do

- Paid Razorpay capture or Live keys.  
- Logged-in chef/driver/admin consoles.  
- Email recovery round-trip.  
- Native Android APK / iOS Simulator.  
- Load test.  
- Dumping live SQL (by design; use official dump in a hardening PR).  
- Mutating real meal/order rows.

### 11.7 Commands to reproduce checks

```bash
flutter test
flutter analyze --no-fatal-infos
# REST counts (requires publishable key in env)
curl -sD - -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  -H "Prefer: count=exact" -H "Range: 0-0" \
  "$URL/rest/v1/meals?select=id&status=eq.Available"
curl -sS -X POST "$URL/functions/v1/create-split-order" \
  -H "Content-Type: application/json" -d '{"items":[]}'
```

---

*End of audit. No production code was changed. This document is the deliverable.*
