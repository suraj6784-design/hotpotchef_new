import 'dart:math' as math;

import '../models/cart_enums.dart';

const double kCheckoutDeliveryBaseFee = 30;
const double kCheckoutDeliveryIncludedKm = 3;
const double kCheckoutDeliveryPerExtraKm = 10;
const int kHomeMealStreamLimit = 150;
const double kMaxCheckoutTip = 500;

double clampCheckoutTip(num? raw) {
  final n = raw == null ? 0.0 : raw.toDouble();
  if (!n.isFinite) return 0;
  return n.clamp(0, kMaxCheckoutTip).toDouble();
}

/// Matches live checkout: geodesic km, ₹30 for the first 3 km, ₹10 per extra km.
double deliveryFeeForDistanceKm(double distanceKm) {
  if (!distanceKm.isFinite || distanceKm < 0) return kCheckoutDeliveryBaseFee;
  var fee = kCheckoutDeliveryBaseFee;
  if (distanceKm > kCheckoutDeliveryIncludedKm) {
    fee += (distanceKm - kCheckoutDeliveryIncludedKm).ceil() * kCheckoutDeliveryPerExtraKm;
  }
  return fee;
}

double haversineKm({
  required double startLat,
  required double startLng,
  required double endLat,
  required double endLng,
}) {
  if ([startLat, startLng, endLat, endLng].any((v) => v == 0 || !v.isFinite)) {
    return 0;
  }
  const earthKm = 6371.0;
  final dLat = _toRad(endLat - startLat);
  final dLng = _toRad(endLng - startLng);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(startLat)) * math.cos(_toRad(endLat)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthKm * c;
}

double _toRad(double deg) => deg * math.pi / 180;

bool cartHasDelivery(Iterable<Map<String, dynamic>> items) {
  return items.any((item) {
    final raw = (item['selected_service_type'] ??
            item['selectedServiceType'] ??
            item['service_type'] ??
            item['serviceType'] ??
            '')
        .toString();
    return ServiceType.fromString(raw).isDelivery;
  });
}

/// Server and client share this quote. Missing drop-off → ₹30 flat (same as checkout UI).
/// Missing chef pin → ₹30 for that kitchen.
double quoteCheckoutDeliveryFee({
  required Iterable<Map<String, dynamic>> cartItems,
  double? dropLat,
  double? dropLng,
  Map<String, ({double? lat, double? lng})> chefLocations = const {},
}) {
  final items = cartItems.toList();
  if (items.isEmpty || !cartHasDelivery(items)) return 0;

  if (dropLat == null || dropLng == null || dropLat == 0 || dropLng == 0) {
    return kCheckoutDeliveryBaseFee;
  }

  final chefIds = <String>{};
  for (final item in items) {
    final id = (item['chef_id'] ?? item['chefId'] ?? '').toString().trim();
    if (id.isNotEmpty) chefIds.add(id);
  }
  if (chefIds.isEmpty) return kCheckoutDeliveryBaseFee;

  var total = 0.0;
  for (final chefId in chefIds) {
    final pin = chefLocations[chefId];
    final lat = pin?.lat;
    final lng = pin?.lng;
    if (lat == null || lng == null) {
      total += kCheckoutDeliveryBaseFee;
      continue;
    }
    final km = haversineKm(
      startLat: lat,
      startLng: lng,
      endLat: dropLat,
      endLng: dropLng,
    );
    total += km <= 0 ? kCheckoutDeliveryBaseFee : deliveryFeeForDistanceKm(km);
  }
  return total;
}
