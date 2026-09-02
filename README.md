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

Configure `.env` with `SUPABASE_URL` and `SUPABASE_ANON_KEY`, then `flutter run`.
