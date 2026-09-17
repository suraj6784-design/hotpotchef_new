import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/widgets/customer_ui_components.dart';

void main() {
  testWidgets('guest order login opens as a sheet over the current screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const Text('Cart • 2 items'),
                ElevatedButton(
                  onPressed: () => showAuthBottomSheet(
                    context,
                    () {},
                    title: 'Sign in to order',
                    subtitle: 'Your cart is still here. Sign in to continue checkout.',
                  ),
                  child: const Text('Sign in to order'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Sign in to order'));
    await tester.pumpAndSettle();

    expect(find.text('Cart • 2 items'), findsOneWidget);
    expect(find.text('Sign in to order'), findsWidgets);
    expect(find.text('Your cart is still here. Sign in to continue checkout.'), findsOneWidget);
    expect(find.text('Keep my cart and go back'), findsOneWidget);
  });
}
