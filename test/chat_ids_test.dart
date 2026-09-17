import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/chat_ids.dart';

void main() {
  group('ChatIds.isCartLineId / stripCartLineSuffix', () {
    test('detects mealId_timestamp cart lines', () {
      expect(ChatIds.isCartLineId('meal-abc_1710000000000'), isTrue);
      expect(ChatIds.isCartLineId('meal-abc_1710000000000123'), isTrue);
      expect(ChatIds.stripCartLineSuffix('meal-abc_1710000000000'), 'meal-abc');
    });

    test('leaves meal UUIDs and request ids alone', () {
      expect(ChatIds.isCartLineId('a1b2c3d4-e5f6-7890-abcd-ef1234567890'), isFalse);
      expect(ChatIds.isCartLineId('request_lead-1'), isFalse);
      expect(ChatIds.stripCartLineSuffix('meal-abc'), 'meal-abc');
    });
  });

  group('ChatIds.mealRoomId', () {
    test('prefers source_meal_id over cart line id', () {
      expect(
        ChatIds.mealRoomId({
          'id': 'meal-abc_1710000000000',
          'source_meal_id': 'meal-abc',
        }),
        'meal-abc',
      );
    });

    test('prefers mealId when source_meal_id is missing', () {
      expect(
        ChatIds.mealRoomId({
          'id': 'meal-abc_1710000000000',
          'mealId': 'meal-abc',
        }),
        'meal-abc',
      );
    });

    test('strips a cart-line source_meal_id', () {
      expect(
        ChatIds.mealRoomId({'source_meal_id': 'meal-abc_1710000000000'}),
        'meal-abc',
      );
    });

    test('reads nested cart items JSON', () {
      expect(
        ChatIds.mealRoomId({
          'id': 'order-uuid-1',
          'items': '[{"id":"meal-abc_1710000000000","mealId":"meal-abc"}]',
        }),
        'meal-abc',
      );
    });

    test('does not use an order UUID as the room', () {
      expect(
        ChatIds.mealRoomId({
          'id': 'order-uuid-1',
          'status': 'Preparing',
          'customer_id': 'cust-1',
        }),
        isEmpty,
      );
    });
  });

  group('ChatIds.bulkRequestRoomId', () {
    test('prefixes request ids once', () {
      expect(ChatIds.bulkRequestRoomId('lead-9'), 'request_lead-9');
      expect(ChatIds.bulkRequestRoomId('request_lead-9'), 'request_lead-9');
      expect(ChatIds.bulkRequestRoomId(''), isEmpty);
    });
  });

  group('ChatIds.location', () {
    test('builds /chat/:mealId with optional roomName', () {
      expect(ChatIds.location('meal-abc'), '/chat/meal-abc');
      expect(
        ChatIds.location('meal-abc', roomName: 'Order HPC1'),
        '/chat/meal-abc?roomName=Order+HPC1',
      );
    });
  });
}
