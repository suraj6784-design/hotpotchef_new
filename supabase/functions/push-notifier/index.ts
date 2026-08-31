import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// 🛑 IMPORTANT: You will need to add your Firebase Server Key as a Supabase Secret later
const FCM_SERVER_KEY = Deno.env.get('FCM_SERVER_KEY') ?? '';

serve(async (req) => {
  try {
    // 1. Parse the Webhook Payload from Supabase
    const payload = await req.json();
    const newRecord = payload.record;
    const oldRecord = payload.old_record;

    // Only trigger if the status actually changed
    if (oldRecord && newRecord.status === oldRecord.status) {
      return new Response(JSON.stringify({ message: "Status unchanged, ignoring." }), { status: 200 });
    }

    // 2. Initialize Supabase Admin Client
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    let targetUserId = '';
    let title = '';
    let body = '';

    // 3. Define Notification Logic based on Status
    const status = newRecord.status.toLowerCase();
    
    if (status === 'confirmed' || status === 'preparing') {
      // Notify Customer: Chef accepted
      targetUserId = newRecord.customer_id;
      title = 'Order Confirmed! 👨‍🍳';
      body = `Your order for ${newRecord.title} is being prepared.`;
    } 
    else if (status === 'out for delivery') {
      // Notify Customer: Driver picked it up
      targetUserId = newRecord.customer_id;
      title = 'Food is on the way! 🛵';
      body = `Your ${newRecord.title} has been dispatched. Track it live!`;
    }
    else if (status === 'delivered') {
      // Notify Customer: Arrived
      targetUserId = newRecord.customer_id;
      title = 'Order Delivered! 🎉';
      body = `Enjoy your home-cooked meal! Don't forget to rate the chef.`;
    }
    else if (status === 'pending chef approval') {
      // Notify Chef: New Order arrived
      targetUserId = newRecord.chef_id;
      title = 'New Order Alert! 🔔';
      body = `You have a new request for ${newRecord.quantity}x ${newRecord.title}.`;
    }

    if (!targetUserId) {
      return new Response(JSON.stringify({ message: "No notification required for this status." }), { status: 200 });
    }

    // 4. Fetch the target user's FCM Token
    const { data: userData, error: userError } = await supabase
      .from('users')
      .select('fcm_token')
      .eq('id', targetUserId)
      .single();

    if (userError || !userData?.fcm_token) {
      return new Response(JSON.stringify({ error: "User has no FCM token." }), { status: 200 });
    }

    // 5. Fire the payload to Firebase
    const fcmResponse = await fetch('https://fcm.googleapis.com/fcm/send', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `key=${FCM_SERVER_KEY}`,
      },
      body: JSON.stringify({
        to: userData.fcm_token,
        notification: {
          title: title,
          body: body,
          sound: "default",
          badge: 1
        },
        data: {
          order_id: newRecord.id,
          click_action: "FLUTTER_NOTIFICATION_CLICK"
        }
      }),
    });

    const fcmResult = await fcmResponse.json();
    return new Response(JSON.stringify({ success: true, fcm: fcmResult }), { status: 200 });

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
});