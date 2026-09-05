import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  test('wallet history prefers ledger rows and falls back to order spends', () {
    final fromLedger = mergeCoinLedger(
      transactions: [
        {
          'amount': 15,
          'transaction_type': 'earning',
          'description': 'Daily streak bonus',
          'created_at': '2026-09-05T00:00:00Z',
        },
        {
          'amount': 15,
          'transaction_type': 'payment',
          'description': 'Coins applied at checkout',
          'created_at': '2026-09-05T01:00:00Z',
        },
      ],
      orders: [
        {'id': 'ignored', 'coins_applied': 15, 'created_at': '2026-09-04T19:21:00Z'},
      ],
    );
    expect(fromLedger, hasLength(2));
    expect(fromLedger.first.isDebit, isTrue);
    expect(fromLedger.last.isDebit, isFalse);

    final fromOrders = mergeCoinLedger(
      transactions: const [],
      orders: [
        {'id': 'ord-1', 'coins_applied': 15, 'created_at': '2026-09-04T19:21:00Z'},
        {'id': 'ord-2', 'coins_applied': 0, 'created_at': '2026-09-04T19:25:00Z'},
      ],
    );
    expect(fromOrders, hasLength(1));
    expect(fromOrders.first.isDebit, isTrue);
    expect(fromOrders.first.amount, 15);
  });
}
