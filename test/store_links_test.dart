import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/store_links.dart';

void main() {
  group('StoreLinks.playStoreUrl', () {
    test('returns empty when no listing is configured', () {
      expect(StoreLinks.playStoreUrl(), isEmpty);
      expect(StoreLinks.playStoreUrl(configuredUrl: ''), isEmpty);
      expect(StoreLinks.playStoreUrl(configuredUrl: '#'), isEmpty);
      expect(StoreLinks.hasPlayStoreListing(), isFalse);
    });

    test('does not invent a Play Store URL from the Android package', () {
      expect(
        StoreLinks.playStoreUrl(
          configuredUrl: 'https://play.google.com/store/apps/details?id=${StoreLinks.androidPackage}',
        ),
        'https://play.google.com/store/apps/details?id=${StoreLinks.androidPackage}',
      );
      // Package alone is not a listing.
      expect(StoreLinks.playStoreUrl(configuredUrl: StoreLinks.androidPackage), isEmpty);
    });

    test('accepts a real configured listing', () {
      const url = 'https://play.google.com/store/apps/details?id=com.example.live';
      expect(StoreLinks.playStoreUrl(configuredUrl: url), url);
      expect(StoreLinks.hasPlayStoreListing(configuredUrl: url), isTrue);
    });
  });
}
