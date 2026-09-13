// lib/models/driver_delivery_model.dart

import 'package:flutter/foundation.dart';

import '../utils/order_status.dart';

enum DeliveryStatus {
  readyForPickup,
  accepted,
  pickedUp,
  outForDelivery,
  delivered,
  cancelled;

  static DeliveryStatus fromString(String? val) {
    switch (OrderStatus.parse(val)) {
      case OrderStatus.readyForPickup:
        return DeliveryStatus.readyForPickup;
      case OrderStatus.accepted:
      case OrderStatus.driverAssigned:
        return DeliveryStatus.accepted;
      case OrderStatus.pickedUp:
        return DeliveryStatus.pickedUp;
      case OrderStatus.outForDelivery:
        return DeliveryStatus.outForDelivery;
      case OrderStatus.delivered:
      case OrderStatus.completed:
        return DeliveryStatus.delivered;
      case OrderStatus.cancelled:
        return DeliveryStatus.cancelled;
      default:
        return DeliveryStatus.readyForPickup;
    }
  }

  String toDbValue() {
    switch (this) {
      case DeliveryStatus.readyForPickup:
        return 'ready_for_pickup';
      case DeliveryStatus.accepted:
        return 'accepted';
      case DeliveryStatus.pickedUp:
        return 'picked_up';
      case DeliveryStatus.outForDelivery:
        return 'out_for_delivery';
      case DeliveryStatus.delivered:
        return 'delivered';
      case DeliveryStatus.cancelled:
        return 'cancelled';
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