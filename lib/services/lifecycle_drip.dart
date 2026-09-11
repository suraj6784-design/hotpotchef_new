import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/network.dart';

Future<void> enqueueWelcomeDrip() async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return;
  try {
    final raw = await client.rpc('claim_welcome_drip').withTimeout(NetworkTimeouts.short);
    final send = raw is Map && raw['send'] == true;
    if (!send) return;
    await client.functions.invoke(
      'send-push-notification',
      body: {'event': 'welcome', 'user_id': user.id},
    ).withTimeout(NetworkTimeouts.standard);
  } catch (_) {}
}
