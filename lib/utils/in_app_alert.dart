import 'package:flutter/material.dart';

/// Stable key so a push and a realtime event for the same cancellation
/// do not queue two identical banners.
String inAppAlertCopyKey(String title, String body) => 'copy:${title.trim()}|${body.trim()}';

/// False when this alert id or the same title/body was already presented.
bool shouldPresentInAppAlert({
  required Set<String> shown,
  required String id,
  required String title,
  required String body,
}) {
  if (shown.contains(id)) return false;
  return !shown.contains(inAppAlertCopyKey(title, body));
}

void rememberInAppAlert(
  Set<String> shown, {
  required String id,
  required String title,
  required String body,
}) {
  shown.add(id);
  shown.add(inAppAlertCopyKey(title, body));
}

/// Order/chat banner. [persist] is false even when [onOpen] is set.
///
/// Flutter otherwise keeps a snackbar with an action on screen, which pins
/// Chef Orders under "Order cancelled" and queues the next message behind it.
SnackBar inAppAlertSnackBar({
  required String message,
  VoidCallback? onOpen,
  Duration duration = const Duration(seconds: 4),
}) {
  return SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
    duration: duration,
    persist: false,
    action: onOpen == null ? null : SnackBarAction(label: 'Open', onPressed: onOpen),
  );
}
