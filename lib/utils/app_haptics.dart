import 'package:flutter/services.dart';

/// Light tactile feedback for docks, CTAs, and page switches.
class AppHaptics {
  static Future<void> selection() => HapticFeedback.selectionClick();

  static Future<void> light() => HapticFeedback.lightImpact();

  static Future<void> medium() => HapticFeedback.mediumImpact();
}
