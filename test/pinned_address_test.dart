import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/pinned_address.dart';

void main() {
  test('parseGoogleAddressComponents fills city, state and PIN', () {
    final parts = parseGoogleAddressComponents([
      {
        'long_name': 'Thergaon',
        'types': ['sublocality_level_1', 'sublocality'],
      },
      {
        'long_name': 'Pimpri-Chinchwad',
        'types': ['locality', 'political'],
      },
      {
        'long_name': 'Maharashtra',
        'types': ['administrative_area_level_1', 'political'],
      },
      {
        'long_name': '411033',
        'types': ['postal_code'],
      },
      {
        'long_name': 'India',
        'types': ['country', 'political'],
      },
    ], formatted: 'Thergaon, Pimpri-Chinchwad, Maharashtra 411033, India');

    expect(parts.city, 'Pimpri-Chinchwad');
    expect(parts.state, 'Maharashtra');
    expect(parts.pincode, '411033');
    expect(parts.street, 'Thergaon');
  });

  test('parseFormattedAddress reads Plus Code Google lines', () {
    final parts = parseFormattedAddress(
      'JQGH+P9V, Chinchwad, Pimpri-Chinchwad, Maharashtra 411033, India',
    );
    expect(parts.city, 'Pimpri-Chinchwad');
    expect(parts.state, 'Maharashtra');
    expect(parts.pincode, '411033');
  });

  test('empty Google strings stay empty instead of blocking a fallback', () {
    expect(PinnedAddressParts.fromMap({'city': '', 'state': 'Maharashtra'}).city, '');
    expect(
      const PinnedAddressParts(state: 'Maharashtra').merge(
        const PinnedAddressParts(city: 'Pune', pincode: '411004'),
      ).city,
      'Pune',
    );
  });
}
