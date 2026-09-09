// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;

Future<void> loadGoogleMapsJsIfNeededImpl(String apiKey) async {
  final key = apiKey.trim();
  if (key.isEmpty || key.contains('YOUR_GOOGLE_MAPS')) {
    return;
  }

  if (html.document.querySelector(
        'script[src*="maps.googleapis.com/maps/api/js"]',
      ) !=
      null) {
    return;
  }

  final completer = Completer<void>();
  final script = html.ScriptElement()
    ..src =
        'https://maps.googleapis.com/maps/api/js?key=${Uri.encodeQueryComponent(key)}'
    ..async = true;

  script.onLoad.listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  script.onError.listen((_) {
    if (!completer.isCompleted) completer.complete();
  });

  html.document.head?.append(script);
  await completer.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () {},
  );
}
