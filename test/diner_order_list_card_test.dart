import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/widgets/diner_order_list_card.dart';

/// Past order 695B9CD2 as it appeared on the oversized diner card.
void main() {
  Future<void> pumpCard(WidgetTester tester, {required Widget card}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.topCenter, child: card),
        ),
      ),
    );
  }

  DinerOrderListCard pastBreakfast({
    VoidCallback? onReorder,
    VoidCallback? onOpenDetails,
  }) {
    return DinerOrderListCard(
      orderIdLabel: '695B9CD2',
      chefName: 'newchef16',
      lineLabel: '1x Breakfast',
      badgeLabel: 'Cancelled',
      statusLine: 'Status: Cancelled',
      statusColor: Colors.red,
      priceLabel: '₹100',
      orderType: 'Delivery Partner',
      placedLabel: '25 Sep 2026, 10:14 PM',
      slotLabel: '26 Sep 2026, 09:00 AM',
      addressLabel: 'Dropoff: ',
      addressValue: '9, Thergaon, Pimpri-Chinchwad, Maharashtra - 411033',
      isPickup: false,
      deliveryPin: '8779',
      dimmed: true,
      showReorder: true,
      onReorder: onReorder,
      onOpenDetails: onOpenDetails,
    );
  }

  testWidgets(
    'collapsed Past card stays button-sized and expands the old details',
    (tester) async {
      var reorders = 0;
      var details = 0;
      await pumpCard(
        tester,
        card: pastBreakfast(
          onReorder: () => reorders++,
          onOpenDetails: () => details++,
        ),
      );

      expect(find.text('695B9CD2'), findsOneWidget);
      expect(find.text('1x Breakfast'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('newchef16'), findsNothing);
      expect(find.text('₹100'), findsNothing);
      expect(find.textContaining('Delivery Slot:'), findsNothing);
      expect(find.textContaining('Dropoff:'), findsNothing);
      expect(find.textContaining('Delivery PIN: 8779'), findsNothing);
      expect(find.text('Reorder'), findsNothing);

      final collapsed = tester.getSize(find.byType(DinerOrderListCard));
      expect(
        collapsed.height,
        lessThanOrEqualTo(DinerOrderListCard.collapsedHeight + 12),
      );

      await tester.tap(find.byKey(DinerOrderListCard.toggleKey('695B9CD2')));
      await tester.pumpAndSettle();

      expect(find.text('newchef16'), findsOneWidget);
      expect(find.text('1x Breakfast'), findsWidgets);
      expect(find.text('Status: Cancelled'), findsOneWidget);
      expect(find.text('₹100'), findsOneWidget);
      expect(find.text('Delivery Partner'), findsOneWidget);
      expect(find.text('25 Sep 2026, 10:14 PM'), findsOneWidget);
      expect(find.text('26 Sep 2026, 09:00 AM'), findsOneWidget);
      expect(find.textContaining('Dropoff: 9, Thergaon'), findsOneWidget);
      expect(find.textContaining('Delivery PIN: 8779'), findsOneWidget);
      expect(find.text('Reorder'), findsOneWidget);
      expect(
        tester.getSize(find.byType(DinerOrderListCard)).height,
        greaterThan(collapsed.height),
      );

      await tester.tap(find.text('Reorder'));
      await tester.pump();
      expect(reorders, 1);
      expect(find.text('Reorder'), findsOneWidget);

      await tester.tap(find.text('Order details'));
      await tester.pump();
      expect(details, 1);

      await tester.tap(find.byKey(DinerOrderListCard.toggleKey('695B9CD2')));
      await tester.pumpAndSettle();

      expect(find.text('newchef16'), findsNothing);
      expect(find.text('Reorder'), findsNothing);
      expect(find.textContaining('Delivery PIN: 8779'), findsNothing);
      expect(
        tester.getSize(find.byType(DinerOrderListCard)).height,
        collapsed.height,
      );
    },
  );

  testWidgets(
    'the same card collapses an active order and keeps Track inside',
    (tester) async {
      var tracks = 0;
      await pumpCard(
        tester,
        card: DinerOrderListCard(
          orderIdLabel: '4D6B2765',
          chefName: 'newchef16',
          lineLabel: '1x Breakfast',
          badgeLabel: 'Confirmed',
          statusLine: 'Status: Confirmed',
          statusColor: Colors.green,
          priceLabel: '₹100',
          orderType: 'Delivery Partner',
          placedLabel: '03 Oct 2026, 12:27 PM',
          slotLabel: '04 Oct 2026, 08:00 AM',
          addressLabel: 'Dropoff: ',
          addressValue: 'Kitchen drop',
          isPickup: false,
          showTrack: true,
          onTrack: () => tracks++,
        ),
      );

      expect(find.text('Track Live Order'), findsNothing);
      expect(find.text('Reorder'), findsNothing);
      expect(
        tester.getSize(find.byType(DinerOrderListCard)).height,
        lessThanOrEqualTo(DinerOrderListCard.collapsedHeight + 12),
      );

      await tester.tap(find.byKey(DinerOrderListCard.toggleKey('4D6B2765')));
      await tester.pumpAndSettle();
      expect(find.text('Track Live Order'), findsOneWidget);
      expect(find.text('04 Oct 2026, 08:00 AM'), findsOneWidget);

      await tester.tap(find.text('Track Live Order'));
      await tester.pump();
      expect(tracks, 1);
      expect(find.text('Track Live Order'), findsOneWidget);
    },
  );
}
