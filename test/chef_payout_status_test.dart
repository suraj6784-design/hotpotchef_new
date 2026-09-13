import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/chef_payout_status.dart';

void main() {
  group('ChefPayoutStatus.classify', () {
    test('missing when no gateway id is stored', () {
      expect(
        ChefPayoutStatus.classify(accountId: ''),
        ChefPayoutLinkKind.missing,
      );
    });

    test('mock for acc_mock_* or mock mode', () {
      expect(
        ChefPayoutStatus.classify(accountId: 'acc_mock_1700'),
        ChefPayoutLinkKind.mock,
      );
      expect(
        ChefPayoutStatus.classify(accountId: 'acc_RZPtest', mockFlag: true),
        ChefPayoutLinkKind.mock,
      );
      expect(
        ChefPayoutStatus.classify(accountId: 'acc_RZPtest', mode: 'mock'),
        ChefPayoutLinkKind.mock,
      );
    });

    test('test-linked for a real acc_ from Test mode', () {
      expect(
        ChefPayoutStatus.classify(accountId: 'acc_RZPtest123', mode: 'test'),
        ChefPayoutLinkKind.testLinked,
      );
      expect(
        ChefPayoutStatus.classify(accountId: 'acc_RZPtest123'),
        ChefPayoutLinkKind.testLinked,
      );
    });

    test('live-linked only when mode is live', () {
      expect(
        ChefPayoutStatus.classify(accountId: 'acc_Live', mode: 'live'),
        ChefPayoutLinkKind.liveLinked,
      );
    });
  });

  group('ChefPayoutStatus copy', () {
    test('does not call mock or test accounts live-verified', () {
      expect(
        ChefPayoutStatus.title(ChefPayoutLinkKind.mock),
        isNot(contains('Direct Settlement Active')),
      );
      expect(
        ChefPayoutStatus.title(ChefPayoutLinkKind.testLinked),
        contains('Test mode'),
      );
      expect(
        ChefPayoutStatus.snackBarMessage(ChefPayoutLinkKind.testLinked),
        contains('not a live settlement'),
      );
      expect(ChefPayoutStatus.canRelink(ChefPayoutLinkKind.mock), isTrue);
      expect(ChefPayoutStatus.canRelink(ChefPayoutLinkKind.testLinked), isFalse);
    });
  });
}
