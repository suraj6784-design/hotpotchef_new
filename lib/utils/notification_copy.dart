import 'dart:convert';

import '../models/app_role.dart';

class OrderAlertCopy {
  const OrderAlertCopy({
    required this.title,
    required this.body,
    required this.notifyChef,
    required this.notifyCustomer,
    this.notifyDriver = false,
  });

  final String title;
  final String body;
  final bool notifyChef;
  final bool notifyCustomer;
  final bool notifyDriver;
}

String mealTitleFromItems(dynamic items) {
  dynamic parsed = items;
  if (items is String && items.trim().isNotEmpty) {
    try {
      parsed = jsonDecode(items);
    } catch (_) {
      parsed = items;
    }
  }
  if (parsed is List && parsed.isNotEmpty) {
    final first = parsed.first;
    if (first is Map) {
      final title = first['title'] ?? first['name'] ?? first['meal_name'];
      if (title != null && title.toString().trim().isNotEmpty) {
        return title.toString().trim();
      }
    }
  }
  return 'your order';
}

String chatPreview(String? content) {
  final text = (content ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) return 'New message in your HotPotChef chat.';
  if (text.length <= 80) return text;
  return '${text.substring(0, 77)}...';
}

String orderGroupAlertTitle(String? roomId) {
  final id = (roomId ?? '').trim();
  if (id.isEmpty) return 'New message';
  final label = id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();
  return 'Order $label';
}

/// One push stage per kitchen/delivery milestone so Confirmed and Preparing
/// do not both fire "Order confirmed".
String orderAlertStage(String? status) {
  final current = status?.trim().toLowerCase() ?? '';
  if (current.contains('cancel') || current.contains('reject')) return 'cancelled';
  if (current.contains('out for delivery') ||
      current.contains('out_for_delivery') ||
      (current.contains('out') && current.contains('deliver') && !current.contains('delivered'))) {
    return 'out';
  }
  if (current.contains('deliver') || current.contains('complet')) return 'delivered';
  if (current.contains('assign')) return 'assigned';
  if (current.contains('ready') || current.contains('pack')) return 'ready';
  if (current.contains('prepar')) return 'preparing';
  if (current.contains('confirm')) return 'confirmed';
  if (current.contains('pending') || current == 'placed' || current == 'new' || current.isEmpty) {
    return 'new';
  }
  return current;
}

OrderAlertCopy? orderAlertCopy({
  required String status,
  required bool isInsert,
  String? previousStatus,
  String mealTitle = 'your order',
}) {
  final stage = orderAlertStage(status);
  final previous = orderAlertStage(previousStatus);
  if (!isInsert && stage == previous) return null;

  if (stage == 'new') {
    return OrderAlertCopy(
      title: 'New order',
      body: 'You have a new order for $mealTitle.',
      notifyChef: true,
      notifyCustomer: false,
    );
  }
  if (stage == 'cancelled') {
    return OrderAlertCopy(
      title: 'Order cancelled',
      body: 'The order for $mealTitle was cancelled. A refund is issued if you paid online.',
      notifyChef: true,
      notifyCustomer: true,
    );
  }
  if (stage == 'delivered') {
    return const OrderAlertCopy(
      title: 'Order delivered',
      body: 'Your order has arrived. Rate the kitchen when you can.',
      notifyChef: false,
      notifyCustomer: true,
    );
  }
  if (stage == 'out') {
    return OrderAlertCopy(
      title: 'On the way',
      body: '$mealTitle is out for delivery. Track it from Orders.',
      notifyChef: false,
      notifyCustomer: true,
    );
  }
  if (stage == 'assigned') {
    return const OrderAlertCopy(
      title: 'Delivery partner assigned',
      body: 'A delivery partner is on the way to the kitchen.',
      notifyChef: false,
      notifyCustomer: true,
    );
  }
  if (stage == 'ready') {
    return OrderAlertCopy(
      title: 'Your box is packed',
      body: '$mealTitle is packed. Open the order to see the kitchen photo.',
      notifyChef: false,
      notifyCustomer: true,
      notifyDriver: true,
    );
  }
  if (stage == 'confirmed') {
    return OrderAlertCopy(
      title: 'Order confirmed',
      body: 'Your order for $mealTitle is being prepared.',
      notifyChef: false,
      notifyCustomer: true,
    );
  }
  return null;
}

class KitchenLiveAlertCopy {
  const KitchenLiveAlertCopy({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

KitchenLiveAlertCopy kitchenLiveAlertCopy({String chefName = 'A home kitchen'}) {
  final name = chefName.trim().isEmpty ? 'A home kitchen' : chefName.trim();
  return KitchenLiveAlertCopy(
    title: '$name is open',
    body: '$name just opened. Order leftovers and today\'s meals now.',
  );
}

class LeadAlertCopy {
  const LeadAlertCopy({
    required this.title,
    required this.body,
    required this.notifyAllChefs,
    required this.notifyClaimedChef,
    required this.notifyCustomer,
  });

  final String title;
  final String body;
  final bool notifyAllChefs;
  final bool notifyClaimedChef;
  final bool notifyCustomer;
}

LeadAlertCopy? leadAlertCopy({
  required String status,
  required bool isInsert,
  String? previousStatus,
  String title = 'Catering lead',
}) {
  final current = status.trim().toLowerCase();
  final previous = previousStatus?.trim().toLowerCase() ?? '';
  if (!isInsert && current == previous) return null;

  final label = title.trim().isEmpty ? 'Catering lead' : title.trim();

  if (isInsert && (current.isEmpty || current == 'open')) {
    return LeadAlertCopy(
      title: 'New catering lead',
      body: '$label is open. Submit a quote from Leads.',
      notifyAllChefs: true,
      notifyClaimedChef: false,
      notifyCustomer: false,
    );
  }
  if (current == 'accepted') {
    return LeadAlertCopy(
      title: 'Kitchen selected',
      body: 'A kitchen was chosen for $label. Confirm and pay from My Orders.',
      notifyAllChefs: false,
      notifyClaimedChef: true,
      notifyCustomer: true,
    );
  }
  if (current.contains('cancel')) {
    return LeadAlertCopy(
      title: 'Catering lead cancelled',
      body: '$label was cancelled.',
      notifyAllChefs: false,
      notifyClaimedChef: true,
      notifyCustomer: false,
    );
  }
  return null;
}

class KycReminderCopy {
  const KycReminderCopy({required this.title, required this.body});

  final String title;
  final String body;
}

KycReminderCopy kycReminderCopy({
  required String role,
  List<String> missing = const [],
}) {
  final parsed = AppRole.parse(role);
  final needed = missing.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (!parsed.requiresKitchenFssai && !parsed.requiresDriverKyc) {
    return const KycReminderCopy(
      title: 'Your diner profile',
      body: 'Diners do not submit FSSAI. Open Profile for addresses, coins, and dietary preferences.',
    );
  }
  final isDriver = parsed.requiresDriverKyc;
  if (needed.isEmpty) {
    return KycReminderCopy(
      title: 'Complete your KYC',
      body: isDriver
          ? 'HotPotChef still needs your delivery-partner KYC. Open Profile and finish the missing details.'
          : 'HotPotChef still needs your kitchen KYC. Open Profile and finish the missing details.',
    );
  }
  final listed = needed.take(8).join(', ');
  final extra = needed.length > 8 ? ' and more' : '';
  return KycReminderCopy(
    title: 'Complete your KYC',
    body: isDriver
        ? 'Still needed: $listed$extra. Open Profile to finish so we can keep you on jobs.'
        : 'Still needed: $listed$extra. Open Profile to finish so we can keep your kitchen live.',
  );
}
