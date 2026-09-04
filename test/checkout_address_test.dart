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

  group('shouldMarkSavedAddressDefault', () {
    test('marks the first address and fills in when none is default', () {
      expect(shouldMarkSavedAddressDefault(const []), isTrue);
      expect(
        shouldMarkSavedAddressDefault([
          {'id': 'a', 'is_default': true},
        ]),
        isFalse,
      );
      expect(
        shouldMarkSavedAddressDefault([
          {'id': 'a', 'is_default': false},
        ]),
        isTrue,
      );
      expect(
        shouldMarkSavedAddressDefault([
          {'id': 'a', 'is_default': true},
        ], editingId: 'a'),
        isTrue,
      );
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

  group('orderDropoffAddress', () {
    test('prefers the order delivery_address column', () {
      expect(
        orderDropoffAddress({
          'delivery_address': '2, Chinchwad, 411033',
        }),
        '2, Chinchwad, 411033',
      );
    });

    test('skips placeholder text and uses a saved-address fallback', () {
      expect(
        orderDropoffAddress(
          {'delivery_address': 'Unknown Location'},
          fallbackAddress: {
            'house_no': '2',
            'street': '396/400, Chinchwad',
            'city': 'Pimpri-Chinchwad',
            'postal_code': '411033',
          },
        ),
        '2, 396/400, Chinchwad, Pimpri-Chinchwad - 411033',
      );
    });

    test('reads structured fields when delivery_address is missing', () {
      expect(
        orderDropoffAddress({
          'house_no': '12A',
          'street': 'FC Road',
          'city': 'Pune',
          'pincode': '411004',
        }),
        '12A, FC Road, Pune - 411004',
      );
    });
  });

  group('resolvedOrderId', () {
    test('prefers order_id on enriched line items', () {
      expect(
        resolvedOrderId({'id': 'meal-row', 'order_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'}),
        'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );
    });

    test('uses id on a raw orders row', () {
      expect(resolvedOrderId({'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'}), 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    });
  });

  group('mealIdFromOrderItem', () {
    test('prefers source_meal_id from checkout payload', () {
      expect(mealIdFromOrderItem({'id': 'line', 'source_meal_id': 'meal-1'}), 'meal-1');
    });

    test('orderChatRoomId uses the order id so everyone shares one group', () {
      expect(
        orderChatRoomId(
          {'id': 'order-row'},
          items: [
            {'source_meal_id': 'meal-77', 'id': 'line-1'},
          ],
        ),
        'order-row',
      );
    });

    test('orderChatMemberIds collects customer, chef, and driver', () {
      expect(
        orderChatMemberIds({
          'customer_id': 'cust-1',
          'chef_id': 'chef-1',
          'driver_id': 'drv-1',
        }),
        {'cust-1', 'chef-1', 'drv-1'},
      );
    });

    test('shouldNotifyChatMember only alerts people in the order group', () {
      expect(
        shouldNotifyChatMember(myId: 'chef-1', senderId: 'cust-1', memberIds: {'cust-1', 'chef-1'}),
        isTrue,
      );
      expect(
        shouldNotifyChatMember(myId: 'stranger', senderId: 'cust-1', memberIds: {'cust-1', 'chef-1'}),
        isFalse,
      );
      expect(
        shouldNotifyChatMember(myId: 'cust-1', senderId: 'cust-1', memberIds: {'cust-1', 'chef-1'}),
        isFalse,
      );
    });

    test('otherChatParticipantId skips my own messages', () {
      expect(
        otherChatParticipantId([
          {'sender_id': 'me'},
          {'sender_id': 'chef-2'},
        ], 'me'),
        'chef-2',
      );
      expect(otherChatParticipantId([{'sender_id': 'me'}], 'me'), isNull);
    });

    test('resolveChatCallTarget prefers the known other user', () {
      expect(
        resolveChatCallTarget(
          knownOtherUserId: 'chef-9',
          messages: [
            {'sender_id': 'me'},
          ],
          myId: 'me',
        ),
        'chef-9',
      );
      expect(
        resolveChatCallTarget(
          knownOtherUserId: 'me',
          messages: [
            {'sender_id': 'chef-2'},
          ],
          myId: 'me',
        ),
        'chef-2',
      );
    });

    test('chatPath carries the other user for an empty room', () {
      final uri = Uri.parse(chatPath('req-1', roomName: 'Catering lead', otherUserId: 'cust-3'));
      expect(uri.path, '/chat/req-1');
      expect(uri.queryParameters['roomName'], 'Catering lead');
      expect(uri.queryParameters['otherUserId'], 'cust-3');
    });

    test('chatPath marks an order group and lists members', () {
      final uri = Uri.parse(chatPath(
        'order-row',
        roomName: 'Order ABC12345',
        otherUserId: 'chef-1',
        memberIds: ['cust-1', 'chef-1', 'drv-1'],
        isGroup: true,
      ));
      expect(uri.queryParameters['group'], '1');
      expect(parseChatMemberIds(uri.queryParameters['memberIds']), containsAll(['cust-1', 'chef-1', 'drv-1']));
    });
  });

  group('checkoutItemsFromCateringRequest', () {
    test('splits the budget across portions and keeps the claiming chef', () {
      final items = checkoutItemsFromCateringRequest({
        'id': 'req-1',
        'title': 'Office lunch',
        'quantity': 10,
        'budget': 5000,
        'accepted_chef_id': 'chef-9',
        'accepted_chef_name': 'Asha Kitchen',
        'service_type': 'Delivery Partner',
        'target_date_time': '2026-09-10T07:30:00.000Z',
      });
      expect(items, hasLength(1));
      expect(items.single['chef_id'], 'chef-9');
      expect(items.single['quantity'], 10);
      expect(items.single['price'], 500);
      expect(items.single['source_request_id'], 'req-1');
    });
  });

  group('preferredCheckoutAddress', () {
    test('matches a feed pin hint to a saved address', () {
      final chosen = preferredCheckoutAddress(
        [
          {'id': 'a1', 'street': 'FC Road', 'city': 'Pune', 'is_default': true},
          {'id': 'a2', 'street': 'Kothrud', 'city': 'Pune', 'latitude': 18.5, 'longitude': 73.8},
        ],
        hint: {'street': 'Kothrud', 'city': 'Pune', 'latitude': 18.5, 'longitude': 73.8},
      );
      expect(chosen?['id'], 'a2');
    });
  });

  group('kitchenCoordinate', () {
    test('prefers pickup_lat over a chef fallback and skips zeros', () {
      expect(
        kitchenCoordinate({'pickup_lat': 18.52, 'chef_lat': 19.1}, latitude: true),
        18.52,
      );
      expect(
        kitchenCoordinate({'pickup_lat': 0, 'chef_lat': 19.1}, latitude: true),
        19.1,
      );
      expect(hasKitchenPin({'pickup_lat': 0, 'pickup_lng': 0}), isFalse);
    });

    test('isChefKitchenOpen treats a missing profile as open and respects is_open', () {
      expect(isChefKitchenOpen(null), isTrue);
      expect(isChefKitchenOpen({'name': 'Asha'}), isTrue);
      expect(isChefKitchenOpen({'is_open': true}), isTrue);
      expect(isChefKitchenOpen({'is_open': false}), isFalse);
      expect(isChefKitchenOpen({'is_open': 'offline'}), isFalse);
    });

    test('kitchenPinMealFields writes pickup_lat and pickup_lng', () {
      expect(kitchenPinMealFields(18.52, 73.85), {
        'pickup_lat': 18.52,
        'pickup_lng': 73.85,
      });
    });

    test('copies a chef pin onto a meal that has none', () {
      final pinned = mealWithKitchenPin(
        {'id': 'meal-1', 'title': 'Dal'},
        chefPin: {'lat': 18.52, 'lng': 73.85},
      );
      expect(hasKitchenPin(pinned), isTrue);
      expect(pinned['pickup_lat'], 18.52);
      expect(pinned['pickup_lng'], 73.85);
    });
  });

  test('mealShareText names the dish, kitchen, and price', () {
    expect(
      mealShareText({
        'title': 'Dal Tadka',
        'chef_name': 'Asha Kitchen',
        'price': 120,
      }),
      'Try Dal Tadka from Asha Kitchen on HotPotChef — ₹120',
    );
    expect(
      mealShareText({
        'id': 'meal-77',
        'title': 'Dal Tadka',
        'chef_name': 'Asha Kitchen',
        'price': 120,
      }),
      'Try Dal Tadka from Asha Kitchen on HotPotChef — ₹120\nhotpotchef://app/meal/meal-77',
    );
  });

  test('alertOpenPath opens the Order# room or the matching hub tab', () {
    expect(
      alertOpenPath({'meal_id': 'abc12345-order'}),
      contains('/chat/abc12345-order'),
    );
    expect(
      alertOpenPath({'order_id': 'ord-1'}, role: 'Customer'),
      '/customer-hub?tab=orders',
    );
    expect(
      alertOpenPath({'order_id': 'ord-1', 'status': 'Delivered'}, role: 'Customer'),
      '/order-history',
    );
    expect(
      alertOpenPath({'order_id': 'ord-1'}, role: 'Chef'),
      '/chef-hub?tab=orders',
    );
    expect(
      alertOpenPath({'order_id': 'ord-1', 'status': 'Cancelled'}, role: 'Chef'),
      '/chef-hub?tab=history',
    );
    expect(
      alertOpenPath({'request_id': 'lead-1'}, role: 'chef'),
      '/chef-hub?tab=leads',
    );
    expect(customerHubTabIndex('orders'), 2);
    expect(chefHubTabIndex('leads'), 4);
  });
}
