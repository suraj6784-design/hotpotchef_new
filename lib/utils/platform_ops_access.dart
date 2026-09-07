/// Platform Ops permission keys and helpers (owner + scoped seats).
library;

const kPlatformOwnerEmail = 'suraj6784@gmail.com';

const kOpsPermissionDashboard = 'dashboard';
const kOpsPermissionPackaging = 'packaging';
const kOpsPermissionFssai = 'fssai';
const kOpsPermissionBrands = 'brands';
const kOpsPermissionRefunds = 'refunds';
const kOpsPermissionTickets = 'tickets';
const kOpsPermissionKyc = 'kyc';
const kOpsPermissionAccounts = 'accounts';
const kOpsPermissionHelpers = 'helpers';

/// Scopes that can be granted via helper invite codes.
const kOpsInviteablePermissions = <String>[
  kOpsPermissionDashboard,
  kOpsPermissionPackaging,
  kOpsPermissionFssai,
  kOpsPermissionBrands,
  kOpsPermissionRefunds,
  kOpsPermissionTickets,
  kOpsPermissionKyc,
];

const kOpsAllPermissions = <String>[
  ...kOpsInviteablePermissions,
  kOpsPermissionAccounts,
  kOpsPermissionHelpers,
];

String opsPermissionLabel(String key) {
  switch (key.toLowerCase().trim()) {
    case kOpsPermissionDashboard:
      return 'Dashboard';
    case kOpsPermissionPackaging:
      return 'Packaging';
    case kOpsPermissionFssai:
      return 'FSSAI';
    case kOpsPermissionBrands:
      return 'Brands';
    case kOpsPermissionRefunds:
      return 'Refunds';
    case kOpsPermissionTickets:
      return 'Tickets';
    case kOpsPermissionKyc:
      return 'KYC';
    case kOpsPermissionAccounts:
      return 'Accounts';
    case kOpsPermissionHelpers:
      return 'Helpers';
    default:
      return key;
  }
}

bool isPlatformOwnerEmail(String? email) {
  final value = (email ?? '').trim().toLowerCase();
  return value.isNotEmpty && value == kPlatformOwnerEmail.toLowerCase();
}

List<String> normalizeOpsPermissions(dynamic raw, {bool owner = false}) {
  if (owner) return List<String>.from(kOpsAllPermissions);
  final out = <String>{};
  if (raw is Iterable) {
    for (final item in raw) {
      final key = item?.toString().trim().toLowerCase() ?? '';
      if (kOpsAllPermissions.contains(key)) out.add(key);
    }
  }
  return out.toList()..sort();
}

bool opsPermissionsContain(Iterable<String> permissions, String key, {bool owner = false}) {
  if (owner) return true;
  final needle = key.trim().toLowerCase();
  return permissions.map((p) => p.toLowerCase()).contains(needle);
}

class OpsTransactionSnapshot {
  const OpsTransactionSnapshot({
    required this.period,
    required this.gmv,
    required this.orderCount,
    required this.deliveredCount,
    required this.cancelledCount,
    required this.deliveryFeeSum,
    required this.avgTicket,
    required this.series,
    required this.recent,
  });

  final String period;
  final double gmv;
  final int orderCount;
  final int deliveredCount;
  final int cancelledCount;
  final double deliveryFeeSum;
  final double avgTicket;
  final List<OpsSnapshotBucket> series;
  final List<Map<String, dynamic>> recent;

  factory OpsTransactionSnapshot.fromJson(Map<String, dynamic>? json) {
    final raw = json ?? const <String, dynamic>{};
    final seriesRaw = raw['series'];
    final recentRaw = raw['recent'];
    return OpsTransactionSnapshot(
      period: raw['period']?.toString() ?? 'day',
      gmv: double.tryParse(raw['gmv']?.toString() ?? '') ?? 0,
      orderCount: int.tryParse(raw['order_count']?.toString() ?? '') ?? 0,
      deliveredCount: int.tryParse(raw['delivered_count']?.toString() ?? '') ?? 0,
      cancelledCount: int.tryParse(raw['cancelled_count']?.toString() ?? '') ?? 0,
      deliveryFeeSum: double.tryParse(raw['delivery_fee_sum']?.toString() ?? '') ?? 0,
      avgTicket: double.tryParse(raw['avg_ticket']?.toString() ?? '') ?? 0,
      series: seriesRaw is List
          ? seriesRaw
              .whereType<Map>()
              .map((e) => OpsSnapshotBucket.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      recent: recentRaw is List
          ? recentRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const [],
    );
  }
}

class OpsSnapshotBucket {
  const OpsSnapshotBucket({required this.bucketDate, required this.gmv, required this.orderCount});

  final String bucketDate;
  final double gmv;
  final int orderCount;

  factory OpsSnapshotBucket.fromJson(Map<String, dynamic> json) {
    return OpsSnapshotBucket(
      bucketDate: json['bucket_date']?.toString() ?? '',
      gmv: double.tryParse(json['gmv']?.toString() ?? '') ?? 0,
      orderCount: int.tryParse(json['order_count']?.toString() ?? '') ?? 0,
    );
  }
}
