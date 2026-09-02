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
