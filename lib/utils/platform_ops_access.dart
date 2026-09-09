/// Platform Ops permission keys and helpers (owner + scoped seats).
library;

import 'app_env.dart';
import 'helpers.dart';

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
const kOpsPermissionCatalog = 'catalog';
const kOpsPermissionProfile = 'profile';
const kOpsPermissionAudit = 'audit';

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
  kOpsPermissionCatalog,
  kOpsPermissionProfile,
  kOpsPermissionAudit,
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
    case kOpsPermissionCatalog:
      return 'Catalog';
    case kOpsPermissionProfile:
      return 'Profile';
    case kOpsPermissionAudit:
      return 'Audit';
    default:
      return key;
  }
}

class OpsNavGroup {
  const OpsNavGroup(this.title, this.keys);
  final String title;
  final List<String> keys;
}

const kOpsNavGroups = <OpsNavGroup>[
  OpsNavGroup('Overview', [kOpsPermissionDashboard, kOpsPermissionProfile]),
  OpsNavGroup('Kitchen', [
    kOpsPermissionCatalog,
    kOpsPermissionPackaging,
    kOpsPermissionKyc,
    kOpsPermissionFssai,
  ]),
  OpsNavGroup('Growth', [kOpsPermissionBrands]),
  OpsNavGroup('Support', [kOpsPermissionTickets, kOpsPermissionRefunds]),
  OpsNavGroup('Team', [kOpsPermissionAccounts, kOpsPermissionHelpers, kOpsPermissionAudit]),
];

List<OpsNavGroup> opsNavGroupsFor(Iterable<String> availableKeys) {
  final allowed = availableKeys.map((k) => k.trim().toLowerCase()).toSet();
  return [
    for (final group in kOpsNavGroups)
      if (group.keys.any(allowed.contains))
        OpsNavGroup(
          group.title,
          group.keys.where(allowed.contains).toList(growable: false),
        ),
  ];
}

String? opsNavGroupTitleFor(String key) {
  final needle = key.trim().toLowerCase();
  for (final group in kOpsNavGroups) {
    if (group.keys.contains(needle)) return group.title;
  }
  return null;
}

const kOpsHelperEmailDomain = 'helpers.hotpotchef.app';

/// Login field: real email, or a helper username mapped to the reserved domain.
String resolveAuthLoginEmail(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return value;
  if (value.contains('@')) return value;
  final user = value.replaceAll(RegExp(r'[^a-z0-9._-]'), '');
  if (user.length < 3) return value;
  return '$user@$kOpsHelperEmailDomain';
}

String opsHelperUsernameFromEmail(String? email) {
  final value = (email ?? '').trim().toLowerCase();
  const suffix = '@$kOpsHelperEmailDomain';
  if (value.endsWith(suffix)) {
    return value.substring(0, value.length - suffix.length);
  }
  return value;
}

String opsHelperEmailFromUsername(String raw) {
  return resolveAuthLoginEmail(raw);
}

String generateOpsHelperPassword() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
  final rnd = DateTime.now().microsecondsSinceEpoch;
  final buf = StringBuffer();
  var seed = rnd;
  for (var i = 0; i < 10; i++) {
    seed = 1103515245 * seed + 12345;
    buf.write(chars[(seed.abs()) % chars.length]);
  }
  return buf.toString();
}

bool isPlatformOwnerEmail(String? email) {
  final value = (email ?? '').trim().toLowerCase();
  if (value.isEmpty) return false;
  final configured = appEnv('PLATFORM_OWNER_EMAIL').trim().toLowerCase();
  final expected = configured.contains('@') ? configured : kPlatformOwnerEmail.toLowerCase();
  return value == expected;
}

String opsFriendlyError(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('permission') || text.contains('not authorized') || text.contains('jwt')) {
    return 'You do not have permission for this action.';
  }
  if (text.contains('network') || text.contains('timeout') || text.contains('socket') || text.contains('offline')) {
    return 'Network issue. Try again.';
  }
  if (text.contains('group cart') || text.contains('already checked out')) {
    return 'This group cart is no longer open.';
  }
  if (text.contains('already in use') || text.contains('already registered')) {
    return 'That username or email is already in use.';
  }
  return 'Could not complete that action. Try again.';
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
    required this.platformMarginSum,
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
  final double platformMarginSum;
  final double avgTicket;
  final List<OpsSnapshotBucket> series;
  final List<Map<String, dynamic>> recent;

  factory OpsTransactionSnapshot.fromJson(Map<String, dynamic>? json) {
    final raw = json ?? const <String, dynamic>{};
    final seriesRaw = raw['series'];
    final recentRaw = raw['recent'];
    final gmv = double.tryParse(raw['gmv']?.toString() ?? '') ?? 0;
    final deliveryFeeSum = double.tryParse(raw['delivery_fee_sum']?.toString() ?? '') ?? 0;
    final parsedMargin = double.tryParse(raw['platform_margin_sum']?.toString() ?? '');
    final estimated = estimatedPlatformMargin(gmv: gmv, deliveryFeeSum: deliveryFeeSum);
    return OpsTransactionSnapshot(
      period: raw['period']?.toString() ?? 'day',
      gmv: gmv,
      orderCount: int.tryParse(raw['order_count']?.toString() ?? '') ?? 0,
      deliveredCount: int.tryParse(raw['delivered_count']?.toString() ?? '') ?? 0,
      cancelledCount: int.tryParse(raw['cancelled_count']?.toString() ?? '') ?? 0,
      deliveryFeeSum: deliveryFeeSum,
      platformMarginSum: (parsedMargin != null && parsedMargin > 0) ? parsedMargin : estimated,
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
