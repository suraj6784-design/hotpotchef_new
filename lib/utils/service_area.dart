import 'dart:math' as math;

/// Launch-city serviceability. City 2 adds another [ServiceCity] — do not clone schema.
class ServiceCity {
  const ServiceCity({
    required this.id,
    required this.label,
    required this.pinPrefixes,
    required this.centerLat,
    required this.centerLng,
    this.bboxSouth = 0,
    this.bboxNorth = 0,
    this.bboxWest = 0,
    this.bboxEast = 0,
  });

  final String id;
  final String label;
  final List<String> pinPrefixes;
  final double centerLat;
  final double centerLng;
  final double bboxSouth;
  final double bboxNorth;
  final double bboxWest;
  final double bboxEast;

  bool pinMatches(String digits) {
    for (final prefix in pinPrefixes) {
      if (digits.startsWith(prefix)) return true;
    }
    return false;
  }

  bool coordMatches(double lat, double lng) {
    if (bboxSouth == 0 && bboxNorth == 0) return false;
    return lat >= bboxSouth && lat <= bboxNorth && lng >= bboxWest && lng <= bboxEast;
  }
}

const kLaunchCities = <ServiceCity>[
  ServiceCity(
    id: 'pune',
    label: 'Pune',
    pinPrefixes: ['411', '412'],
    centerLat: 18.5204,
    centerLng: 73.8567,
    bboxSouth: 18.32,
    bboxNorth: 18.78,
    bboxWest: 73.62,
    bboxEast: 74.12,
  ),
];

String normalizeServicePincode(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length < 3) return '';
  return digits.length >= 6 ? digits.substring(0, 6) : digits;
}

ServiceCity? serviceCityForPin(String? raw) {
  final digits = normalizeServicePincode(raw);
  if (digits.isEmpty) return null;
  for (final city in kLaunchCities) {
    if (city.pinMatches(digits)) return city;
  }
  return null;
}

ServiceCity? serviceCityForCoord(double? lat, double? lng) {
  if (lat == null || lng == null || lat == 0 || lng == 0) return null;
  for (final city in kLaunchCities) {
    if (city.coordMatches(lat, lng)) return city;
  }
  return null;
}

/// True when pin or coordinates sit in a live city. Unknown pin+coord is not a block.
bool isInLaunchServiceArea({
  String? pincode,
  double? lat,
  double? lng,
}) {
  if (serviceCityForPin(pincode) != null) return true;
  if (serviceCityForCoord(lat, lng) != null) return true;
  final digits = normalizeServicePincode(pincode);
  if (digits.length >= 6) return false;
  if (lat != null && lng != null && lat != 0 && lng != 0) return false;
  return true;
}

String launchCitiesLabel() => kLaunchCities.map((c) => c.label).join(', ');

/// Null when checkout may proceed without a city warning.
String? serviceAreaCheckoutWarning({
  String? pincode,
  double? lat,
  double? lng,
}) {
  if (isInLaunchServiceArea(pincode: pincode, lat: lat, lng: lng)) return null;
  return 'HotPotChef is live in ${launchCitiesLabel()} first. This drop looks outside our delivery cities.';
}

List<T> pageCatalog<T>(List<T> items, {required int page, int pageSize = 80}) {
  if (pageSize <= 0 || page < 0 || items.isEmpty) return <T>[];
  final start = page * pageSize;
  if (start >= items.length) return <T>[];
  final end = (start + pageSize).clamp(0, items.length);
  return items.sublist(start, end);
}

/// Guest / first-open pin when GPS is unavailable. No permission prompt.
Map<String, dynamic> launchCityDefaultPin() {
  final city = kLaunchCities.first;
  return {
    'id': 'launch-city-${city.id}',
    'title': 'Current location',
    'landmark': city.label,
    'address': city.label,
    'city': city.label,
    'pincode': '411001',
    'postal_code': '411001',
    'latitude': city.centerLat,
    'longitude': city.centerLng,
    'lat': city.centerLat,
    'lng': city.centerLng,
    'is_launch_city': true,
  };
}

/// Home radius: same launch city is always in range (Thergaon vs FC Pune
/// exceeds 15 km × 1.3 road). Missing kitchen coords still list while hydrating.
bool kitchenServesDinerPin({
  double? kitchenLat,
  double? kitchenLng,
  double? dinerLat,
  double? dinerLng,
  String? dinerPincode,
  String? kitchenPincode,
}) {
  final dinerCity = serviceCityForPin(dinerPincode) ?? serviceCityForCoord(dinerLat, dinerLng);
  final kitchenCity =
      serviceCityForPin(kitchenPincode) ?? serviceCityForCoord(kitchenLat, kitchenLng);
  if (dinerCity != null && kitchenCity != null && dinerCity.id == kitchenCity.id) {
    return true;
  }
  if (kitchenLat == null || kitchenLng == null || dinerLat == null || dinerLng == null) {
    return dinerCity != null;
  }
  const maxKm = 15.0;
  const earthKm = 6371.0;
  final dLat = (dinerLat - kitchenLat) * math.pi / 180;
  final dLng = (dinerLng - kitchenLng) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(kitchenLat * math.pi / 180) *
          math.cos(dinerLat * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final km = earthKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return km > 0 && km <= maxKm;
}
