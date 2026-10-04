import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/delivery_fee.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

/// Veg Jumbo Thali 0E61A568: diner paid ₹241, delivery ₹0, driver ₹20,
/// stored chef_payout ₹184.85 (85% of food+pack, minus the ₹20 stipend).
Map<String, dynamic> _thali({String? deliveredAt}) => {
  'id': '0E61A568',
  'status': 'Delivered',
  'order_type': 'Delivery Partner',
  'total_price': 241,
  'packaging_fee': 20,
  'delivery_fee': 0,
  'driver_payout': 20,
  'chef_payout': 184.85,
  'payout_status': 'pending',
  'delivered_at': deliveredAt ?? '2026-10-04T22:53:00',
  'items': [
    {'title': 'Veg Jumbo Thali', 'quantity': 1, 'price': 221, 'line_net': 221},
  ],
};

/// Breakfast 4D6B2765: total ₹100, packaging ₹10, driver_payout ₹40, chef_payout ₹0.
Map<String, dynamic> _breakfast({
  String? deliveredAt,
  String status = 'Delivered',
}) => {
  'id': '4D6B2765',
  'status': status,
  'order_type': 'Delivery Partner',
  'total_price': 100,
  'packaging_fee': 10,
  'delivery_fee': 0,
  'driver_payout': 40,
  'chef_payout': 0,
  'payout_status': 'pending',
  'delivered_at': deliveredAt ?? '2026-10-04T12:27:00',
  'items': [
    {'title': 'Breakfast', 'quantity': 1, 'price': 90, 'line_net': 90},
  ],
};

