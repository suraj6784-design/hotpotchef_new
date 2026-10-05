import 'package:flutter/material.dart';

/// Red past-slot line under a plate or a group room. Hidden when [message] is empty.
class CartSlotIssueNotice extends StatelessWidget {
  const CartSlotIssueNotice({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w600),
      ),
    );
  }
}
