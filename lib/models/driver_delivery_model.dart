// lib/models/driver_delivery_model.dart

import 'package:flutter/foundation.dart';

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
  final double payout;
  final double distanceKm;
  final int totalItemsCount;
  final DeliveryStatus status;
  final DateTime createdAt;

  const DriverDeliveryModel({
    required this.orderId,
    required this.chefId,
    required this.chefName,
    required this.pickupAddress,
    required this.customerAddress,
    required this.payout,
    this.distanceKm = 0.0,
    this.totalItemsCount = 1,
    required this.status,
    required this.createdAt,
  });

  factory DriverDeliveryModel.fromJson(Map<String, dynamic> json) {
    return DriverDeliveryModel(
      orderId: json['id']?.toString() ?? '',
      chefId: json['chef_id']?.toString() ?? '',
      chefName: json['chef_name']?.toString() ?? json['chefs']?['business_name']?.toString() ?? 'Chef Kitchen',
      pickupAddress: json['pickup_address']?.toString() ?? json['chefs']?['pickup_address']?.toString() ?? '',
      customerAddress: json['delivery_address']?.toString() ?? '',
      payout: (json['driver_payout'] as num?)?.toDouble() ?? 
              (json['delivery_fee'] as num?)?.toDouble() ?? 40.0,
      distanceKm: (json['estimated_distance_km'] as num?)?.toDouble() ?? 0.0,
      totalItemsCount: (json['order_items'] as List?)?.length ?? 1,
      status: DeliveryStatus.fromString(json['status']?.toString()),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
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