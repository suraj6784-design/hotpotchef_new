import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  test('vegetarian and allergy notes hide the matching dishes', () {
    final chicken = {'title': 'Butter Chicken', 'is_veg': false};
    final paneer = {'title': 'Paneer Tikka', 'is_veg': true, 'description': 'cottage cheese'};
    final onionSalad = {'title': 'Kachumber', 'is_veg': true, 'description': 'onion tomato'};

    expect(mealMatchesCustomerDiet(chicken, preference: 'Vegetarian'), isFalse);
    expect(mealMatchesCustomerDiet(paneer, preference: 'Vegetarian'), isTrue);
    expect(mealMatchesCustomerDiet(paneer, preference: 'Vegan'), isFalse);
    expect(mealMatchesCustomerDiet(onionSalad, preference: 'Jain'), isFalse);
    expect(mealMatchesCustomerDiet(onionSalad, allergies: 'No onion'), isFalse);
    expect(mealMatchesCustomerDiet(paneer, allergies: 'No onion'), isTrue);
  });

  test('unread is only for newer messages from someone else', () {
    final lastAt = DateTime.parse('2026-09-05T10:00:00Z');
    expect(
      chatRoomHasUnread(myId: 'me', lastAt: lastAt, lastSenderId: 'me'),
      isFalse,
    );
    expect(
      chatRoomHasUnread(myId: 'me', lastAt: lastAt, lastSenderId: 'them'),
      isTrue,
    );
    expect(
      chatRoomHasUnread(
        myId: 'me',
        lastAt: lastAt,
        lastSenderId: 'them',
        lastReadAt: DateTime.parse('2026-09-05T10:01:00Z'),
      ),
      isFalse,
    );
  });
}
