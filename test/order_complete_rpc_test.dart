import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/services/order_repository.dart';

void main() {
  test('completing a delivery never falls back to a direct orders.update', () {
    expect(OrderRepository.allowDirectStatusWrite(completing: true), isFalse);
    expect(OrderRepository.allowDirectStatusWrite(completing: false), isTrue);
  });
}
