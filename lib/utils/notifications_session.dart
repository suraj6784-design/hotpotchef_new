/// Alerts stays mounted on the diner dock. Reload when the session user
/// changes, and again after a failed load for the same user.
bool notificationsInboxShouldReload({
  required bool settled,
  required String? loadedUserId,
  required String? sessionUserId,
  bool previousLoadFailed = false,
}) {
  if (!settled || previousLoadFailed) return true;
  return (loadedUserId ?? '').trim() != (sessionUserId ?? '').trim();
}

/// Signed-out copy only. A real session must not use this message.
String? notificationsSignedOutMessage(String? sessionUserId) {
  if ((sessionUserId ?? '').trim().isEmpty) {
    return 'Sign in to see notifications.';
  }
  return null;
}
