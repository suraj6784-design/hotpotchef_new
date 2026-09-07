// lib/models/driver_delivery_model.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../utils/helpers.dart';

enum DeliveryStatus {
  waitingKitchen,
  readyForPickup,
  accepted,
  pickedUp,
  outForDelivery,
  delivered,
  cancelled;

  static DeliveryStatus fromString(String? val) {
    final s = val?.toLowerCase().trim() ?? '';
    if (s.contains('cancel')) return DeliveryStatus.cancelled;
    if (s.contains('out')) return DeliveryStatus.outForDelivery;
    if (s.contains('deliver') || s.contains('completed')) return DeliveryStatus.delivered;
    if (s.contains('assigned') || s == 'accepted') return DeliveryStatus.accepted;
    if (s.contains('ready')) return DeliveryStatus.readyForPickup;
    if (s.contains('pickup') || s.contains('picked')) return DeliveryStatus.pickedUp;
    if (s.contains('pending') || s.contains('confirm') || s.contains('prepar') || s == 'placed' || s == 'new') {
      return DeliveryStatus.waitingKitchen;
    }
    return DeliveryStatus.waitingKitchen;
  }

  String toDbValue() {
    switch (this) {
      case DeliveryStatus.waitingKitchen:
        return 'Pending Chef Approval';
      case DeliveryStatus.readyForPickup:
        return 'Ready for Pickup';
      case DeliveryStatus.accepted:
        return 'Driver Assigned';
      case DeliveryStatus.pickedUp:
        return 'Ready for Pickup';
      case DeliveryStatus.outForDelivery:
        return 'Out for Delivery';
      case DeliveryStatus.delivered:
        return 'Delivered';
      case DeliveryStatus.cancelled:
        return 'Cancelled';
    }
  }
}

@immutable
class DriverDeliveryModel {
  final String orderId;
  final String orderNumber;
  final String chefId;
  final String chefName;
  final String pickupAddress;
  final String customerAddress;
  final String customerId;
  final String chatRoomId;
  final String itemsSummary;
  final double payout;
  final double distanceKm;
  final int totalItemsCount;
  final DeliveryStatus status;
  final String statusLabel;
  final DateTime createdAt;
  final String timeSlot;
  final String? selectedDate;
  final double? pickupLat;
  final double? pickupLng;
  final double? deliveryLat;
  final double? deliveryLng;

  const DriverDeliveryModel({
    required this.orderId,
    this.orderNumber = '',
    required this.chefId,
    required this.chefName,
    required this.pickupAddress,
    required this.customerAddress,
    this.customerId = '',
    this.chatRoomId = '',
    this.itemsSummary = '',
    required this.payout,
    this.distanceKm = 0.0,
    this.totalItemsCount = 1,
    required this.status,
    this.statusLabel = '',
    required this.createdAt,
    this.timeSlot = '',
    this.selectedDate,
    this.pickupLat,
    this.pickupLng,
    this.deliveryLat,
    this.deliveryLng,
  });

  String get displayOrderNumber =>
      orderNumber.isNotEmpty ? orderNumber : formatOrderId(null, orderId);

  String get dropoffBrief => briefDriverAddress(customerAddress);

  /// One-line reference under the kitchen name on Home history.
  String get driverHistoryDetail {
    final parts = <String>[];
    if (itemsSummary.isNotEmpty) parts.add(itemsSummary);
    if (dropoffBrief.isNotEmpty) parts.add(dropoffBrief);
    return parts.join(' · ');
  }

  Map<String, dynamic> get slotSource => {
        'created_at': createdAt.toIso8601String(),
        'time_slot': timeSlot,
        if (selectedDate != null && selectedDate!.isNotEmpty) 'selected_date': selectedDate,
      };

  /// After Start Delivery / Out for Delivery → navigate to customer; before that → kitchen.
  bool get navigateToCustomer => driverRunIsOutForDelivery(statusLabel.isEmpty ? status.toDbValue() : statusLabel);

  String get navigateLeg => navigateToCustomer ? 'dropoff' : 'pickup';

  String get navigateButtonLabel =>
      navigateToCustomer ? 'Navigate to customer' : 'Navigate to kitchen';

  String get activeStepTitle =>
      navigateToCustomer ? 'Deliver to customer' : 'Pickup from $chefName';

  String get pickupCoordLabel => formatMapCoordinateLabel(pickupLat, pickupLng);

  String get dropoffCoordLabel => formatMapCoordinateLabel(deliveryLat, deliveryLng);

  Map<String, dynamic> toTrackingOrderExtra() => {
        'id': orderId,
        'status': statusLabel.isEmpty ? status.toDbValue() : statusLabel,
        'delivery_address': customerAddress,
        'pickup_address': pickupAddress,
        'chef_address': pickupAddress,
        'hosting_address': pickupAddress,
        'title': chefName,
        'chef_id': chefId,
        'customer_id': customerId,
        'navigate_leg': navigateLeg,
        if (pickupLat != null) 'pickup_lat': pickupLat,
        if (pickupLng != null) 'pickup_lng': pickupLng,
        if (pickupLat != null) 'chef_lat': pickupLat,
        if (pickupLng != null) 'chef_lng': pickupLng,
        if (deliveryLat != null) 'delivery_lat': deliveryLat,
        if (deliveryLng != null) 'delivery_lng': deliveryLng,
      };

