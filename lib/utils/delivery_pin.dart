import 'helpers.dart';

/// Straight-line distance that counts as the partner reaching the diner.
const double kDropoffArrivalRadiusMeters = 80;

/// True when [driverLat]/[driverLng] is at the dropoff pin.
bool driverHasReachedDropoff({
  required double? driverLat,
  required double? driverLng,
  required double? dropoffLat,
  required double? dropoffLng,
  double radiusMeters = kDropoffArrivalRadiusMeters,
}) {
  if (driverLat == null ||
      driverLng == null ||
      dropoffLat == null ||
      dropoffLng == null) {
    return false;
  }
  if (!driverLat.isFinite ||
      !driverLng.isFinite ||
      !dropoffLat.isFinite ||
      !dropoffLng.isFinite) {
    return false;
  }
  if (radiusMeters <= 0) return false;
  if (driverLat.abs() < 0.0001 && driverLng.abs() < 0.0001) return false;
  if (dropoffLat.abs() < 0.0001 && dropoffLng.abs() < 0.0001) return false;
  final meters =
      haversineKm(driverLat, driverLng, dropoffLat, dropoffLng) * 1000;
  return meters <= radiusMeters;
}

/// Copy shown when Mark Delivered must not ask for the PIN.
String markDeliveredTooFarMessage() {
  final meters = kDropoffArrivalRadiusMeters.round();
  return 'You need to be near the dropoff (within $meters meters) to mark this order delivered.';
}

/// Why Mark Delivered must not open the PIN dialog.
///
/// Null when the partner is inside [kDropoffArrivalRadiusMeters] of the
/// dropoff — the same gate that reveals the diner PIN. A missing fix counts
/// as too far: the emulator and a denied GPS permission are not at the door.
String? markDeliveredBlockReason({
  required double? driverLat,
  required double? driverLng,
  required double? dropoffLat,
  required double? dropoffLng,
}) {
  if (driverHasReachedDropoff(
    driverLat: driverLat,
    driverLng: driverLng,
    dropoffLat: dropoffLat,
    dropoffLng: dropoffLng,
  )) {
    return null;
  }
  return markDeliveredTooFarMessage();
}

bool _statusHidesDeliveryPin(String? status) {
  final s = (status ?? '').trim().toLowerCase();
  if (s.contains('cancel') || s.contains('reject')) {
    return true;
  }
  if (s.contains('out for delivery') || s.contains('out_for_delivery')) {
    return false;
  }
  return s.contains('delivered') || s.contains('completed');
}

/// PIN the diner may see. Empty until the partner has reached the dropoff.
String dinerVisibleDeliveryPin(Map<String, dynamic> order) {
  if (_statusHidesDeliveryPin(order['status']?.toString())) return '';
  final arrived = (order['driver_arrived_at'] ?? '').toString().trim();
  if (arrived.isEmpty) return '';
  final pin = (order['delivery_otp'] ?? '').toString().trim();
  if (pin.length < 4) return '';
  return pin;
}
