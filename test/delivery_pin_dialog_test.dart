import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/widgets/delivery_pin_dialog.dart';

/// Order 4D6B2765 delivery PIN. It must be entered, never printed on the dialog.
const _pin = '8784';

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool? openedCamera;

  void rebuild() => setState(() {});

  Future<void> confirm() async {
    final ok = await promptDeliveryPinAndDoorPhoto(
      context: context,
      expectedPin: _pin,
    );
    if (!mounted) return;
    setState(() => openedCamera = ok);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text('camera:${openedCamera ?? 'pending'}'),
          ElevatedButton(
            onPressed: confirm,
            child: const Text('Mark Delivered'),
          ),
        ],
      ),
    );
  }
}

Future<void> _openPinSheet(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: _Host()));
  await tester.tap(find.text('Mark Delivered'));
  await tester.pumpAndSettle();
  expect(find.text('Enter delivery PIN'), findsOneWidget);
  expect(find.text(_pin), findsNothing);
  final field = tester.widget<TextField>(find.byType(TextField));
  expect(field.obscureText, isTrue);
}

void main() {
  testWidgets(
    'correct PIN confirm opens the door photo without disposing the field early',
    (tester) async {
      await _openPinSheet(tester);
      final host = tester.state<_HostState>(find.byType(_Host));

      await tester.enterText(find.byType(TextField), _pin);
      // Rebuild the parent in the same turn as Confirm, the way a GPS fix
      // notifies the hub while the PIN route is still exiting.
      await tester.tap(find.text('Confirm'));
      host.rebuild();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.text('Door photo'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Door photo'), findsOneWidget);
      expect(find.text('Enter delivery PIN'), findsNothing);
      expect(find.text(_pin), findsNothing);

      await tester.tap(find.text('Open camera'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('camera:true'), findsOneWidget);
      expect(find.text('Door photo'), findsNothing);
    },
  );

  testWidgets('wrong PIN stays on the sheet and does not open the door photo', (
    tester,
  ) async {
    await _openPinSheet(tester);

    await tester.enterText(find.byType(TextField), '0000');
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Enter delivery PIN'), findsOneWidget);
    expect(
      find.text('PIN does not match. Ask the customer for the delivery PIN.'),
      findsOneWidget,
    );
    expect(find.text('Door photo'), findsNothing);
    expect(find.text('camera:pending'), findsOneWidget);
    expect(find.text(_pin), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel closes the PIN sheet and skips the door photo', (
    tester,
  ) async {
    await _openPinSheet(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Enter delivery PIN'), findsNothing);
    expect(find.text('Door photo'), findsNothing);
    expect(find.text('camera:false'), findsOneWidget);
  });
}
