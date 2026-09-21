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

  test('home diet and cuisine chips filter without changing saved prefs', () {
    expect(feedDietChipFromPreference('Vegetarian'), 'Veg');
    expect(feedDietChipFromPreference('Non-Vegetarian'), 'All');
    expect(mealMatchesFeedDiet({'title': 'Butter Chicken', 'is_veg': false}, 'Veg'), isFalse);
    expect(mealMatchesFeedDiet({'title': 'Ragi dosa', 'is_veg': true}, 'Millet'), isTrue);
    expect(mealMatchesFeedDiet({'title': 'Dal rice', 'health_tags': ['High-protein']}, 'High-protein'), isTrue);
    expect(mealMatchesFeedDiet({'title': 'Gulab jamun', 'is_veg': true}, 'Diabetic'), isFalse);
    expect(mealIsVegetarian({'title': 'Veg Biryani', 'is_veg': true}), isTrue);
    expect(mealIsVegetarian({'title': 'Egg Dish', 'is_veg': false}), isFalse);
    expect(mealIsVegetarian({'title': 'Puran Poli'}), isTrue);
    expect(mealIsVegetarian({'title': 'Egg bhurji'}), isFalse);
    expect(mealIsVegetarian({'is_veg': 'true'}), isTrue);
    expect(mealMatchesCuisine({'title': 'Misal pav', 'category': 'Snacks'}, 'Maharashtrian'), isTrue);
    expect(mealMatchesCuisine({'title': 'Idli sambar', 'category': 'South Indian'}, 'Punjabi'), isFalse);
    expect(mealMatchesCuisine({'title': 'Quinoa bowl', 'category': 'Healthy & Salads'}, 'Healthy'), isTrue);
  });

  test('favorites filter turns off after logout', () {
    expect(feedFavoritesFilterActive(signedIn: false, favoritesOnly: true), isFalse);
    expect(feedFavoritesFilterActive(signedIn: true, favoritesOnly: true), isTrue);
    expect(feedFollowingFilterActive(signedIn: false, followingOnly: true), isFalse);
    expect(feedFollowingFilterActive(signedIn: true, followingOnly: true), isTrue);
    expect(canFollowKitchen(viewerId: 'diner-1', chefId: 'chef-1'), isTrue);
    expect(canFollowKitchen(viewerId: 'chef-1', chefId: 'chef-1'), isFalse);
    expect(canFollowKitchen(chefId: ''), isFalse);
  });

  test('empty feed copy matches favorites, category, and guest', () {
    expect(
      feedEmptyCopy(signedIn: false, favoritesOnly: true, hasFavorites: false, hasSearch: false).title,
      'Sign in to see favorites',
    );
    expect(
      feedEmptyCopy(signedIn: true, favoritesOnly: true, hasFavorites: false, hasSearch: false).title,
      'No favorites yet',
    );
    expect(
      feedEmptyCopy(
        signedIn: true,
        favoritesOnly: false,
        hasFavorites: false,
        hasSearch: false,
        followingOnly: true,
        hasFollows: false,
      ).title,
      'No kitchens followed yet',
    );
    final category = feedEmptyCopy(
      signedIn: false,
      favoritesOnly: false,
      hasFavorites: false,
      hasSearch: false,
      category: 'Maharashtrian',
    );
    expect(category.title, 'No Maharashtrian meals');
    expect(category.clearCategory, isTrue);
    final diet = feedEmptyCopy(
      signedIn: true,
      favoritesOnly: false,
      hasFavorites: false,
      hasSearch: false,
      diet: 'Jain',
    );
    expect(diet.title, 'No Jain meals');
    expect(diet.clearCategory, isTrue);
    final offers = feedEmptyCopy(
      signedIn: true,
      favoritesOnly: false,
      hasFavorites: false,
      hasSearch: true,
      offerBrowseGroupKey: 'flashSale',
    );
    expect(offers.title, 'No Flash Sale plates nearby');
    final outside = feedEmptyCopy(
      signedIn: true,
      favoritesOnly: false,
      hasFavorites: false,
      hasSearch: false,
      outOfServiceArea: true,
    );
    expect(outside.title, contains('Pune'));
    expect(
      feedEmptyCopy(
        signedIn: true,
        favoritesOnly: false,
        hasFavorites: false,
        hasSearch: false,
        homeMode: 'heat',
      ).title,
      'No healthy plates nearby',
    );
    expect(
      feedEmptyCopy(
        signedIn: true,
        favoritesOnly: false,
        hasFavorites: false,
        hasSearch: false,
        homeMode: 'preorder',
      ).title,
      'No pre-order slots nearby',
    );
  });

  test('home Live / Pre-order / Healthy chips filter the catalog', () {
    final evening = DateTime(2026, 9, 21, 19, 39);
    final noon = DateTime(2026, 9, 21, 12);
    final quinoa = {'title': 'Quinoa bowl', 'category': 'Healthy & Salads'};
    final ragi = {'title': 'Ragi dosa', 'is_veg': true};
    final dal = {'title': 'Dal tadka', 'time_slot': 'ASAP'};
    final dinner = {'title': 'Biryani', 'time_slot': 'Daily (6:30 PM to 9:30 PM)'};
    final breakfast = {'title': 'Breakfast', 'time_slot': 'Daily (8:00 AM to 11:00 AM)'};
    final booked = {'title': 'Hourly thali', 'time_slot': '7:00 PM to 8:00 PM'};
    final futureOneOff = {'title': 'Weekend thali', 'time_slot': '22 Sep, 1:00 PM to 2:00 PM'};

    expect(mealMatchesHomeMode(quinoa, mode: 'heat'), isTrue);
    expect(mealMatchesHomeMode(ragi, mode: 'healthy'), isTrue);
    expect(mealMatchesHomeMode(dal, mode: 'heat'), isFalse);
    expect(mealMatchesHomeMode(dal, mode: 'preorder', now: evening), isFalse);
    expect(mealMatchesHomeMode(dal, mode: 'live', now: evening), isTrue);

    expect(mealMatchesHomeMode(dinner, mode: 'live', now: evening), isTrue);
    expect(mealMatchesHomeMode(dinner, mode: 'preorder', now: evening), isTrue);
    expect(mealMatchesHomeMode(breakfast, mode: 'live', now: evening), isFalse);
    expect(mealMatchesHomeMode(breakfast, mode: 'preorder', now: evening), isTrue);

    expect(mealMatchesHomeMode(booked, mode: 'live', now: evening), isTrue);
    expect(mealMatchesHomeMode(booked, mode: 'preorder', now: evening), isTrue);
    expect(mealMatchesHomeMode(booked, mode: 'live', now: noon), isFalse);
    expect(mealMatchesHomeMode(booked, mode: 'preorder', now: noon), isTrue);

    expect(mealMatchesHomeMode(futureOneOff, mode: 'live', now: evening), isFalse);
    expect(mealMatchesHomeMode(futureOneOff, mode: 'preorder', now: evening), isTrue);
    expect(
      mealMatchesHomeMode(dinner, mode: 'live', now: evening, chefProfile: {'is_open': false}),
      isFalse,
    );
  });

  test('home sort chips order by price, rating, then distance', () {
    final meals = [
      {'id': 'a', 'price': 220.0, 'chef_id': 'c1'},
      {'id': 'b', 'price': 140.0, 'chef_id': 'c2'},
      {'id': 'c', 'price': 180.0, 'chef_id': 'c3'},
    ];
    double? km(Map<String, dynamic> meal) {
      switch (meal['id']) {
        case 'a':
          return 8;
        case 'b':
          return 3;
        default:
          return 1;
      }
    }

    expect(
      sortFeedMeals(meals, sort: kFeedSortPrice, distanceKm: km).map((m) => m['id']),
      ['b', 'c', 'a'],
    );
    expect(
      sortFeedMeals(meals, sort: kFeedSortNearby, distanceKm: km).map((m) => m['id']),
      ['c', 'b', 'a'],
    );
    expect(
      sortFeedMeals(
        meals,
        sort: kFeedSortRating,
        distanceKm: km,
        rating: (m) => m['id'] == 'a' ? 4.8 : 4.1,
      ).map((m) => m['id']),
      ['a', 'c', 'b'],
    );
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
