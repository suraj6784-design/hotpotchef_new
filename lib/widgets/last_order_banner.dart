import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/cart_provider.dart';
import '../providers/last_order_provider.dart';
import '../services/reorder_service.dart';
import '../utils/helpers.dart';

Future<ReorderResult> reorderOrderItems({
  required WidgetRef ref,
  required List<Map<String, dynamic>> items,
}) {
  return ReorderService.addOrderItemsToCart(
    cart: ref.read(cartProvider.notifier),
    items: items,
  );
}

class LastOrderReorderBanner extends ConsumerWidget {
  const LastOrderReorderBanner({
    super.key,
    this.onAddedToCart,
    this.compact = false,
  });

  final VoidCallback? onAddedToCart;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    final order = ref.watch(lastOrderProvider);
    final items = orderItemsForReorder(order);
    if (order == null || items.isEmpty) return const SizedBox.shrink();

    final alreadyInCart = orderItemsAlreadyInCart(
      items,
      ref.watch(cartProvider).items.map((item) => item.mealId),
    );
    if (alreadyInCart) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placed = DateTime.tryParse(order['created_at']?.toString() ?? '');
    final label = sameAsLastLabel(placed);
    final summary = reorderMealSummary(items);
    final chef = chefDisplayName({...order, ...items.first});

    return Container(
      margin: compact
          ? const EdgeInsets.only(bottom: 16)
          : const EdgeInsets.fromLTRB(20, 4, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.grey.shade400 : AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            chef,
            style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade400 : AppTheme.textMuted),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final result = await reorderOrderItems(ref: ref, items: items);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ReorderService.resultMessage(result))),
                );
                if (result.added > 0) onAddedToCart?.call();
              },
              child: const Text('Order again', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
