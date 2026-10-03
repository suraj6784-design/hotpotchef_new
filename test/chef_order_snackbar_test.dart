import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/utils/in_app_alert.dart';
import 'package:hotpotchef_new/widgets/customer_ui_components.dart';

const _cancelled =
    'Order cancelled — The order for Veg Biryani was cancelled. A refund is issued if you paid online.';
const _tooEarly = 'Too early to start preparing. Opens 4 hours before the requested time.';

void main() {
  test('prep window is still 4 hours', () {
    expect(kChefPrepEarliestMinutes, 240);
  });

  test('chef order update keeps the server too-early sentence', () {
    final wrapped = Exception(
      'Failed to update order status to Preparing: '
      'PostgrestException(message: $_tooEarly, code: P0001, details: null, hint: null)',
    );
    expect(chefOrderUpdateMessage(wrapped), _tooEarly);
    expect(
      chefOrderUpdateMessage(Exception('Opens in 19 hr (4 hours before requested time)')),
      'Opens in 19 hr (4 hours before requested time)',
    );
    expect(
      chefOrderUpdateMessage(Exception('column delivered_at missing')),
      'Could not mark this order delivered. Try again.',
    );
    expect(
      chefOrderUpdateMessage(Exception('network down')),
      'Could not update this order. Try again.',
    );
  });

  test('the same cancellation is not queued twice', () {
    const title = 'Order cancelled';
    const body = 'The order for Veg Biryani was cancelled. A refund is issued if you paid online.';
    final shown = <String>{};
    expect(
      shouldPresentInAppAlert(shown: shown, id: 'order-1-cancelled', title: title, body: body),
      isTrue,
    );
    rememberInAppAlert(shown, id: 'order-1-cancelled', title: title, body: body);
    expect(
      shouldPresentInAppAlert(shown: shown, id: 'push-order-1', title: title, body: body),
      isFalse,
    );
    expect(inAppAlertSnackBar(message: _cancelled, onOpen: () {}).persist, isFalse);
  });

  testWidgets('a persistent Open banner hides the prepare error until it is replaced', (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              pageContext = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    final messenger = ScaffoldMessenger.of(pageContext);
    messenger.showSnackBar(
      SnackBar(
        content: const Text(_cancelled),
        action: SnackBarAction(label: 'Open', onPressed: () {}),
      ),
    );
    messenger.showSnackBar(const SnackBar(content: Text(_tooEarly)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 5));

    expect(find.text(_cancelled), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text(_tooEarly), findsNothing);

    showReplacingSnackBar(pageContext, _tooEarly, isError: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(_tooEarly), findsOneWidget);
    expect(find.text(_cancelled), findsNothing);
  });

  testWidgets('the chef cancellation banner does not stay stuck', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  inAppAlertSnackBar(message: _cancelled, onOpen: () {}),
                );
              },
              child: const Text('alert'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('alert'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_cancelled), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text(_cancelled), findsNothing);
  });
}
