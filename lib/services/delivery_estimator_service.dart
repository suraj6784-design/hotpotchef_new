// lib/services/delivery_estimator_service.dart

import 'package:geolocator/geolocator.dart';

import '../utils/kitchen_promise.dart';

class DeliveryEstimatorService {
  /// Maximum serviceable radius in kilometers for home kitchen deliveries
  static const double maxDeliveryRadiusKm = 15.0;

  /// Standard urban tortuosity factor to convert straight-line GPS distance to estimated road distance
  static const double _roadDistanceMultiplier = 1.3;

  /// Calculates estimated road distance in kilometers between two geo-coordinates
  static double calculateDistanceKm({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) {
    if (startLat == 0.0 || startLng == 0.0 || endLat == 0.0 || endLng == 0.0) {
      return 0.0;
    }

    double straightLineMeters = Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
    double straightLineKm = straightLineMeters / 1000.0;

    // Apply tortuosity multiplier for realistic road routing
    return straightLineKm * _roadDistanceMultiplier;
  }

  /// Validates whether the destination is within the kitchen's delivery range
  static bool isWithinDeliveryRadius(double distanceKm) {
    return distanceKm <= maxDeliveryRadiusKm;
  }

  /// Calculates dynamic delivery fee based on estimated road distance
  static double calculateDynamicFee(double distanceKm) {
    if (distanceKm <= 0) return 0.0;

    double baseFee = 30.0; // Base fee for first 3 kilometers
    if (distanceKm > 3.0) {
      double extraKm = distanceKm - 3.0;
      baseFee += extraKm.ceil() * 10.0; // ₹10 per additional kilometer
    }
    return baseFee;
  }

  /// Estimates delivery ETA in minutes: kitchen prep window + city travel at 20 km/h.
  static int estimateEtaMinutes(double distanceKm, {int prepMinutes = 30}) {
    return promisedEtaMinutes(distanceKm: distanceKm, prepMinutes: prepMinutes);
  }
}