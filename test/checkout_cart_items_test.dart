import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/cart_enums.dart';
import 'package:hotpotchef_new/models/cart_state.dart';
import 'package:hotpotchef_new/utils/checkout_cart_items.dart';

void main() {
  CartItemModel item({
    ServiceType service = ServiceType.deliveryPlatform,
    double basePrice = 120,
    double? discountedPrice,
    Map<String, dynamic> mealDetails = const {'price': 120, 'exact_time': '7:00 PM'},
  }) {
    return CartItemModel(
      id: 'meal-1_1',
      mealId: 'meal-1',
      chefId: 'chef-1',
      title: 'Dal',
      basePrice: basePrice,
      discountedPrice: discountedPrice,
      quantity: 2,
      scheduledDate: DateTime(2026, 9, 12),
      serviceType: service,
      timeSlot: '7:00 PM',
      rawMealDetails: mealDetails,
    );
  }

  group('cart JSON → checkout contract', () {
    test('CartItemModel.toJson uses selectedServiceType, not selected_service_type', () {
      final json = item().toJson();
      expect(json['selectedServiceType'], 'deliveryPlatform');
      expect(json.containsKey('selected_service_type'), isFalse);
      expect(json.containsKey('serviceType'), isFalse);
      expect(json['basePrice'], 120);
      expect(json.containsKey('base_price'), isFalse);
      expect(json['mealDetails'], isA<Map>());
      expect(json.containsKey('rawMealDetails'), isFalse);
    });

    test('legacy checkout keys miss delivery on real cart JSON (the production bug)', () {
      final json = item(service: ServiceType.deliveryPlatform).toJson();
      final legacyHasDelivery = (json['selected_service_type'] ?? json['serviceType'] ?? '')
          .toString()
          .toLowerCase()
          .contains('delivery');
      expect(legacyHasDelivery, isFalse);
      expect(cartItemHasDelivery(json), isTrue);
    });

    test('detects delivery and pickup from wire values and legacy aliases', () {
      expect(cartItemsHaveDelivery([item().toJson()]), isTrue);
      expect(
        cartItemsHaveDelivery([item(service: ServiceType.deliverySelf).toJson()]),
        isTrue,
      );
      expect(
        cartItemsHaveDelivery([item(service: ServiceType.pickup).toJson()]),
        isFalse,
      );
      expect(
        cartItemsHaveDelivery([item(service: ServiceType.dineIn).toJson()]),
        isFalse,
      );
      expect(
        cartItemHasDelivery({'selected_service_type': 'delivery'}),
        isTrue,
      );
      expect(cartItemHasDelivery({'serviceType': 'Pickup'}), isFalse);
    });

    test('unit price reads camelCase cart keys used by toJson', () {
      final json = item(basePrice: 200, discountedPrice: 150).toJson();
      expect(json['discountedPrice'], 150);
      expect(json['discounted_price'], isNull);
      expect(cartItemUnitPrice(json), 150);

      final baseOnly = item(basePrice: 99, discountedPrice: null).toJson();
      expect(cartItemUnitPrice(baseOnly), 99);

      expect(cartItemUnitPrice({'discounted_price': 40, 'quantity': 1}), 40);
    });

    test('meal details fallback finds exact_time on mealDetails, not rawMealDetails', () {
      final json = item().toJson();
      expect(json['rawMealDetails'], isNull);
      expect(cartItemMealDetails(json)?['exact_time'], '7:00 PM');
    });
  });

  group('resolveCustomerEmail', () {
    test('prefers auth email, then metadata, then profile', () {
      expect(
        resolveCustomerEmail(
          authEmail: 'a@x.com',
          metadataEmail: 'b@x.com',
          profileEmail: 'c@x.com',
        ),
        'a@x.com',
      );
      expect(
        resolveCustomerEmail(authEmail: null, metadataEmail: 'b@x.com'),
        'b@x.com',
      );
      expect(
        resolveCustomerEmail(authEmail: '', profileEmail: 'c@x.com'),
        'c@x.com',
      );
      expect(resolveCustomerEmail(authEmail: null), isNull);
    });
  });

  group('mealDisplayTitle', () {
    test('prefers catalog title over name, then generic fallback', () {
      expect(mealDisplayTitle({'title': 'Puran Poli', 'name': 'legacy'}), 'Puran Poli');
      expect(mealDisplayTitle({'name': 'Legacy Thali'}), 'Legacy Thali');
      expect(mealDisplayTitle({'title': '  ', 'name': null}), 'Meal Item');
      expect(mealDisplayTitle({}), 'Meal Item');
    });
  });
}
