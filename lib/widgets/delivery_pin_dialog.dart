import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/helpers.dart';

/// Asks for the diner PIN, then for the door photo.
///
/// True only when the PIN matches and the partner chooses to open the camera.
/// The PIN field's controller is owned by the dialog route. [showDialog]
/// completes when the route is popped, while the exit animation still has the
/// field mounted. Disposing the controller at that moment rebuilds the field
/// against a disposed listenable and deactivates an inherited widget that
/// still has dependents (`_dependents.isEmpty`).
Future<bool> promptDeliveryPinAndDoorPhoto({
  required BuildContext context,
  required String expectedPin,
}) async {
  final matched = await showDialog<bool>(
    context: context,
    builder: (ctx) => DeliveryPinDialog(expectedPin: expectedPin),
  );
  if (matched != true || !context.mounted) return false;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: AppTheme.dialogShape,
      title: const Text('Door photo'),
      content: const Text(
        'Take a timestamped photo at the door. Ops uses this with the PIN if a refund is raised.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Open camera'),
        ),
      ],
    ),
  );
  return proceed == true;
}

/// Password field for the 4-digit delivery PIN. The expected PIN is not shown.
class DeliveryPinDialog extends StatefulWidget {
  const DeliveryPinDialog({super.key, required this.expectedPin});

  final String expectedPin;

  @override
  State<DeliveryPinDialog> createState() => _DeliveryPinDialogState();
}

class _DeliveryPinDialogState extends State<DeliveryPinDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!deliveryOtpMatches(widget.expectedPin, _controller.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'PIN does not match. Ask the customer for the delivery PIN.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: AppTheme.dialogShape,
      title: const Text('Enter delivery PIN'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        obscureText: true,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: '4-digit PIN from customer',
          counterText: '',
        ),
        onSubmitted: (_) {
          final ok = deliveryOtpMatches(widget.expectedPin, _controller.text);
          Navigator.pop(context, ok);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _confirm, child: const Text('Confirm')),
      ],
    );
  }
}
