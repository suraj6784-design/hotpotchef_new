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
      expect(
        ChefPayoutStatus.canRelink(ChefPayoutLinkKind.testLinked),
        isFalse,
      );
    });
  });

  group('Chef profile settlement banner', () {
    test('empty bank fields do not show Direct Settlement Active', () {
      // payout_enabled is false. A non-empty gateway_account_id that is not an
      // acc_* Route id used to flip the Active pill on its own.
      final active = ChefPayoutStatus.showsDirectSettlementActive(
        payoutEnabled: false,
        gatewayAccountId: '112233445566778899',
        beneficiaryName: '',
        bankAccountNumber: '',
        bankIfsc: '',
      );
      expect(active, isFalse);
      expect(
        ChefPayoutStatus.profileBannerTitle(active: active),
        'Configure Settlement Account',
      );
      expect(
        ChefPayoutStatus.profileBannerTitle(active: active),
        isNot(contains('Direct Settlement Active')),
      );
      expect(
        ChefPayoutStatus.profileBannerSubtitle(active: active),
        isNot(contains('settle automatically')),
      );
      expect(
        ChefPayoutStatus.profileBannerPill(active: active),
        isNot('Active'),
      );
      expect(ChefPayoutStatus.profileBannerPill(active: active), isNull);
    });

    test(
      'payout_enabled true still hides Active when bank fields are blank',
      () {
        final active = ChefPayoutStatus.showsDirectSettlementActive(
          payoutEnabled: true,
          gatewayAccountId: 'acc_LiveAccount',
          beneficiaryName: '   ',
          bankAccountNumber: '',
          bankIfsc: '',
        );
        expect(active, isFalse);
        expect(
          ChefPayoutStatus.profileBannerPill(active: active),
          isNot('Active'),
        );
      },
    );

    test('a Route id with only some bank fields does not show Active', () {
      final active = ChefPayoutStatus.showsDirectSettlementActive(
        payoutEnabled: true,
        gatewayAccountId: 'acc_RZPtest123',
        beneficiaryName: 'Kitchen',
        bankAccountNumber: '123456789012',
        bankIfsc: '',
      );
      expect(active, isFalse);
    });

    test('saved bank details with the payout flag show Active', () {
      final active = ChefPayoutStatus.showsDirectSettlementActive(
        payoutEnabled: true,
        gatewayAccountId: '',
        beneficiaryName: 'Home Kitchen',
        bankAccountNumber: '123456789012',
        bankIfsc: 'HDFC0001234',
      );
      expect(active, isTrue);
      expect(
        ChefPayoutStatus.profileBannerTitle(active: active),
        'Direct Settlement Active',
      );
      expect(ChefPayoutStatus.profileBannerPill(active: active), 'Active');
    });

    test(
      'saved bank details still show Active from a non-empty gateway id',
      () {
        // payout_enabled stays false. The pill follows the gateway id once the
        // holder, account number, and IFSC are actually saved.
        final active = ChefPayoutStatus.showsDirectSettlementActive(
          payoutEnabled: false,
          gatewayAccountId: '112233445566778899',
          beneficiaryName: 'Newchef16',
          bankAccountNumber: '123456789012',
          bankIfsc: 'HDFC0000001',
        );
        expect(active, isTrue);
        expect(
          ChefPayoutStatus.profileBannerTitle(active: active),
          'Direct Settlement Active',
        );
        expect(ChefPayoutStatus.profileBannerPill(active: active), 'Active');
      },
    );
  });
}
