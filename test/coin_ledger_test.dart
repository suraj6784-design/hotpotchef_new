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
        {
          'id': 'abcdef12-3456-7890-abcd-ef1234567890',
          'coins_applied': 15,
          'created_at': '2026-09-05T01:00:30Z',
        },
      ],
    );
    expect(fromLedger, hasLength(2));
    expect(fromLedger.first.isDebit, isTrue);
    expect(fromLedger.first.orderRef, 'ABCDEF12');
    expect(fromLedger.last.isDebit, isFalse);
    expect(fromLedger.last.orderRef, isNull);

    final fromOrders = mergeCoinLedger(
      transactions: const [],
      orders: [
        {'id': 'ord-1abc', 'coins_applied': 15, 'created_at': '2026-09-04T19:21:00Z'},
        {'id': 'ord-2', 'coins_applied': 0, 'created_at': '2026-09-04T19:25:00Z'},
      ],
    );
    expect(fromOrders, hasLength(1));
    expect(fromOrders.first.isDebit, isTrue);
    expect(fromOrders.first.amount, 15);
    expect(fromOrders.first.orderRef, 'ORD-1ABC');
  });

  test('coinCheckoutDebitTitle appends brief order ref once', () {
    expect(
      coinCheckoutDebitTitle(base: 'Coins applied at checkout', orderRef: 'ABC12345'),
      'Coins applied at checkout · ABC12345',
    );
    expect(
      coinCheckoutDebitTitle(base: 'Coins applied at checkout · ABC12345', orderRef: 'ABC12345'),
      'Coins applied at checkout · ABC12345',
    );
  });

  test('wallet order summary shows dish, rupee total, and extra items', () {
    final summary = walletOrderSummaryFrom({
      'id': 'abcdef12-3456-7890-abcd-ef1234567890',
      'order_id': 'HP-1042',
      'status': 'out_for_delivery',
      'total_price': 420,
      'coins_applied': 15,
      'created_at': '2026-09-09T11:45:00Z',
      'items': [
        {'title': 'Paneer Butter Masala'},
        {'name': 'Jeera Rice'},
      ],
    });
    expect(summary.orderRef, isNotEmpty);
    expect(summary.dishLine, 'Paneer Butter Masala (+1 more)');
    expect(summary.statusLabel, 'Out For Delivery');
    expect(summary.total, 420);
    expect(summary.coinsApplied, 15);
  });

  test('checkout coin rows attach dish summary when coins_applied is missing', () {
    final entries = mergeCoinLedger(
      transactions: [
        {
          'amount': 15,
          'transaction_type': 'payment',
          'description': 'Coins applied at checkout',
          'created_at': '2026-09-09T11:45:00Z',
        },
      ],
      orders: [
        {
          'id': 'abcdef12-3456-7890-abcd-ef1234567890',
          'coins_applied': 0,
          'total_price': 320,
          'created_at': '2026-09-09T11:40:00Z',
          'items': [
            {'title': 'Veg Thali'},
          ],
        },
      ],
    );
    expect(entries, hasLength(1));
    expect(entries.first.orderRef, 'ABCDEF12');
    expect(entries.first.detail, 'Veg Thali · ₹320');
    expect(entries.first.title, 'Coins applied at checkout');
    expect(coinWalletOrderNumber(entries.first.orderRef), 'Order #ABCDEF12');
  });

  test('credited coins on an order show the same Order # as checkout', () {
    final entries = mergeCoinLedger(
      transactions: [
        {
          'amount': 15,
          'transaction_type': 'earning',
          'description': 'HotPot Coins credited',
          'created_at': '2026-09-11T02:44:00Z',
        },
        {
          'amount': 15,
          'transaction_type': 'payment',
          'description': 'Coins applied at checkout',
          'created_at': '2026-09-11T02:44:05Z',
        },
        {
          'amount': 15,
          'transaction_type': 'earning',
          'description': 'Daily streak bonus',
          'created_at': '2026-09-11T08:08:00Z',
        },
      ],
      orders: [
        {
          'id': '65709a47-aaaa-bbbb-cccc-ddddeeeeffff',
          'coins_applied': 15,
          'created_at': '2026-09-11T02:44:10Z',
          'items': [
            {'title': 'Veg Biryani'},
          ],
        },
      ],
    );
    expect(entries[0].isDebit, isFalse);
    expect(entries[0].title, 'Daily streak bonus');
    expect(entries[0].orderRef, isNull);
    expect(entries[1].isDebit, isTrue);
    expect(coinWalletOrderNumber(entries[1].orderRef), 'Order #65709A47');
    expect(entries[2].isDebit, isFalse);
    expect(coinWalletOrderNumber(entries[2].orderRef), 'Order #65709A47');
  });

  test('coinWalletOrderNumber prefixes Order # once', () {
    expect(coinWalletOrderNumber('ABC12345'), 'Order #ABC12345');
    expect(coinWalletOrderNumber('Order ABC12345'), 'Order #ABC12345');
  });
}
