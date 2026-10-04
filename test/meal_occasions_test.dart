import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/delivery_fee.dart';
import 'package:hotpotchef_new/utils/diner_meal_catalog.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('occasion browse', () {
    test('classifies the home-cooked groups from the dish itself', () {
      expect(mealOccasionId({'title': 'Dal rice', 'time_slot': '1:00 PM'}), kOccasionEveryday);
      expect(mealOccasionId({'title': 'Plain biryani'}), kOccasionEveryday);
      expect(mealOccasionId({'title': 'Winter bhaji'}), kOccasionEveryday);
      expect(mealOccasionId({'title': 'Summer buttermilk'}), kOccasionEveryday);
      expect(mealOccasionId({'title': 'Light soup', 'is_seasonal': true}), kOccasionEveryday);

      expect(mealOccasionId({'title': 'Diwali laddu'}), kOccasionFestive);
      expect(mealOccasionId({'title': 'Diwali barfi'}), kOccasionFestive);
      expect(mealOccasionId({'title': 'Holi gujiya'}), kOccasionFestive);
      expect(mealOccasionId({'title': 'Holi namkeen'}), kOccasionFestive);
      expect(mealOccasionId({'title': 'Eid biryani'}), kOccasionFestive);
      expect(mealOccasionId({'title': 'Christmas cake'}), kOccasionFestive);
      expect(mealOccasionId({'title': 'Family gathering thali'}), kOccasionFestive);
      expect(mealOccasionId({'title': 'Sattvic prasad'}), kOccasionFestive);
      expect(mealOccasionId({'title': 'Housewarming lunch'}), kOccasionFestive);

      expect(mealOccasionId({'title': 'Birthday cake'}), kOccasionParty);
      expect(mealOccasionId({'title': 'Birthday laddu'}), kOccasionParty);
      expect(mealOccasionId({'title': 'Anniversary platter'}), kOccasionParty);
      expect(mealOccasionId({'title': 'Office snacks'}), kOccasionParty);
      expect(mealOccasionId({'title': 'Community pickle', 'is_society_night': true}), kOccasionParty);

      expect(mealOccasionId({'title': 'Mango pickle'}), kOccasionSpecialty);
      expect(mealOccasionId({'title': 'Lemon achar'}), kOccasionSpecialty);
      expect(mealOccasionId({'title': 'Namkeen'}), kOccasionSpecialty);
      expect(mealOccasionId({'title': 'Chakli'}), kOccasionSpecialty);
      expect(mealOccasionId({'title': 'Besan laddu'}), kOccasionSpecialty);
      expect(mealOccasionId({'title': 'Motichoor laddu'}), kOccasionSpecialty);
      expect(mealOccasionId({'title': 'Ganesh modak'}), kOccasionSpecialty);
      expect(mealOccasionId({'title': 'Til laddu'}), kOccasionSpecialty);
    });

    test('word boundaries keep holiday and several out of the wrong tab', () {
      expect(mealOccasionId({'title': 'Holiday thali'}), kOccasionEveryday);
      expect(mealOccasionId({'title': 'Several rotis'}), kOccasionEveryday);
    });

    test('an explicit meal occasion wins over the title', () {
      expect(
        mealOccasionId({'title': 'Diwali laddu', 'occasion': 'specialty'}),
        kOccasionSpecialty,
      );
    });

    test('slices stay inside the group the dish already belongs to', () {
      expect(
        mealMatchesOccasion({'title': 'Diabetic lunch', 'time_slot': '12:30 PM'}, kOccasionEveryday, slice: 'diet'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Diabetic lunch', 'time_slot': '12:30 PM'}, kOccasionEveryday, slice: 'lunch'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Winter bhaji'}, kOccasionEveryday, slice: 'seasonal'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Diwali laddu'}, kOccasionFestive, slice: 'diwali'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Diwali laddu'}, kOccasionSpecialty, slice: 'sweet'),
        isFalse,
      );
      expect(
        mealMatchesOccasion({'title': 'Holi gujiya'}, kOccasionFestive, slice: 'holi'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Eid biryani'}, kOccasionFestive, slice: 'eid'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Christmas cake'}, kOccasionFestive, slice: 'christmas'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Family gathering thali'}, kOccasionFestive, slice: 'gathering'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Naming ceremony prasad'}, kOccasionFestive, slice: 'ceremony'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Birthday finger food'}, kOccasionParty, slice: 'birthday'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Anniversary platter'}, kOccasionParty, slice: 'anniversary'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Office bulk snacks'}, kOccasionParty, slice: 'office'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Community namkeen', 'is_society_night': true}, kOccasionParty, slice: 'community'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Mixed achar'}, kOccasionSpecialty, slice: 'pickle'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Samosa'}, kOccasionSpecialty, slice: 'savory'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Peda'}, kOccasionSpecialty, slice: 'sweet'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Ganesh modak'}, kOccasionSpecialty, slice: 'seasonal'),
        isTrue,
      );
      expect(
        mealMatchesOccasion({'title': 'Ganesh modak'}, kOccasionFestive, slice: 'all'),
        isFalse,
      );
    });

    test('festivals and parties stay listed for a future slot while live is selected', () {
      final laddu = {'title': 'Diwali laddu'};
      expect(
        mealListedForOccasion(
          meal: laddu,
          occasion: kOccasionFestive,
          matchesHomeMode: false,
          hasFutureSlot: true,
        ),
        isTrue,
      );
      expect(
        mealListedForOccasion(
          meal: {'title': 'Birthday cake'},
          occasion: kOccasionParty,
          matchesHomeMode: false,
          hasFutureSlot: true,
        ),
        isTrue,
      );
      expect(
        mealListedForOccasion(
          meal: {'title': 'Dal rice'},
          occasion: kOccasionEveryday,
          matchesHomeMode: false,
          hasFutureSlot: true,
        ),
        isFalse,
      );
      expect(
        mealListedForOccasion(
          meal: {'title': 'Mango pickle'},
          occasion: kOccasionSpecialty,
          matchesHomeMode: false,
          hasFutureSlot: true,
        ),
        isFalse,
      );
    });

    test('narrow tabs name the empty state and everyday all stays the old copy', () {
      final everyday = feedEmptyCopy(
        signedIn: true,
        favoritesOnly: false,
        hasFavorites: false,
        hasSearch: false,
        hasDeliveryPin: true,
      );
      expect(everyday.title, 'No meals found');

      final diwali = feedEmptyCopy(
        signedIn: true,
        favoritesOnly: false,
        hasFavorites: false,
        hasSearch: false,
        hasDeliveryPin: true,
        occasion: kOccasionFestive,
        occasionSlice: 'diwali',
      );
      expect(diwali.title, 'No Diwali meals');
      expect(diwali.clearCategory, isTrue);
    });
  });

  group('occasion on the order', () {
    test('a daily plate stays everyday and keeps the checkout fields', () {
      final payload = checkoutCartPayload([
        {
          'chef_id': 'chef-1',
          'title': 'Dal rice',
          'quantity': 1,
          'price': 120,
          'service_type': 'Delivery Partner',
          'rawMealDetails': {
            'id': 'meal-dal',
            'chef_id': 'chef-1',
            'price': 120,
            'title': 'Dal rice',
          },
        },
      ]);

      expect(payload, hasLength(1));
      expect(payload.single['occasion'], kOccasionEveryday);
      expect(payload.single['chef_id'], 'chef-1');
      expect(payload.single['price'], isNotNull);
      expect(payload.single['service_type'], 'Delivery Partner');
      expect(payload.single['rawMealDetails']['occasion'], kOccasionEveryday);
    });

    test('a Diwali laddu is tagged festive on the checkout line', () {
      final payload = checkoutCartPayload([
        {
          'chef_id': 'chef-2',
          'title': 'Diwali laddu',
          'quantity': 2,
          'price': 240,
          'rawMealDetails': {'id': 'meal-laddu', 'title': 'Diwali laddu'},
        },
      ]);
      expect(payload.single['occasion'], kOccasionFestive);
    });

    test('the order column wins and a missing occasion stays unlabeled', () {
      expect(
        orderOccasionId(column: 'party', items: const [
          {'occasion': 'everyday'},
        ]),
        kOccasionParty,
      );
      expect(orderOccasionId(column: null, items: const []), isNull);
      expect(occasionTabLabel(orderOccasionId()), '');
      expect(
        orderOccasionId(items: const [
          {
            'title': 'Old dal',
            'rawMealDetails': {'title': 'Old dal'},
          },
        ]),
        isNull,
      );
    });
  });

  group('broadcast every occasion', () {
    test('each tab and slice can be sent to every nearby kitchen', () {
      final when = DateTime(2026, 11, 2, 18, 30);
      for (final tab in kOccasionTabs) {
        for (final slice in tab.slices) {
          final body = occasionBroadcastInsert(
            customerId: 'diner-1',
            occasion: tab.id,
            slice: slice.id,
            note: '${tab.label} ${slice.label}',
            details: 'Less oil',
            quantity: 1,
            address: '12 Lane, Pune',
            targetLocal: when,
            serviceType: 'Delivery Partner',
            budget: 800,
          );
          expect(body['request_type'], kBroadcastRequestType, reason: tab.id);
          expect(body['occasion'], tab.id);
          expect(body['target_chef_ids'], isEmpty);
          expect(body['quantity'], 1);
          expect(body['remaining_quantity'], 1);
          expect(body['status'], 'Open');
          expect(body['description'].toString(), startsWith('Occasion:'));
          expect(body['description'].toString(), contains(tab.label));
          if (slice.id == kOccasionSliceAll) {
            expect(body['occasion_slice'], isNull);
          } else {
            expect(body['occasion_slice'], slice.id);
            expect(body['description'].toString(), contains(slice.label));
          }
        }
      }
    });

    test('a one-portion ask is still a broadcast', () {
      final body = occasionBroadcastInsert(
        customerId: 'diner-1',
        occasion: kOccasionEveryday,
        slice: 'lunch',
        quantity: 0,
        address: 'Home',
        targetLocal: DateTime(2026, 10, 6, 13),
        serviceType: 'Delivery Partner',
      );
      expect(body['quantity'], 1);
      expect(body['occasion'], kOccasionEveryday);
      expect(body['occasion_slice'], 'lunch');
    });

    test('paying a quoted broadcast keeps the occasion on the cart line', () {
      for (final tab in kOccasionTabs) {
        final items = checkoutItemsFromCateringRequest({
          'id': 'req-${tab.id}',
          'title': '${tab.label} request',
          'quantity': 4,
          'budget': 400,
          'accepted_chef_id': 'chef-9',
          'service_type': 'Delivery Partner',
          'target_date_time': '2026-11-02T13:00:00.000Z',
          'occasion': tab.id,
          'description': 'Occasion: ${tab.label}',
        });
        expect(items.single['occasion'], tab.id);
        expect(items.single['chef_id'], 'chef-9');
      }
    });

    test('chefs still see the occasion when the new columns are absent', () {
      expect(
        broadcastOccasionLabel({
          'description': 'Occasion: Parties · Birthday\nEggless',
        }),
        'Parties · Birthday',
      );
      expect(
        broadcastOccasionLabel({
          'occasion': 'specialty',
          'occasion_slice': 'pickle',
          'description': 'ignored',
        }),
        'Specialty · Pickles',
      );
    });
  });

  test('catalog selects request occasion only on the full diner list', () {
    expect(kHomeMealCatalogSelect.split(',').map((part) => part.trim()), contains('occasion'));
    expect(kHomeMealCatalogSelectMinimal.contains('occasion'), isFalse);
    expect(dinerMealCatalogColumnSet(), contains('occasion'));
  });
}
