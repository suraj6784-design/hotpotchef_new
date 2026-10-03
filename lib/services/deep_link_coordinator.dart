// lib/services/deep_link_coordinator.dart
//
// Wires app_links + Supabase passwordRecovery to GoRouter. Injectable streams
// keep the mapping testable without plugins or a running app.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_deep_links.dart';

class DeepLinkCoordinator {
  DeepLinkCoordinator({
    required this.navigate,
    this.currentPath,
    this.linkStream,
    this.getInitialUri,
    this.authEvents,
  });

  final void Function(String location) navigate;
  final String? Function()? currentPath;
  final Stream<Uri>? linkStream;
  final Future<Uri?> Function()? getInitialUri;
  final Stream<AuthChangeEvent>? authEvents;

  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<AuthChangeEvent>? _authSub;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      final initial = await getInitialUri?.call();
      if (initial != null) {
        handleUri(initial);
      }
    } catch (error, stack) {
      debugPrint('⚠️ Deep link initial URI failed: $error');
      debugPrint('$stack');
    }

    _linkSub = linkStream?.listen(
      handleUri,
      onError: (Object error, StackTrace stack) {
        debugPrint('⚠️ Deep link stream error: $error');
        debugPrint('$stack');
      },
    );
    _authSub = authEvents?.listen(handleAuthEvent);
  }

  @visibleForTesting
  void handleUri(Uri uri) {
    final mapped = AppDeepLinks.locationFor(uri);
    if (mapped == null) return;
    if (mapped == AppDeepLinks.cartLocation) {
      navigate(AppDeepLinks.cartLocationFor(currentPath: currentPath?.call()));
      return;
    }
    navigate(mapped);
  }

  @visibleForTesting
  void handleAuthEvent(AuthChangeEvent event) {
    final mapped = AppDeepLinks.locationForAuthEvent(event);
    if (mapped != null) {
      navigate(mapped);
    }
  }

  Future<void> dispose() async {
    await _linkSub?.cancel();
    await _authSub?.cancel();
    _linkSub = null;
    _authSub = null;
  }
}
