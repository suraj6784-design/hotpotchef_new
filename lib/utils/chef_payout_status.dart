// Honest chef payout / Razorpay Route linkage labels.
// Real acc_* ids from Test keys are "test-linked", not live-verified settlements.

enum ChefPayoutLinkKind { missing, mock, testLinked, liveLinked }

abstract final class ChefPayoutStatus {
  static ChefPayoutLinkKind classify({
    required String accountId,
    bool? mockFlag,
    String? mode,
  }) {
    final id = accountId.trim();
    final normalizedMode = mode?.trim().toLowerCase();
    if (mockFlag == true || id.startsWith('acc_mock_') || normalizedMode == 'mock') {
      return ChefPayoutLinkKind.mock;
    }
    if (id.isEmpty) return ChefPayoutLinkKind.missing;
    if (normalizedMode == 'live') return ChefPayoutLinkKind.liveLinked;
    return ChefPayoutLinkKind.testLinked;
  }

  static bool canRelink(ChefPayoutLinkKind kind) {
    return kind == ChefPayoutLinkKind.missing || kind == ChefPayoutLinkKind.mock;
  }

  static String title(ChefPayoutLinkKind kind) {
    switch (kind) {
      case ChefPayoutLinkKind.missing:
        return 'Configure Settlement Account';
      case ChefPayoutLinkKind.mock:
        return 'Sandbox payout saved';
      case ChefPayoutLinkKind.testLinked:
        return 'Razorpay Route linked (Test mode)';
      case ChefPayoutLinkKind.liveLinked:
        return 'Direct Settlement Active';
    }
  }

  static String subtitle(ChefPayoutLinkKind kind) {
    switch (kind) {
      case ChefPayoutLinkKind.missing:
        return 'Required for automated split payouts via Razorpay Route.';
      case ChefPayoutLinkKind.mock:
        return 'Local mock account only. Add Razorpay Test keys to create a real Route linked account.';
      case ChefPayoutLinkKind.testLinked:
        return 'Test-mode linked account. Settlements use Razorpay Test Route, not live bank payouts.';
      case ChefPayoutLinkKind.liveLinked:
        return 'Earnings settle automatically to your registered account.';
    }
  }

  static String snackBarMessage(ChefPayoutLinkKind kind) {
    switch (kind) {
      case ChefPayoutLinkKind.missing:
        return 'Payout account is not linked.';
      case ChefPayoutLinkKind.mock:
        return 'Payout details saved in sandbox. Razorpay Route Test keys are not configured.';
      case ChefPayoutLinkKind.testLinked:
        return 'Razorpay Route linked in Test mode. This is not a live settlement account.';
      case ChefPayoutLinkKind.liveLinked:
        return 'Payout account linked.';
    }
  }

  static String chipLabel(ChefPayoutLinkKind kind) {
    switch (kind) {
      case ChefPayoutLinkKind.missing:
        return 'Missing';
      case ChefPayoutLinkKind.mock:
        return 'Mock';
      case ChefPayoutLinkKind.testLinked:
        return 'Test';
      case ChefPayoutLinkKind.liveLinked:
        return 'Active';
    }
  }
}
