/// Public runtime config: compile-time `--dart-define` first, then optional local `.env`.
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> loadAppEnv() async {
  try {
    await dotenv.load(fileName: '.env', isOptional: true);
  } catch (_) {
    // Release builds must not require a bundled .env file.
  }
}

String appEnv(String key) {
  final fromDefine = _fromDefine(key);
  if (fromDefine.isNotEmpty) return fromDefine;
  try {
    return dotenv.env[key]?.trim() ?? '';
  } catch (_) {
    return '';
  }
}

String _fromDefine(String key) {
  switch (key) {
    case 'SUPABASE_URL':
      return const String.fromEnvironment('SUPABASE_URL');
    case 'SUPABASE_ANON_KEY':
      return const String.fromEnvironment('SUPABASE_ANON_KEY');
    case 'RAZORPAY_KEY_ID':
      return const String.fromEnvironment('RAZORPAY_KEY_ID');
    case 'GOOGLE_MAPS_API_KEY':
      return const String.fromEnvironment('GOOGLE_MAPS_API_KEY');
    case 'PLATFORM_OWNER_EMAIL':
      return const String.fromEnvironment('PLATFORM_OWNER_EMAIL');
    case 'SUPPORT_EMAIL':
      return const String.fromEnvironment('SUPPORT_EMAIL');
    case 'SUPPORT_WHATSAPP':
      return const String.fromEnvironment('SUPPORT_WHATSAPP');
    case 'PLAY_STORE_URL':
      return const String.fromEnvironment('PLAY_STORE_URL');
    case 'TERMS_URL':
      return const String.fromEnvironment('TERMS_URL');
    case 'PRIVACY_URL':
      return const String.fromEnvironment('PRIVACY_URL');
    case 'FAQ_URL':
      return const String.fromEnvironment('FAQ_URL');
    case 'CANCELLATION_POLICY_URL':
      return const String.fromEnvironment('CANCELLATION_POLICY_URL');
    default:
      return '';
  }
}

bool googleMapsApiKeyConfigured() => appEnv('GOOGLE_MAPS_API_KEY').isNotEmpty;
