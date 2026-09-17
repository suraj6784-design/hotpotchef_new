// lib/utils/store_links.dart
//
// Play Store listing `com.hotpotchef.app` is not published (HTTP 404).
// Never invent a store URL from the Android applicationId. Supply a real
// listing via PLAY_STORE_URL / APP_STORE_URL when one exists.

abstract final class StoreLinks {
  /// Android applicationId / Firebase package. Not a proof the listing exists.
  static const androidPackage = 'com.hotpotchef.app';

  static const playStoreEnvKey = 'PLAY_STORE_URL';
  static const appStoreEnvKey = 'APP_STORE_URL';

  /// Returns [configuredUrl] only when it is a real http(s) listing.
  /// Empty / `#` / package-only placeholders disable the CTA.
  static String playStoreUrl({String? configuredUrl}) {
    final url = configuredUrl?.trim() ?? '';
    if (!_isUsableHttpUrl(url)) return '';
    return url;
  }

  static String appStoreUrl({String? configuredUrl}) {
    final url = configuredUrl?.trim() ?? '';
    if (!_isUsableHttpUrl(url)) return '';
    return url;
  }

  static bool hasPlayStoreListing({String? configuredUrl}) {
    return playStoreUrl(configuredUrl: configuredUrl).isNotEmpty;
  }

  /// Deep-link / intent scheme used by the marketing cart.
  static const appScheme = 'hotpotchef';
  static const appHost = 'app';
  static const cartPath = '/cart';

  static const passwordResetScheme = 'io.supabase.hotpotchef';
  static const passwordResetHost = 'reset-callback';

  static bool _isUsableHttpUrl(String url) {
    if (url.isEmpty || url == '#') return false;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }
}
