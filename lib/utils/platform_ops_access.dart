/// Platform Ops permission keys and helpers (owner + scoped seats).
library;

import 'app_env.dart';
import 'helpers.dart';

const kPlatformOwnerEmail = 'suraj6784@gmail.com';

const kOpsPermissionDashboard = 'dashboard';
const kOpsPermissionAnalytics = 'analytics';
const kOpsPermissionCrm = 'crm';
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
  kOpsPermissionAnalytics,
  kOpsPermissionCrm,
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
    case kOpsPermissionAnalytics:
      return 'Analytics';
    case kOpsPermissionCrm:
      return 'CRM';
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
  OpsNavGroup('Overview', [
    kOpsPermissionDashboard,
    kOpsPermissionAnalytics,
    kOpsPermissionCrm,
    kOpsPermissionProfile,
  ]),
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

int _opsInt(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

double _opsDouble(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0;

class OpsNamedCount {
  const OpsNamedCount({required this.label, required this.count});

  final String label;
  final int count;

  factory OpsNamedCount.fromJson(Map<String, dynamic> json) {
    return OpsNamedCount(
      label: json['label']?.toString() ?? json['status']?.toString() ?? json['role']?.toString() ?? '',
      count: _opsInt(json['count'] ?? json['value']),
    );
  }
}

class OpsKitchenRank {
  const OpsKitchenRank({
    required this.chefId,
    required this.name,
    required this.orderCount,
    required this.gmv,
  });

  final String chefId;
  final String name;
  final int orderCount;
  final double gmv;

  factory OpsKitchenRank.fromJson(Map<String, dynamic> json) {
    return OpsKitchenRank(
      chefId: json['chef_id']?.toString() ?? json['id']?.toString() ?? '',
      name: (json['name']?.toString() ?? json['kitchen']?.toString() ?? 'Kitchen').trim(),
      orderCount: _opsInt(json['order_count']),
      gmv: _opsDouble(json['gmv']),
    );
  }
}

class OpsAdminHq {
  const OpsAdminHq({
    required this.snapshot,
    required this.chefCount,
    required this.dinerCount,
    required this.driverCount,
    required this.newUsers,
    required this.pendingKyc,
    required this.pendingFssai,
    required this.openTickets,
    required this.openDisputes,
    required this.failedRefunds,
    required this.liveMeals,
    required this.userCount,
    required this.topKitchens,
    required this.ticketsByStatus,
    required this.usersByRole,
    this.slaBreached = 0,
    this.avgCsat = 0,
    this.repeat7d = 0,
    this.repeat30d = 0,
    this.churn21d = 0,
    this.referredAccounts = 0,
    this.organicAccounts = 0,
    this.refundVelocity = 0,
    this.fraudFlags = 0,
    this.forecastGmv7d = 0,
  });

  final OpsTransactionSnapshot snapshot;
  final int chefCount;
  final int dinerCount;
  final int driverCount;
  final int newUsers;
  final int pendingKyc;
  final int pendingFssai;
  final int openTickets;
  final int openDisputes;
  final int failedRefunds;
  final int liveMeals;
  final int userCount;
  final List<OpsKitchenRank> topKitchens;
  final List<OpsNamedCount> ticketsByStatus;
  final List<OpsNamedCount> usersByRole;
  final int slaBreached;
  final double avgCsat;
  final int repeat7d;
  final int repeat30d;
  final int churn21d;
  final int referredAccounts;
  final int organicAccounts;
  final int refundVelocity;
  final int fraudFlags;
  final double forecastGmv7d;

  double get fulfillmentRate {
    final n = snapshot.orderCount;
    if (n <= 0) return 0;
    return snapshot.deliveredCount / n;
  }

  double get cancelRate {
    final n = snapshot.orderCount;
    if (n <= 0) return 0;
    return snapshot.cancelledCount / n;
  }

  factory OpsAdminHq.fromJson(Map<String, dynamic>? json) {
    final raw = json ?? const <String, dynamic>{};
    final snapRaw = raw['snapshot'];
    final snapMap = snapRaw is Map
        ? Map<String, dynamic>.from(snapRaw)
        : Map<String, dynamic>.from(raw);
    List<Map<String, dynamic>> asMaps(dynamic value) {
      if (value is! List) return const [];
      return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }

    final roles = asMaps(raw['users_by_role']);
    int roleCount(String needle) {
      for (final row in roles) {
        if ((row['role']?.toString() ?? row['label']?.toString() ?? '').toLowerCase() == needle) {
          return _opsInt(row['count']);
        }
      }
      return 0;
    }

    return OpsAdminHq(
      snapshot: OpsTransactionSnapshot.fromJson(snapMap),
      chefCount: raw.containsKey('chef_count') ? _opsInt(raw['chef_count']) : roleCount('chef'),
      dinerCount: raw.containsKey('diner_count')
          ? _opsInt(raw['diner_count'])
          : roleCount('customer') + roleCount('diner'),
      driverCount: raw.containsKey('driver_count') ? _opsInt(raw['driver_count']) : roleCount('driver'),
      newUsers: _opsInt(raw['new_users']),
      pendingKyc: _opsInt(raw['pending_kyc']),
      pendingFssai: _opsInt(raw['pending_fssai']),
      openTickets: _opsInt(raw['open_tickets']),
      openDisputes: _opsInt(raw['open_disputes']),
      failedRefunds: _opsInt(raw['failed_refunds']),
      liveMeals: _opsInt(raw['live_meals']),
      userCount: _opsInt(raw['user_count']),
      topKitchens: asMaps(raw['top_kitchens']).map(OpsKitchenRank.fromJson).toList(),
      ticketsByStatus: asMaps(raw['tickets_by_status']).map(OpsNamedCount.fromJson).toList(),
      usersByRole: roles.map(OpsNamedCount.fromJson).toList(),
      slaBreached: _opsInt(raw['sla_breached']),
      avgCsat: _opsDouble(raw['avg_csat']),
      repeat7d: _opsInt(raw['repeat_7d']),
      repeat30d: _opsInt(raw['repeat_30d']),
      churn21d: _opsInt(raw['churn_21d']),
      referredAccounts: _opsInt(raw['referred_accounts']),
      organicAccounts: _opsInt(raw['organic_accounts']),
      refundVelocity: _opsInt(raw['refund_velocity']),
      fraudFlags: _opsInt(raw['fraud_flags']),
      forecastGmv7d: _opsDouble(raw['forecast_gmv_7d']),
    );
  }
}

class OpsCrmContact {
  const OpsCrmContact({
    required this.id,
    required this.role,
    required this.name,
    required this.email,
    required this.phone,
    required this.accountStatus,
    required this.fssaiStatus,
    required this.kitchenName,
    required this.orderCount,
    required this.gmv,
    required this.lastOrderAt,
    required this.openTickets,
    required this.createdAt,
    required this.lastNote,
  });

  final String id;
  final String role;
  final String name;
  final String email;
  final String phone;
  final String accountStatus;
  final String fssaiStatus;
  final String kitchenName;
  final int orderCount;
  final double gmv;
  final String lastOrderAt;
  final int openTickets;
  final String createdAt;
  final String lastNote;

  factory OpsCrmContact.fromJson(Map<String, dynamic> json) {
    final display = [
      json['full_name']?.toString(),
      json['name']?.toString(),
      json['kitchen_name']?.toString(),
    ].where((v) => v != null && v.trim().isNotEmpty).map((v) => v!.trim());
    return OpsCrmContact(
      id: json['id']?.toString() ?? '',
      role: (json['role']?.toString() ?? '').toLowerCase(),
      name: display.isEmpty ? 'Account' : display.first,
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      accountStatus: (json['account_status']?.toString() ?? 'active').toLowerCase(),
      fssaiStatus: (json['fssai_verification_status']?.toString() ?? '').toLowerCase(),
      kitchenName: json['kitchen_name']?.toString() ?? '',
      orderCount: _opsInt(json['order_count']),
      gmv: _opsDouble(json['gmv']),
      lastOrderAt: json['last_order_at']?.toString() ?? '',
      openTickets: _opsInt(json['open_tickets']),
      createdAt: json['created_at']?.toString() ?? '',
      lastNote: json['last_note']?.toString() ?? '',
    );
  }
}

List<OpsCrmContact> parseOpsCrmDirectory(dynamic raw) {
  if (raw is List) {
    return raw.whereType<Map>().map((e) => OpsCrmContact.fromJson(Map<String, dynamic>.from(e))).toList();
  }
  if (raw is Map) {
    final inner = raw['contacts'] ?? raw['rows'] ?? raw['data'];
    return parseOpsCrmDirectory(inner);
  }
  return const [];
}
