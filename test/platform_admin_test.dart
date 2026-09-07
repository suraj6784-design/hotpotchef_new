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

    test('inviteable set excludes accounts and helpers', () {
      expect(kOpsInviteablePermissions.contains(kOpsPermissionAccounts), isFalse);
      expect(kOpsInviteablePermissions.contains(kOpsPermissionHelpers), isFalse);
      expect(kOpsInviteablePermissions.contains(kOpsPermissionFssai), isTrue);
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
      expect(snap.series.single.orderCount, 2);
      expect(snap.recent.single['status'], 'Delivered');
    });
  });
}
