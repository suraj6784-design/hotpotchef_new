// lib/widgets/group_order_modal.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/app_theme.dart';
import '../providers/cart_provider.dart';
import '../services/shared_cart_service.dart';

class GroupOrderModal extends ConsumerStatefulWidget {
  const GroupOrderModal({super.key});

  @override
  ConsumerState<GroupOrderModal> createState() => _GroupOrderModalState();
}

class _GroupOrderModalState extends ConsumerState<GroupOrderModal> {
  final _sharedCartService = SharedCartService();
  final _roomCodeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _roomCodeController.dispose();
    super.dispose();
  }

  Future<void> _startGroupOrder() async {
    setState(() => _isLoading = true);
    try {
      final cartState = ref.read(cartProvider);
      final roomCode = await _sharedCartService.createSharedCart(cartState.items);
      await ref.read(cartProvider.notifier).attachSharedRoom(roomCode);

      if (!mounted) return;
      Navigator.pop(context);
      _showRoomCodeDialog(roomCode);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to start group order');
      if (!mounted) return;
      _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinGroupOrder() async {
    final code = _roomCodeController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final items = await _sharedCartService.fetchSharedCart(code);

      if (!mounted) return;

      final cart = ref.read(cartProvider.notifier);
      var added = 0;
      final skipped = <String>[];
      var allowClear = true;
      for (final item in items) {
        final ok = cart.addToCart(
          item.toMealMap(),
          item.quantity,
          addOns: item.selectedAddOns,
          clearIfVendorConflict: allowClear,
        );
        if (ok) {
          added += 1;
          allowClear = false;
        } else {
          skipped.add(item.title.isEmpty ? 'a dish' : item.title);
        }
      }

      if (!mounted) return;
      Navigator.pop(context);
      if (added <= 0) {
        final names = skipped.isEmpty ? 'those meals' : skipped.join(', ');
        _showSnackBar('$names could not be added to your cart.', isError: true);
        return;
      }
      await ref.read(cartProvider.notifier).attachSharedRoom(code);
      final extra = skipped.isEmpty ? '' : ' Skipped: ${skipped.join(', ')}.';
      _showSnackBar('Joined $code. Later adds stay in sync.$extra', isError: false);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to join group order');
      if (!mounted) return;
      _showSnackBar('Invalid Room Code: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.orangeAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showRoomCodeDialog(String roomCode) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        title: Text(
          'Group Order Created! 🍕',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Share this room code with your family or colleagues so they can add items to your cart:',
              style: TextStyle(
                color: isDark ? Colors.grey.shade300 : AppTheme.textMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.orange.shade900.withValues(alpha: 0.3) : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.orange.shade700 : Colors.orange.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    roomCode,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.orange.shade200 : AppTheme.primary,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: Icon(Icons.copy, size: 20, color: isDark ? Colors.orange.shade200 : AppTheme.primary),
                    tooltip: 'Copy Room Code',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: roomCode));
                      _showSnackBar('Room code copied to clipboard!', isError: false);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Group Ordering (Shared Cart)',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Order together with colleagues or family in real-time.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade400 : AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.group_add),
            label: Text(
              _isLoading ? 'Processing...' : 'Start New Group Cart',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: _isLoading ? null : _startGroupOrder,
          ),
          Divider(height: 32, color: isDark ? Colors.white12 : Colors.grey.shade300),
          TextField(
            controller: _roomCodeController,
            style: TextStyle(color: isDark ? AppTheme.textMainDark : AppTheme.textMain),
            decoration: InputDecoration(
              labelText: 'Enter Room Code (e.g. GRP-XYZ)',
              filled: true,
              fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
              labelStyle: TextStyle(color: isDark ? Colors.grey.shade400 : AppTheme.textMuted, fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: AppTheme.primary, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isLoading ? null : _joinGroupOrder,
            child: const Text(
              'Join Group Cart',
              style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}