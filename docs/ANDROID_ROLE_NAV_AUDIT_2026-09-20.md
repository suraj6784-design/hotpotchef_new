# Android role navigation audit — 2026-09-20

**Repo:** hotpotchef_new  
**Base:** `main` @ `05a481a`  
**Companion:** live emulator E2E on the user's laptop (this pass is **code-only**; no device session here)  
**Constraint:** surgical consolidations only. Do **not** redesign the cream diner storefront.

Chrome entry points were inventoried across Customer / Chef / Driver / Admin hubs. Duplicates that stacked the same screen twice (or labeled two different screens the same way) were collapsed to one dock or overflow path. Deep-link aliases remain registered.

---

## Report matrix

| Duplicate | Locations | Consolidation | Status |
| --- | --- | --- | --- |
| Legal docs | Profile Help tiles, auth terms, checkout links → `openLegalDocument` used a second `MaterialPageRoute` **and** GoRouter `/legal/:doc` exists | `openLegalDocument` now `push(legalPathFor(type))`. External URL still wins when `SupportConfig` has one | **FIXED** |
| Chef meal editor | Menu edit used off-router `MaterialPageRoute(ChefPublishMealScreen)`; Publish already uses `/chef-publish-meal` | `_openMealEditor` → `context.push('/chef-publish-meal', extra: meal)` | **FIXED** |
| Driver Digital ID | Overflow **Digital ID** + Home tool + Profile button; Profile used `MaterialPageRoute` while others used `/driver-id-card` | Overflow item removed. Profile and Home tool both `push('/driver-id-card')`. Canonical chrome = Profile; Home stays the quick action (same pattern as chef Upload Menu) | **FIXED** |
| Partner portal switch | Home pill + large “Want to deliver/cook instead?” banner + driver overflow | Banners removed. Pill stays on Home. Overflow: chef **Delivery portal**, driver **Chef portal** (needed off-Home) | **FIXED** |
| Profile (KYC / alerts) | `KycReminderBanner` and `alertOpenPath` pushed `/chef-profile` or `/driver-profile` **on top of** the hub Profile dock | Banner calls `onOpenProfile` → dock tab 2. KYC alerts → `/chef-hub?tab=profile` or `/driver-hub?tab=profile`. Standalone routes kept for cold deep links | **FIXED** |
| Notifications inbox | Dock **Alerts** embeds `NotificationsInboxScreen`; unused `/notifications` painted a second chrome-less copy; back always `go('/customer-hub')` (wrong APK/role) | Signed-in diner/chef/driver `/notifications` redirects to `?tab=alerts`. Back uses `role.hubPath`. Admin may keep standalone | **FIXED** |
| Orders / history | Wallet “See all orders” + delivered FCM → `/order-history` while Orders dock already has Active / Past | Wallet and delivered alerts → `/customer-hub?tab=orders&past=1`. `/order-history` remains a legacy alias (not linked from chrome) | **FIXED** |
| Referral | Loyalty card cell → `/referral`; Share code is a sheet, not a second screen | Single chrome entry (Profile loyalty). Route stays signed-in diner-only | **OK** (already one entry) |
| Packaging supplies | Chef overflow **Packaging supplies** → hub tab 8 (`?tab=supplies`). Admin desk Packaging is a different inbox | One chef entry (overflow). Not a diner/driver screen (`canUsePackagingStore`) | **OK** |
| Cart | Home header bag + floating tray + `?tab=cart` (not on dock) | Left as designed — cream storefront. Not a second route | **OK** (by design) |
| Tracking | Active order **Track** + live-status FCM `/tracking?orderId=` | Contextual (order), not a second hub tab | **OK** |
| Chat | Overflow / Profile **Order chats** → `/chats` inbox; order cards → `chatPath(room)` | Inbox vs room are different screens. One inbox entry per role (Profile diner, overflow partner) | **OK** |
| Kitchen take-home label | Chef overflow + history tab = completed orders; Profile tile used the **same label** for `/chef-analytics` | Profile tile renamed **Earnings analytics**. Overflow/history keep “Kitchen take-home” | **FIXED** |
| Dock labels | Diner `DinerCopy` vs chef/driver hardcoded strings; glass `HubBottomDock` vs `Scaffold.bottomNavigationBar` | English diner already Profile/Alerts. Partner docks now share `partnerHubDockDestinations`. All hubs overlay `HubBottomDock` (glass). Admin desk stays tab-strip (ops, not marketplace) | **OK** / **ALIGNED** |
| Wrong storefront | Diner APK + chef/driver session; Partner APK + diner session | `/wrong-app` + `kAppStorefront.allowsRole`. Partner portal pills only when `isPartner`. Inbox back no longer assumes diner hub | **OK** + **FIXED** back-target |

---

## Role chrome (after this pass)

| Role | Dock (glass `HubBottomDock`) | Overflow / extra | Notes |
| --- | --- | --- | --- |
| Customer | Home · Orders · Profile · Alerts (`DinerCopy`) | Cart = header + tray, not dock | Cream storefront unchanged |
| Chef | Home · Orders · Profile · Alerts (`partnerHubDockDestinations`) | Menu, Dispatch, Kitchen take-home, chats, leads, supplies, ads, academy, Delivery portal | Overflow-only tabs 4–8 |
| Driver | Same four labels | Chef portal, chats | `?tab=` now selects Home/Orders/Profile/Alerts |
| Admin | Ops desk tabs (not the marketplace dock) | Profile → **Diner feed** preview `?preview=diner` | Intentional desk chrome |

---

## Off-router leftovers (still intentional)

These are **not** duplicate hub screens. They have no GoRoute and stay `Navigator` / `appMaterialRoute`:

