import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Client-side FCM token lifecycle is fixed in the Flutter app.
// This function still depends on a hosted `orders` webhook that is NOT in
// this repo (no supabase/migrations, roles.sql is timeouts only). Do not
// claim push delivery works until that webhook is exported / applied.
//
// Preferred long-term path: FCM HTTP v1 (`send-push-notification`). This
// function keeps the legacy FCM HTTP API so existing secrets keep working.

const FCM_SERVER_KEY = Deno.env.get('FCM_SERVER_KEY') ?? '';

type NotifyTarget = { userId: string; title: string; body: string };

function collectTargets(record: Record<string, unknown>): NotifyTarget[] {
  const status = String(record.status ?? '').toLowerCase();
  const title = String(record.title ?? 'your order');
  const customerId = String(record.customer_id ?? '');
  const chefId = String(record.chef_id ?? '');
  const driverId = String(record.delivery_partner_id ?? record.driver_id ?? '');
  const quantity = record.quantity ?? 1;
  const targets: NotifyTarget[] = [];

  const add = (userId: string, nTitle: string, nBody: string) => {
    if (userId) targets.push({ userId, title: nTitle, body: nBody });
  };

  if (status === 'confirmed' || status === 'preparing') {
    add(customerId, 'Order Confirmed! 👨‍🍳', `Your order for ${title} is being prepared.`);
  } else if (status === 'ready for pickup' || status === 'ready') {
    add(customerId, 'Ready for Pickup! 🥡', `Your ${title} is ready.`);
    add(driverId, 'Pickup ready 🛵', `${title} is ready for pickup.`);
  } else if (status === 'out for delivery') {
    add(customerId, 'Food is on the way! 🛵', `Your ${title} has been dispatched. Track it live!`);
    add(driverId, 'Delivery assigned 🛵', `You are delivering ${title}.`);
  } else if (status === 'delivered') {
    add(customerId, 'Order Delivered! 🎉', `Enjoy your home-cooked meal! Don't forget to rate the chef.`);
  } else if (status === 'pending chef approval') {
    add(chefId, 'New Order Alert! 🔔', `You have a new request for ${quantity}x ${title}.`);
  }

  return targets;
}

serve(async (req) => {
  try {
    const payload = await req.json();
    const newRecord = payload.record ?? {};
    const oldRecord = payload.old_record;

    if (oldRecord && newRecord.status === oldRecord.status) {
      return new Response(JSON.stringify({ message: "Status unchanged, ignoring." }), { status: 200 });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const targets = collectTargets(newRecord);
    if (targets.length === 0) {
      return new Response(JSON.stringify({ message: "No notification required for this status." }), { status: 200 });
    }

    const results = [];
    for (const target of targets) {
      const { data: userData, error: userError } = await supabase
        .from('users')
        .select('fcm_token')
        .eq('id', target.userId)
        .single();

      if (userError || !userData?.fcm_token) {
        results.push({ userId: target.userId, skipped: 'no_fcm_token' });
        continue;
      }

      const fcmResponse = await fetch('https://fcm.googleapis.com/fcm/send', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `key=${FCM_SERVER_KEY}`,
        },
        body: JSON.stringify({
          to: userData.fcm_token,
          notification: {
            title: target.title,
            body: target.body,
            sound: "default",
            badge: 1
          },
          data: {
            order_id: String(newRecord.id ?? ''),
            click_action: "FLUTTER_NOTIFICATION_CLICK"
          }
        }),
      });

      const fcmResult = await fcmResponse.json();
      results.push({ userId: target.userId, fcm: fcmResult });
    }

    return new Response(JSON.stringify({ success: true, results }), { status: 200 });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
});
