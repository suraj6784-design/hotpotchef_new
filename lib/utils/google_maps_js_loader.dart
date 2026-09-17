import 'google_maps_js_loader_stub.dart'
    if (dart.library.html) 'google_maps_js_loader_web.dart';

/// Loads the Google Maps JavaScript API on web from [apiKey] (typically
/// `GOOGLE_MAPS_API_KEY` in `.env`). No-op on other platforms.
Future<void> loadGoogleMapsJsIfNeeded(String apiKey) =>
    loadGoogleMapsJsIfNeededImpl(apiKey);