- Address form, map picker
- Checkout (including membership-only)
- Academy lesson / certificate
- Support ticket thread, ops ticket thread

Converted in this pass: legal, chef meal editor, driver ID from Profile.

---

## Flavor / APK confusion (code-proven)

Compile-time storefront (`lib/utils/app_flavor.dart`):

- `--flavor diner` / default → `HotPotChef`, signup `Customer` only
- `--flavor partner` (Flutter `FLUTTER_APP_FLAVOR` + Gradle-injected `APP_FLAVOR`) / aliases `chef` / `driver` → `HotPotChef Partner`, signup Chef + Delivery Partner
- Do **not** rely on a manual `--dart-define=APP_FLAVOR=partner` — Android flavors inject it. iOS has no matching schemes.
- Admin is allowed on both APKs
- Mismatch → `/wrong-app` then Sign out (copy names the **other** app)

Partner Home pills (“Chef Portal” / “Delivery Partner”) render only when `kAppStorefront.isPartner`. Switching portals signs out and opens `/auth?role=…&signup=1` — it does **not** mutate `users.role` in place.

`/notifications` back used to ignore flavor and always open `/customer-hub` (a Partner-session bug). It now uses `AuthSession.roleFromSession().hubPath`.

---

## Market-readiness / errors / security (code review can prove)

No live Edge or emulator claims in this document. These are **in-tree**.

### Present and wired

| Control | Where | What code proves |
| --- | --- | --- |
| Offline banner | `main.dart` wraps `MaterialApp.router` in `OfflineBannerHost`; `test/widget_test.dart` covers show/hide | Global “You're offline…” strip; Pay/actions may fail while offline |
| Timeouts / retry copy | `NetworkTimeouts`, `networkErrorMessage` | Checkout, hubs, banners use the same timeout helper |
| RouteAuthz (pure) | `lib/utils/route_authz.dart` + `test/route_authz_test.dart` | Role parse, hub map, guest vs signed-in redirects. Diner account paths (`/referral`, `/order-history`, …) are now `RouteAccess.customer` |
| Router gate | `AppRouter.redirect` + `roleCanOpenAuthenticatedPath` | Second, live gate. Partner guests cannot open diner hub. Wrong flavor → `/wrong-app` |
| Hub role bounce | `AuthSession.ensureHubRole` on customer/chef/driver hubs | Signed-in user on the wrong hub is sent to `users.role` hub |
| Secure storage | `lib/utils/payment_preferences.dart` | `FlutterSecureStorage` for saved UPI VPA only. Preferred **method** is `SharedPreferences`. Card PANs are never stored (comment + Razorpay prefill only) |
| Local auth | `unlockSavedPayInstrument` | Device lock before reusing a saved instrument; fails open if the plugin is unsupported |
| Flavor allow-list | `kAppStorefront.allowsRole` | Chef/driver cannot use the diner APK; diners cannot use Partner |

### Dual gate (document, do not “simplify” blindly)

`RouteAuthz.resolveRedirect` is **not** what `GoRouter` calls. The running redirect uses `signedInOnlyRoutes` + `roleCanOpenAuthenticatedPath`.

- `/chats` is `RouteAccess.shared` (guests allowed by RouteAuthz) but listed in `signedInOnlyRoutes` (guests → `/auth`). Runtime is stricter.
- `/notifications` stays `shared` in RouteAuthz so any signed-in role can hit the alias; the router then rewrites diner/chef/driver to the Alerts tab.
- JWT `user_metadata.role` vs `public.users.role` can diverge until `AuthSession.resolveRole` refreshes. Owner email allowlist in RouteAuthz must stay aligned with `is_platform_ops()`.

### Gaps still open (do not weaken RLS to “fix”)

| Item | Risk | Owner |
| --- | --- | --- |
| `messages` SELECT `USING (true)` (prior audit) | Any signed-in user can read all chats | Policy change; not this PR |
| Authenticated `users` SELECT includes bank / PAN / Aadhaar columns | Cross-account KYC read | Split table / column view |
| Live `RAZORPAY_WEBHOOK_SECRET` unset (prior live smoke) | Captures never record via webhook | Human secret + dashboard URL |
| Play listing `com.hotpotchef.app` HTTP 404; `PLAY_STORE_URL` empty | Profile “Rate us” / store CTAs have no listing | Human store listing |
| Maps key restriction + iOS `GMSServices.provideAPIKey` | Tracking / pin UX | Human Cloud Console + iOS plist |
| `/order-history` screen still compiled | Dead chrome if a bookmark hits it; not linked from hubs | Leave as alias; do not delete in this pass |
| Emulator E2E | Role passwords and paid Razorpay not run here | Laptop companion run |

---

## Tests added / updated

```bash
flutter test \
  test/role_nav_audit_test.dart \
  test/route_authz_test.dart \
  test/checkout_address_test.dart \
  test/app_flavor_test.dart \
  test/hub_role_integrity_test.dart \
  test/diner_locale_test.dart \
  test/widget_test.dart
```

`role_nav_audit_test.dart` locks legal paths, driver tab indices, hub Alerts/Profile/Orders helpers, diner vs partner dock labels, and flavor allow-lists.

---

## How this relates to the laptop emulator run

Expect on device after this lands:

- One Alerts tab (no second Notifications page from chrome)
- One Profile surface from KYC banners
- Wallet / delivered push opens Orders → Past, not a separate history scaffold
- Legal tiles stay in GoRouter (system back matches the rest of the app)
- Partner Home no longer repeats the portal switch under the pill
- Chef/driver Digital ID and meal editor no longer skip the router
