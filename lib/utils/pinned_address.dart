import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

import 'network.dart';

final _plusCode = RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,3}$', caseSensitive: false);
final _pinCode = RegExp(r'\b(\d{6})\b');

const _indianStates = <String>{
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chhattisgarh',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
  'Andaman and Nicobar Islands',
  'Chandigarh',
  'Dadra and Nagar Haveli and Daman and Diu',
  'Delhi',
  'Jammu and Kashmir',
  'Ladakh',
  'Lakshadweep',
  'Puducherry',
  'National Capital Territory of Delhi',
};

class PinnedAddressParts {
  const PinnedAddressParts({
    this.street = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.country = '',
    this.formatted = '',
  });

  final String street;
  final String city;
  final String state;
  final String pincode;
  final String country;
  final String formatted;

  bool get hasRegion => city.isNotEmpty || state.isNotEmpty || pincode.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'street': street,
        'city': city,
        'state': state,
        'pincode': pincode,
        'country': country,
        'address': formatted.isNotEmpty ? formatted : street,
      };

  factory PinnedAddressParts.fromMap(Map<dynamic, dynamic> map) {
    return PinnedAddressParts(
      street: _clean(map['street']?.toString()),
      city: _clean(map['city']?.toString()),
      state: _clean(map['state']?.toString()),
      pincode: _clean(map['pincode']?.toString() ?? map['postal_code']?.toString()),
      country: _clean(map['country']?.toString()),
      formatted: _clean(map['address']?.toString() ?? map['formatted']?.toString()),
    );
  }

  PinnedAddressParts merge(PinnedAddressParts other) {
    return PinnedAddressParts(
      street: street.isNotEmpty ? street : other.street,
      city: city.isNotEmpty ? city : other.city,
      state: state.isNotEmpty ? state : other.state,
      pincode: pincode.isNotEmpty ? pincode : other.pincode,
      country: country.isNotEmpty ? country : other.country,
      formatted: formatted.isNotEmpty ? formatted : other.formatted,
    );
  }
}

String _clean(String? value) => value?.trim() ?? '';

bool _isPlusCode(String value) => _plusCode.hasMatch(value.replaceAll(' ', ''));

PinnedAddressParts parseGoogleAddressComponents(
  Iterable<dynamic> components, {
  String formatted = '',
}) {
  var streetName = '';
  var sublocality = '';
  var locality = '';
  var adminArea2 = '';
  var state = '';
  var pincode = '';
  var country = '';

  for (final raw in components) {
    if (raw is! Map) continue;
    final types = (raw['types'] as List<dynamic>?)?.map((e) => e.toString()).toSet() ?? {};
    final longName = _clean(raw['long_name']?.toString());
    if (longName.isEmpty) continue;

    if (types.contains('route')) {
      streetName = longName;
    } else if (types.contains('sublocality_level_1') || types.contains('sublocality')) {
      sublocality = longName;
    } else if (types.contains('locality')) {
      locality = longName;
    } else if (types.contains('administrative_area_level_2')) {
      adminArea2 = longName;
    } else if (types.contains('administrative_area_level_1')) {
      state = longName;
    } else if (types.contains('postal_code')) {
      pincode = longName;
    } else if (types.contains('country')) {
      country = longName;
    }
  }

  final city = locality.isNotEmpty ? locality : adminArea2;
  final street = [streetName, sublocality].where((part) => part.isNotEmpty && !_isPlusCode(part)).join(', ');
  final parsed = parseFormattedAddress(formatted);

  return PinnedAddressParts(
    street: street,
    city: city,
    state: state,
    pincode: pincode,
    country: country,
    formatted: formatted,
  ).merge(parsed);
}

PinnedAddressParts parseFormattedAddress(String formatted) {
  final text = formatted.trim();
  if (text.isEmpty) return const PinnedAddressParts();

  final pin = _pinCode.firstMatch(text)?.group(1) ?? '';
  var state = '';
  for (final name in _indianStates) {
    if (RegExp('\\b${RegExp.escape(name)}\\b', caseSensitive: false).hasMatch(text)) {
      state = name;
      break;
    }
  }

  final tokens = text
      .split(',')
      .map((part) => part.replaceAll(_pinCode, '').trim())
      .where((part) => part.isNotEmpty)
      .where((part) => !_isPlusCode(part))
      .where((part) => part.toLowerCase() != 'india')
      .where((part) => state.isEmpty || part.toLowerCase() != state.toLowerCase())
      .toList();

  var city = '';
  if (tokens.isNotEmpty) {
    city = tokens.last;
  }

  return PinnedAddressParts(
    city: city,
    state: state,
    pincode: pin,
    formatted: text,
  );
}

PinnedAddressParts partsFromPlacemark(Placemark place) {
  final city = _firstNonEmpty([
    place.locality,
    place.subAdministrativeArea,
    place.subLocality,
  ]);
  final street = [
    _clean(place.street),
    _clean(place.subLocality),
  ].where((part) => part.isNotEmpty && !_isPlusCode(part) && part != city).join(', ');

  return PinnedAddressParts(
    street: street,
    city: city,
    state: _clean(place.administrativeArea),
    pincode: _clean(place.postalCode),
    country: _clean(place.country),
    formatted: [
      street,
      city,
      _clean(place.administrativeArea),
      _clean(place.postalCode),
    ].where((part) => part.isNotEmpty).join(', '),
  );
}

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final cleaned = _clean(value);
    if (cleaned.isNotEmpty && !_isPlusCode(cleaned)) return cleaned;
  }
  return '';
}

Future<PinnedAddressParts> reverseGeocodeLatLng(double latitude, double longitude) async {
  final fromGoogle = await _reverseGeocodeGoogle(latitude, longitude);
  if (fromGoogle != null && fromGoogle.hasRegion) return fromGoogle;

  try {
    final placemarks = await placemarkFromCoordinates(latitude, longitude);
    if (placemarks.isNotEmpty) {
      final fromDevice = partsFromPlacemark(placemarks.first);
      if (fromDevice.hasRegion) {
        return fromGoogle == null ? fromDevice : fromGoogle.merge(fromDevice);
      }
      if (fromGoogle != null) return fromGoogle.merge(fromDevice);
      return fromDevice;
    }
  } catch (_) {}

  return fromGoogle ?? const PinnedAddressParts();
}

Future<PinnedAddressParts?> _reverseGeocodeGoogle(double latitude, double longitude) async {
  String apiKey = '';
  try {
    apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']?.trim() ?? '';
  } catch (_) {}
  if (apiKey.isEmpty) return null;

  final url = Uri.parse(
    'https://maps.googleapis.com/maps/api/geocode/json'
    '?latlng=$latitude,$longitude'
    '&key=$apiKey',
  );

  try {
    final res = await http.get(url).withTimeout(NetworkTimeouts.short);
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    if (data is! Map || data['status'] != 'OK') return null;
    final results = data['results'];
    if (results is! List || results.isEmpty) return null;

    PinnedAddressParts merged = const PinnedAddressParts();
    for (final result in results.take(3)) {
      if (result is! Map) continue;
      final formatted = _clean(result['formatted_address']?.toString());
      final components = result['address_components'] as List<dynamic>? ?? const [];
      merged = parseGoogleAddressComponents(components, formatted: formatted).merge(merged);
      if (merged.hasRegion && merged.pincode.isNotEmpty) break;
    }
    return merged;
  } catch (_) {
    return null;
  }
}