  factory DriverDeliveryModel.fromJson(Map<String, dynamic> json) {
    final chef = _embeddedMap(json['chefs'] ?? json['chef'] ?? json['_chef_pin']);
    final items = _itemsFrom(json['items'] ?? json['cart_items'] ?? json['order_items']);
    final first = items.isNotEmpty ? items.first : const <String, dynamic>{};
    final nestedMeal = first['rawMealDetails'] ?? first['mealDetails'] ?? first['meal_details'];
    final mealMap = nestedMeal is Map ? Map<String, dynamic>.from(nestedMeal) : const <String, dynamic>{};
    final itemsSummary = driverOrderItemsSummary(items);
    final totalQty = items.fold<int>(0, (sum, item) {
      final qty = int.tryParse(item['quantity']?.toString() ?? '') ?? 1;
      return sum + (qty < 1 ? 1 : qty);
    });

    final pickup = orderPickupAddress(json, items: [...items, mealMap, if (chef != null) chef]);
    final chefFormatted = formatSavedAddress(chef);
    final resolvedPickup = pickup.isNotEmpty
        ? pickup
        : (chefFormatted.isNotEmpty
            ? chefFormatted
            : (chef?['address']?.toString().trim() ?? ''));

    final dropoff = orderDropoffAddress(json, items: items);
    final resolvedDropoff = dropoff.isNotEmpty ? dropoff : (json['delivery_address']?.toString() ?? '');

    final pickupLat = kitchenCoordinate(json, latitude: true) ??
        kitchenCoordinate(first, latitude: true) ??
        kitchenCoordinate(mealMap, latitude: true) ??
        kitchenCoordinate(chef, latitude: true);
    final pickupLng = kitchenCoordinate(json, latitude: false) ??
        kitchenCoordinate(first, latitude: false) ??
        kitchenCoordinate(mealMap, latitude: false) ??
        kitchenCoordinate(chef, latitude: false);

    final dropLat = double.tryParse(json['delivery_lat']?.toString() ?? '') ??
        addressCoordinate({
          'lat': json['customer_lat'],
          'latitude': json['customer_lat'],
        }, latitude: true);
    final dropLng = double.tryParse(json['delivery_lng']?.toString() ?? '') ??
        addressCoordinate({
          'lng': json['customer_lng'],
          'longitude': json['customer_lng'],
        }, latitude: false);

    final orderId = json['id']?.toString() ?? '';
    return DriverDeliveryModel(
      orderId: orderId,
      orderNumber: formatOrderId(json['order_id']?.toString(), orderId),
      chefId: json['chef_id']?.toString() ?? '',
      chefName: json['chef_name']?.toString() ??
          chef?['business_name']?.toString() ??
          chef?['name']?.toString() ??
          chef?['full_name']?.toString() ??
          'Chef Kitchen',
      pickupAddress: resolvedPickup.isEmpty ? 'Kitchen address pending' : resolvedPickup,
      customerAddress: resolvedDropoff.isEmpty ? 'Customer address pending' : resolvedDropoff,
      customerId: json['customer_id']?.toString() ?? json['user_id']?.toString() ?? '',
      chatRoomId: orderChatRoomId(json, items: items),
      itemsSummary: itemsSummary,
      payout: driverPayoutFromOrder(json),
      distanceKm: (json['estimated_distance_km'] as num?)?.toDouble() ?? 0.0,
      totalItemsCount: totalQty > 0 ? totalQty : (items.isEmpty ? 1 : items.length),
      status: DeliveryStatus.fromString(json['status']?.toString()),
      statusLabel: json['status']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      timeSlot: json['time_slot']?.toString() ??
          first['time_slot']?.toString() ??
          first['timeSlot']?.toString() ??
          json['delivery_slot']?.toString() ??
          '',
      selectedDate: json['selected_date']?.toString() ?? first['selected_date']?.toString(),
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      deliveryLat: dropLat,
      deliveryLng: dropLng,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DriverDeliveryModel &&
          runtimeType == other.runtimeType &&
          orderId == other.orderId &&
          status == other.status;

  @override
  int get hashCode => orderId.hashCode ^ status.hashCode;
}

Map<String, dynamic>? _embeddedMap(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is List && raw.isNotEmpty && raw.first is Map) {
    return Map<String, dynamic>.from(raw.first as Map);
  }
  return null;
}

List<Map<String, dynamic>> _itemsFrom(dynamic raw) {
  if (raw == null) return const [];
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is List) {
      return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
  } catch (_) {}
  return const [];
}

@immutable
class DriverDashboardState {
  final bool isLoading;
  final double totalEarnings;
  final int completedCount;
  final List<DriverDeliveryModel> recentDeliveries;
  final List<DriverDeliveryModel> availableDeliveries;
  final List<DriverDeliveryModel> activeDeliveries;
  final String? errorMessage;

  const DriverDashboardState({
    this.isLoading = true,
    this.totalEarnings = 0.0,
    this.completedCount = 0,
    this.recentDeliveries = const [],
    this.availableDeliveries = const [],
    this.activeDeliveries = const [],
    this.errorMessage,
  });

  DriverDashboardState copyWith({
    bool? isLoading,
    double? totalEarnings,
    int? completedCount,
    List<DriverDeliveryModel>? recentDeliveries,
    List<DriverDeliveryModel>? availableDeliveries,
    List<DriverDeliveryModel>? activeDeliveries,
    String? errorMessage,
  }) {
    return DriverDashboardState(
      isLoading: isLoading ?? this.isLoading,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      completedCount: completedCount ?? this.completedCount,
      recentDeliveries: recentDeliveries ?? this.recentDeliveries,
      availableDeliveries: availableDeliveries ?? this.availableDeliveries,
      activeDeliveries: activeDeliveries ?? this.activeDeliveries,
      errorMessage: errorMessage,
    );
  }
}
