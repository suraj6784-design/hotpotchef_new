// lib/models/driver_delivery_model.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../utils/helpers.dart';

enum DeliveryStatus {
  readyForPickup,
  accepted,
  pickedUp,
  outForDelivery,
  delivered,
  cancelled;

  static DeliveryStatus fromString(String? val) {
    final s = val?.toLowerCase().trim() ?? '';
    if (s.contains('ready')) return DeliveryStatus.readyForPickup;
    if (s.contains('assigned') || s.contains('accept')) return DeliveryStatus.accepted;
    if (s.contains('pickup') || s.contains('picked')) return DeliveryStatus.pickedUp;
    if (s.contains('out')) return DeliveryStatus.outForDelivery;
    if (s.contains('deliver')) return DeliveryStatus.delivered;
    if (s.contains('cancel')) return DeliveryStatus.cancelled;
    return DeliveryStatus.readyForPickup;
  }

  String toDbValue() {
    switch (this) {
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
  final String chefId;
  final String chefName;
  final String pickupAddress;
  final String customerAddress;
  final String customerId;
  final String chatRoomId;
  final double payout;
  final double distanceKm;
  final int totalItemsCount;
  final DeliveryStatus status;
  final DateTime createdAt;
  final String timeSlot;
  final String? selectedDate;

  const DriverDeliveryModel({
    required this.orderId,
    required this.chefId,
    required this.chefName,
    required this.pickupAddress,
    required this.customerAddress,
    this.customerId = '',
    this.chatRoomId = '',
    required this.payout,
    this.distanceKm = 0.0,
    this.totalItemsCount = 1,
    required this.status,
    required this.createdAt,
    this.timeSlot = '',
    this.selectedDate,
  });

  Map<String, dynamic> get slotSource => {
        'created_at': createdAt.toIso8601String(),
        'time_slot': timeSlot,
        if (selectedDate != null && selectedDate!.isNotEmpty) 'selected_date': selectedDate,
      };

  factory DriverDeliveryModel.fromJson(Map<String, dynamic> json) {
    final chef = _embeddedMap(json['chefs'] ?? json['chef']);
    final items = _itemsFrom(json['items'] ?? json['cart_items'] ?? json['order_items']);
    final first = items.isNotEmpty ? items.first : const <String, dynamic>{};
    return DriverDeliveryModel(
      orderId: json['id']?.toString() ?? '',
      chefId: json['chef_id']?.toString() ?? '',
      chefName: json['chef_name']?.toString() ?? chef?['business_name']?.toString() ?? 'Chef Kitchen',
      pickupAddress: json['pickup_address']?.toString() ?? chef?['pickup_address']?.toString() ?? '',
      customerAddress: json['delivery_address']?.toString() ?? '',
      customerId: json['customer_id']?.toString() ?? json['user_id']?.toString() ?? '',
      chatRoomId: orderChatRoomId(json, items: items),
      payout: (json['driver_payout'] as num?)?.toDouble() ?? 
              (json['delivery_fee'] as num?)?.toDouble() ?? 40.0,
      distanceKm: (json['estimated_distance_km'] as num?)?.toDouble() ?? 0.0,
      totalItemsCount: (json['order_items'] as List?)?.length ?? items.length,
      status: DeliveryStatus.fromString(json['status']?.toString()),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      timeSlot: json['time_slot']?.toString() ??
          first['time_slot']?.toString() ??
          first['timeSlot']?.toString() ??
          json['delivery_slot']?.toString() ??
          '',
      selectedDate: json['selected_date']?.toString() ?? first['selected_date']?.toString(),
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