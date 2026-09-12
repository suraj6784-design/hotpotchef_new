import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  test('fresh kitchen photos count as live for a few hours', () {
    final now = DateTime(2026, 9, 6, 12);
    expect(
      isKitchenLivePhotoFresh(now.subtract(const Duration(hours: 1)), now: now),
      isTrue,
    );
    expect(
      isKitchenLivePhotoFresh(now.subtract(const Duration(hours: 5)), now: now),
      isFalse,
    );
    expect(isKitchenLivePhotoFresh(null, now: now), isFalse);
    expect(
      kitchenLivePhotoLabel(now.subtract(const Duration(minutes: 12)), now: now),
      'Fresh kitchen photo · 12m ago',
    );
  });

  test('packed box photo copy is only for a real kitchen shot', () {
    expect(hasDispatchPhoto({'dispatch_photo_url': 'https://cdn.example/box.jpg'}), isTrue);
    expect(hasDispatchPhoto({'dispatch_photo_url': ''}), isFalse);
    expect(
      dispatchPackedLabel(takenAt: DateTime.now().subtract(const Duration(seconds: 20))),
      'Your box is packed · just now',
    );
  });

  test('cooked meal copy stays readable', () {
    expect(cookedMealsLabel(0), 'New kitchen');
    expect(cookedMealsLabel(1), 'Cooked 1 meal');
    expect(cookedMealsLabel(12), 'Cooked 12 meals');
    expect(
      cookedMealCountFromOrders([
        {'status': 'Out for Delivery'},
        {'status': 'Delivered'},
        {'status': 'Pending Chef Approval'},
      ]),
      2,
    );
  });
}