void main() {
  final day = DateTime(2026, 10, 4, 18);

  group('free-delivery share caption', () {
    test('names the ₹20 already inside a stored chef payout', () {
      final order = _thali();
      expect(chefPayoutForOrder(order).chefPayout, 184.85);
      expect(chefOrderPayoutAmountLabel(order), '₹184.85');
      expect(chefOrderPayoutEstimateTag(order), isNull);

      final caption = chefFreeDeliveryShareCaption(order);
      expect(caption, contains(formatRupees(kFreeDeliveryDriverPayout)));
      expect(caption, contains('driver'));
      expect(caption, contains('₹199'));
      expect(caption, isNot(contains('₹184.85')));
    });

    test('unset payout still nets the stipend and keeps the caption', () {
      final order = _thali()..['chef_payout'] = 0;
      final gross = chefPayoutBreakdown(itemsTotal: 221, packagingFee: 20);
      expect(
        chefPayoutForOrder(order).chefPayout,
        roundMoney(gross.chefPayout - kFreeDeliveryDriverPayout),
      );
      expect(
        chefFreeDeliveryShareCaption(order),
        contains(formatRupees(kFreeDeliveryDriverPayout)),
      );
      expect(chefOrderPayoutEstimateTag(order), 'Estimated');
    });

    test('breakfast under ₹199 with a ₹40 driver payout grows no ₹20 line', () {
      final order = _breakfast();
      expect(chefPayoutForOrder(order).chefPayout, 85);
      expect(chefFreeDeliveryShareCaption(order), isEmpty);
      expect(chefOrderPayoutAmountLabel(order), 'Estimated ₹85.00');
      expect(freeDeliveryDriverStipend(order), 0);
    });

    test('paid delivery and the old ₹40 fallback grow no ₹20 line', () {
      final paid = {
        'order_type': 'Delivery Partner',
        'delivery_fee': 30,
        'driver_payout': 30,
        'packaging_fee': 20,
        'chef_payout': 145.35,
        'items': [
          {'title': 'Thali', 'quantity': 1, 'price': 151, 'line_net': 151},
        ],
      };
      expect(chefFreeDeliveryShareCaption(paid), isEmpty);
      expect(chefOrderPayoutAmountLabel(paid), '₹145.35');

      final fallback = {
        'order_type': 'Delivery Partner',
        'delivery_fee': 0,
        'driver_payout': 40,
        'packaging_fee': 20,
        'chef_payout': 0,
        'items': [
          {'title': 'Thali', 'quantity': 1, 'price': 220, 'line_net': 220},
        ],
      };
      final gross = chefPayoutBreakdown(itemsTotal: 220, packagingFee: 20);
      expect(chefPayoutForOrder(fallback).chefPayout, gross.chefPayout);
      expect(chefFreeDeliveryShareCaption(fallback), isEmpty);
      expect(
        chefOrderPayoutAmountLabel(fallback),
        'Estimated ${formatRupees(gross.chefPayout)}',
      );
    });

    test('chef-self delivery does not invent a driver share line', () {
      final self = _thali()..['order_type'] = 'Chef-Self';
      expect(chefFreeDeliveryShareCaption(self), isEmpty);
      expect(chefPayoutForOrder(self).chefPayout, 184.85);
    });
  });

  group("today's earnings", () {
    test('keeps paise and labels the day, not a lifetime total', () {
      final yesterday = _breakfast(deliveredAt: '2026-10-03T12:27:00');
      final preparing = _breakfast(
        status: 'Preparing',
        deliveredAt: '2026-10-04T12:27:00',
      );
      final orders = [_thali(), _breakfast(), yesterday, preparing];

      expect(chefEarningsForLocalDay(orders, day), 269.85);
      expect(formatChefTodayEarnings(269.85), '₹269.85');
      expect(
        formatChefTodayEarnings(chefEarningsForLocalDay(orders, day)),
        isNot('₹270'),
      );
      expect(kChefTodayEarningsLabel, "Today's Earnings");
      expect(kChefTodayEarningsLabel.toLowerCase(), isNot(contains('total')));
    });

    test('says when today includes an unset chef payout', () {
      final note = chefTodayEarningsEstimateNote([_thali(), _breakfast()], day);
      expect(note.toLowerCase(), contains('estimated'));
      expect(note, contains('₹85.00'));

      expect(chefTodayEarningsEstimateNote([_thali()], day), isEmpty);
    });
  });

  group('payout analytics ledger', () {
    test(
      'stored hero excludes zero chef_payout rows and labels the estimate',
      () {
        final orders = [_thali(), _breakfast()];
        final ledger = chefPayoutLedger(orders);

        expect(
          chefPayoutForOrder(_thali()).chefPayout +
              chefPayoutForOrder(_breakfast()).chefPayout,
          269.85,
        );
        expect(ledger.blended, 269.85);
        expect(ledger.stored, 184.85);
        expect(ledger.storedOrders, 1);
        expect(ledger.estimated, 85);
        expect(ledger.estimatedOrders, 1);

        expect(chefStoredPayoutHeadline(ledger), '₹184.85');
        expect(chefStoredPayoutHeadline(ledger), isNot('₹269.85'));
        expect(kChefStoredPayoutLabel.toLowerCase(), contains('stored'));

        final line = chefEstimatedPayoutLine(ledger);
        expect(line, contains('Estimated'));
        expect(line, contains('₹85.00'));
        expect(line, contains('₹0'));
        expect(line, isNot(contains('₹184.85')));
        expect(line, isNot(contains('₹269.85')));
      },
    );

    test('a kitchen of unset rows does not become a stored payout', () {
      final zeros = List<Map<String, dynamic>>.generate(26, (i) {
        return _breakfast()..['id'] = 'zero-$i';
      });
      final orders = [...zeros, _thali()];
      final ledger = chefPayoutLedger(orders);

      expect(ledger.stored, 184.85);
      expect(ledger.storedOrders, 1);
      expect(ledger.estimatedOrders, 26);
      expect(ledger.estimated, roundMoney(85 * 26));
      expect(chefStoredPayoutHeadline(ledger), '₹184.85');
      expect(
        chefEstimatedPayoutLine(ledger),
        contains('26 orders still store ₹0'),
      );
      expect(chefEstimatedPayoutLine(ledger), contains('Estimated'));
    });

    test('all-stored history has no estimate line', () {
      final ledger = chefPayoutLedger([_thali()]);
      expect(ledger.stored, 184.85);
      expect(ledger.estimated, 0);
      expect(chefEstimatedPayoutLine(ledger), isEmpty);
      expect(chefStoredPayoutHeadline(ledger), formatRupees(ledger.stored));
    });
  });
}
