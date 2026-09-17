import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/app_deep_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AppDeepLinks.locationFor cart', () {
    test('maps hotpotchef://app/cart to /app/cart', () {
      expect(
        AppDeepLinks.locationFor(Uri.parse('hotpotchef://app/cart')),
        '/app/cart',
      );
      expect(
        AppDeepLinks.locationFor(Uri.parse('hotpotchef://app/cart/')),
        '/app/cart',
      );
    });

    test('maps path-only /app/cart regardless of http host', () {
      expect(
        AppDeepLinks.locationFor(Uri.parse('https://hotpotchef.app/app/cart')),
        '/app/cart',
      );
      expect(AppDeepLinks.locationFor(Uri.parse('/app/cart')), '/app/cart');
      expect(
        AppDeepLinks.locationFor(
          Uri.parse('https://hotpotchef.app/#/app/cart'),
        ),
        '/app/cart',
      );
    });

    test('does not treat hub or generic /cart https paths as cart intents', () {
      expect(
        AppDeepLinks.locationFor(
          Uri.parse('https://hotpotchef.app/customer-hub'),
        ),
        isNull,
      );
      expect(
        AppDeepLinks.locationFor(Uri.parse('https://hotpotchef.app/cart')),
        isNull,
      );
    });
  });

  group('AppDeepLinks.cartLocationFor', () {
    test('toggles alias so a second cart intent remounts the hub tab', () {
      expect(AppDeepLinks.cartLocationFor(), '/app/cart');
      expect(
        AppDeepLinks.cartLocationFor(currentPath: '/customer-hub'),
        '/app/cart',
      );
      expect(AppDeepLinks.cartLocationFor(currentPath: '/app/cart'), '/cart');
      expect(AppDeepLinks.cartLocationFor(currentPath: '/app/cart/'), '/cart');
    });
  });

  group('AppDeepLinks.locationFor password recovery', () {
    test('maps the registered reset-callback scheme', () {
      expect(
        AppDeepLinks.locationFor(
          Uri.parse('io.supabase.hotpotchef://reset-callback/'),
        ),
        '/reset-password',
      );
      expect(
        AppDeepLinks.locationFor(
          Uri.parse(
            'io.supabase.hotpotchef://reset-callback/#access_token=abc&type=recovery',
          ),
        ),
        '/reset-password',
      );
    });

    test(
      'maps /reset-callback, /reset-password, and type=recovery fragments',
      () {
        expect(
          AppDeepLinks.locationFor(
            Uri.parse('https://example.com/reset-callback'),
          ),
          '/reset-password',
        );
        expect(
          AppDeepLinks.locationFor(
            Uri.parse('https://example.com/reset-password'),
          ),
          '/reset-password',
        );
        expect(
          AppDeepLinks.locationFor(
            Uri.parse('https://example.com/#/reset-password'),
          ),
          '/reset-password',
        );
        expect(
          AppDeepLinks.locationFor(
            Uri.parse('https://example.com/#type=recovery'),
          ),
          '/reset-password',
        );
      },
    );

    test('passwordResetRedirectTo matches the Android/iOS callback', () {
      expect(
        AppDeepLinks.passwordResetRedirectTo(),
        'io.supabase.hotpotchef://reset-callback/',
      );
    });
  });

  group('AppDeepLinks.locationForAuthEvent', () {
    test('routes passwordRecovery to the set-password screen', () {
      expect(
        AppDeepLinks.locationForAuthEvent(AuthChangeEvent.passwordRecovery),
        '/reset-password',
      );
      expect(
        AppDeepLinks.locationForAuthEvent(AuthChangeEvent.signedIn),
        isNull,
      );
      expect(
        AppDeepLinks.locationForAuthEvent(AuthChangeEvent.signedOut),
        isNull,
      );
    });
  });
}
