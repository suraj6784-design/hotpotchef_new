import 'dart:convert';

class OrderAlertCopy {
  const OrderAlertCopy({
    required this.title,
    required this.body,
    required this.notifyChef,
    required this.notifyCustomer,
  });

  final String title;
  final String body;
  final bool notifyChef;
  final bool notifyCustomer;
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

OrderAlertCopy? orderAlertCopy({
  required String status,
  required bool isInsert,
  String? previousStatus,
  String mealTitle = 'your order',
}) {
  final current = status.trim().toLowerCase();
  final previous = previousStatus?.trim().toLowerCase() ?? '';
  if (!isInsert && current == previous) return null;

  if (isInsert || current.contains('pending')) {
    return OrderAlertCopy(
      title: 'New order',
      body: 'You have a new order for $mealTitle.',
      notifyChef: true,
      notifyCustomer: false,
    );
  }
  if (current.contains('cancel')) {
    return OrderAlertCopy(
      title: 'Order cancelled',
      body: 'The order for $mealTitle was cancelled. A refund is issued if you paid online.',
      notifyChef: true,
      notifyCustomer: true,
    );
  }
  if (current.contains('deliver') || current.contains('complet')) {
    return const OrderAlertCopy(
      title: 'Order delivered',
      body: 'Your order has arrived. Rate the kitchen when you can.',
      notifyChef: false,
      notifyCustomer: true,
    );
  }
  if (current.contains('out for delivery') || current.contains('out_for_delivery')) {
    return OrderAlertCopy(
      title: 'On the way',
      body: '$mealTitle is out for delivery. Track it from Orders.',
      notifyChef: false,
      notifyCustomer: true,
    );
  }
  if (current.contains('assign')) {
    return const OrderAlertCopy(
      title: 'Delivery partner assigned',
      body: 'A delivery partner is on the way to the kitchen.',
      notifyChef: false,
      notifyCustomer: true,
    );
  }
  if (current.contains('ready')) {
    return OrderAlertCopy(
      title: 'Order ready',
      body: '$mealTitle is ready for pickup.',
      notifyChef: false,
      notifyCustomer: true,
    );
  }
  if (current.contains('prepar') || current.contains('confirm')) {
    return OrderAlertCopy(
      title: 'Order confirmed',
      body: 'Your order for $mealTitle is being prepared.',
      notifyChef: false,
      notifyCustomer: true,
    );
  }
  return null;
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
      body: '$label is open. Claim it from Leads.',
      notifyAllChefs: true,
      notifyClaimedChef: false,
      notifyCustomer: false,
    );
  }
  if (current == 'accepted') {
    return LeadAlertCopy(
      title: 'Chef claimed your lead',
      body: 'A kitchen accepted $label. Confirm and pay from My Orders.',
      notifyAllChefs: false,
      notifyClaimedChef: false,
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
