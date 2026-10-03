import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/widgets/customer_ui_components.dart';

void main() {
  group('checkoutContactPhoneError', () {
    test('blocks the dummy number shown on the test diner account', () {
      expect(
        checkoutContactPhoneError('1234567890'),
        'Enter the mobile number we can reach you on',
      );
      expect(checkoutContactPhoneError('9876543210'), isNull);
      expect(checkoutContactPhoneError('+91 98765 43210'), isNull);
    });
  });

  testWidgets('an order-cancelled alert with Open stays and hides a queued pay error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(
                  SnackBar(
                    content: const Text('Order cancelled — Veg Biryani'),
                    action: SnackBarAction(label: 'Open', onPressed: () {}),
                  ),
                );
                messenger.showSnackBar(
                  const SnackBar(content: Text('Enter the mobile number we can reach you on')),
                );
              },
              child: const Text('queue'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('queue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Order cancelled — Veg Biryani'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Enter the mobile number we can reach you on'), findsNothing);
  });

  testWidgets('checkout pay error replaces a persistent order-cancelled alert', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Order cancelled — The order for Veg Biryani was cancelled.',
                        ),
                        behavior: SnackBarBehavior.floating,
                        action: SnackBarAction(label: 'Open', onPressed: () {}),
                      ),
                    );
                  },
                  child: const Text('alert'),
                ),
                TextButton(
                  onPressed: () => showCheckoutSnackBar(
                    context,
                    'Enter the mobile number we can reach you on',
                    isError: true,
                  ),
                  child: const Text('pay'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('alert'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Order cancelled'), findsOneWidget);

    await tester.tap(find.text('pay'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Enter the mobile number we can reach you on'), findsOneWidget);
    expect(find.textContaining('Order cancelled'), findsNothing);
  });
}
