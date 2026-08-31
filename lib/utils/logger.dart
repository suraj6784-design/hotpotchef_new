// lib/utils/logger.dart

import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class AppLogger {
  /// Logs non-fatal exceptions. Prints locally in debug mode and reports to Crashlytics in production.
  static void error(dynamic exception, [StackTrace? stackTrace, String? reason]) {
    if (kDebugMode) {
      debugPrint('❌ [ERROR] ${reason != null ? '[$reason] ' : ''}$exception');
      if (stackTrace != null) {
        debugPrint('Stacktrace:\n$stackTrace');
      }
    }

    try {
      if (!kDebugMode) {
        FirebaseCrashlytics.instance.recordError(
          exception,
          stackTrace ?? StackTrace.current,
          reason: reason ?? 'Caught non-fatal exception',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to report error to Crashlytics: $e');
      }
    }
  }

  /// Logs standard debug messages visible only during development.
  static void debug(String message, {String tag = 'APP'}) {
    if (kDebugMode) {
      debugPrint('💬 [$tag] $message');
    }
  }

  /// Logs informative operational events.
  static void info(String message, {String tag = 'APP'}) {
    if (kDebugMode) {
      debugPrint('ℹ️ [$tag] $message');
    }
  }
}

/// Backward-compatible top-level helper wrapping AppLogger.error
void logError(dynamic exception, StackTrace? stackTrace, {String? reason}) {
  AppLogger.error(exception, stackTrace, reason);
}