import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('formatSavedAddress', () {
    test('joins house, street, city and pin without empty commas', () {
      expect(
        formatSavedAddress({
          'house_no': '12A',
          'street': 'FC Road',
          'city': 'Pune',
          'state': 'Maharashtra',
          'postal_code': '411004',
        }),
        '12A, FC Road, Pune, Maharashtra - 411004',
      );
    });

    test('falls back to a single address field', () {
      expect(
        formatSavedAddress({'address': 'Kothrud, Pune'}),
        'Kothrud, Pune',
      );
    });

    test('returns empty for a missing address', () {
      expect(formatSavedAddress(null), '');
      expect(formatSavedAddress({}), '');
    });

    test('does not repeat city, state, or pin already in the street', () {
      expect(
        formatSavedAddress({
          'house_no': '2',
          'street': '396/400, Chinchwad, Maharashtra, 411033, Pimpri-Chinchwad',
          'city': 'Pimpri-Chinchwad',
          'state': 'Maharashtra',
          'postal_code': '411033',
        }),
        '2, 396/400, Chinchwad, Maharashtra, 411033, Pimpri-Chinchwad',
      );
    });
  });

  group('uniqueSavedAddresses', () {
    test('keeps one row when the same address was saved three times', () {
      final unique = uniqueSavedAddresses([
        {
          'id': 'a',
          'house_no': '2',
          'street': '396/400, Chinchwad, Maharashtra, 411033, Pimpri-Chinchwad',
          'city': 'Pimpri-Chinchwad',
          'state': 'Maharashtra',
          'postal_code': '411033',
          'updated_at': '2026-01-01T00:00:00Z',
        },
        {
          'id': 'b',
          'house_no': '2',
          'street': '396/400, Chinchwad, Maharashtra, 411033, Pimpri-Chinchwad',
          'city': 'Pimpri-Chinchwad',
          'state': 'Maharashtra',
          'postal_code': '411033',
          'updated_at': '2026-09-04T00:00:00Z',
        },
        {
          'id': 'c',
          'house_no': '2',
          'street': '396/400, Chinchwad, Maharashtra, 411033, Pimpri-Chinchwad',
          'city': 'Pimpri-Chinchwad',
          'state': 'Maharashtra',
          'postal_code': '411033',
          'updated_at': '2026-03-01T00:00:00Z',
        },
      ]);
      expect(unique, hasLength(1));
      expect(unique.single['id'], 'b');
    });
  });

  group('preferredCheckoutAddress', () {
    test('keeps the currently selected address', () {
      final selected = preferredCheckoutAddress(
        [
          {'id': 'a', 'street': 'Old'},
          {'id': 'b', 'street': 'New'},
        ],
        selectedId: 'b',
      );
      expect(selected?['id'], 'b');
    });

    test('prefers the default address when nothing is selected', () {
      final selected = preferredCheckoutAddress([
        {'id': 'a', 'is_default': false, 'updated_at': '2026-01-01T00:00:00Z'},
        {'id': 'b', 'is_default': true, 'updated_at': '2025-01-01T00:00:00Z'},
      ]);
      expect(selected?['id'], 'b');
    });

    test('uses the most recently updated address otherwise', () {
      final selected = preferredCheckoutAddress([
        {'id': 'old', 'updated_at': '2026-01-01T00:00:00Z'},
        {'id': 'new', 'updated_at': '2026-09-02T00:00:00Z'},
      ]);
      expect(selected?['id'], 'new');
    });
  });

  group('checkoutAddressFromUserProfile', () {
    test('builds a fallback address from the users row', () {
      final address = checkoutAddressFromUserProfile({
        'address': 'Baner, Pune',
        'lat': 18.5,
        'lng': 73.8,
      });
      expect(formatSavedAddress(address), 'Baner, Pune');
      expect(addressCoordinate(address, latitude: true), 18.5);
      expect(addressCoordinate(address, latitude: false), 73.8);
    });
  });
}
