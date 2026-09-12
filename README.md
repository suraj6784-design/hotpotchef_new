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
flutter run --flavor diner --dart-define=APP_FLAVOR=diner --dart-define-from-file=.env
flutter run --flavor partner --dart-define=APP_FLAVOR=partner --dart-define-from-file=.env
```

Release APKs (diner **HotPotChef** + partner **HotPotChef Partner**; Razorpay keys stay from `.env`):

```bash
# Windows: powershell -File tool/build_release_apk.ps1
# macOS/Linux:
bash tool/build_release_apk.sh
```

Local `.env` is also read at startup if present. Do not list `.env` as a Flutter asset — that would ship secrets in the APK.
