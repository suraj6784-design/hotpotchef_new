import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/platform_ops_access.dart';

void main() {
  group('platform ops access', () {
    test('owner email match is case-insensitive', () {
      expect(isPlatformOwnerEmail('Suraj6784@gmail.com'), isTrue);
      expect(isPlatformOwnerEmail('other@example.com'), isFalse);
    });

    test('owner gets all permissions when normalizing', () {
      expect(normalizeOpsPermissions([], owner: true), kOpsAllPermissions);
    });

    test('helper username maps to a reserved login email', () {
      expect(resolveAuthLoginEmail('Fssai.Reviewer'), 'fssai.reviewer@$kOpsHelperEmailDomain');
      expect(resolveAuthLoginEmail('helper@kitchen.com'), 'helper@kitchen.com');
      expect(opsHelperUsernameFromEmail('fssai.reviewer@$kOpsHelperEmailDomain'), 'fssai.reviewer');
    });

    test('inviteable set excludes accounts, helpers, and catalog', () {
      expect(kOpsInviteablePermissions.contains(kOpsPermissionAccounts), isFalse);
      expect(kOpsInviteablePermissions.contains(kOpsPermissionHelpers), isFalse);
      expect(kOpsInviteablePermissions.contains(kOpsPermissionCatalog), isFalse);
      expect(kOpsInviteablePermissions.contains(kOpsPermissionAudit), isFalse);
      expect(kOpsInviteablePermissions.contains(kOpsPermissionFssai), isTrue);
    });

    test('nav groups keep only permissions the seat can open', () {
      final groups = opsNavGroupsFor(['dashboard', 'kyc', 'tickets']);
      expect(groups.map((g) => g.title), ['Overview', 'Kitchen', 'Support']);
      expect(groups[1].keys, ['kyc']);
      expect(opsNavGroupTitleFor(kOpsPermissionKyc), 'Kitchen');
    });

    test('ops snackbars do not echo raw exceptions', () {
      expect(opsFriendlyError(Exception('JWT expired permission denied')), contains('permission'));
      expect(opsFriendlyError('SocketException: Failed host lookup'), contains('Network'));
      expect(opsFriendlyError('weird postgrest 500'), 'Could not complete that action. Try again.');
    });

    test('permission containment', () {
      expect(opsPermissionsContain(['fssai', 'tickets'], 'FSSAI'), isTrue);
      expect(opsPermissionsContain(['fssai'], 'accounts'), isFalse);
      expect(opsPermissionsContain([], 'dashboard', owner: true), isTrue);
    });

    test('snapshot parse', () {
      final snap = OpsTransactionSnapshot.fromJson({
        'period': 'week',
        'gmv': 1200,
        'order_count': 4,
        'delivered_count': 3,
        'cancelled_count': 1,
        'delivery_fee_sum': 80,
        'platform_margin_sum': 168,
        'avg_ticket': 300,
        'series': [
          {'bucket_date': '2026-09-01', 'gmv': 500, 'order_count': 2},
        ],
        'recent': [
          {'id': 'abc', 'total': 250, 'status': 'Delivered'},
        ],
      });
      expect(snap.period, 'week');
      expect(snap.gmv, 1200);
      expect(snap.platformMarginSum, 168);
      expect(snap.series.single.orderCount, 2);
      expect(snap.recent.single['status'], 'Delivered');
    });

    test('snapshot treats a zero platform_margin_sum as unset and estimates 15%', () {
      final snap = OpsTransactionSnapshot.fromJson({
        'gmv': 1000,
        'delivery_fee_sum': 200,
        'platform_margin_sum': 0,
        'order_count': 2,
        'delivered_count': 1,
        'cancelled_count': 0,
        'avg_ticket': 500,
      });
      expect(snap.platformMarginSum, 120);
    });
  });
}
