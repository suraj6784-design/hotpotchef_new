import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/cart_provider.dart';
import '../providers/meal_plans_provider.dart';
import '../utils/app_theme.dart';
import '../utils/meal_plans.dart';
import 'customer_ui_components.dart';

Future<bool> addPlanToCart({
  required BuildContext context,
  required WidgetRef ref,
  required MealPlan plan,
}) async {
  final meal = await ref.read(mealPlansProvider.notifier).resolveMeal(plan);
  if (!context.mounted) return false;
  return addMealToCartWithConflict(
    context: context,
    ref: ref,
    meal: meal,
    quantity: plan.quantity,
  );
}

class WeeklyPlanDueBanner extends ConsumerWidget {
  const WeeklyPlanDueBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    final due = duePlansMissingFromCart(
      ref.watch(mealPlansProvider),
      ref.watch(cartProvider).items.map((item) => item.mealId),
    );
    if (due.isEmpty) return const SizedBox.shrink();

    final plan = due.first;
    final extra = due.length - 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
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
            'Today\'s tiffin',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isDark ? AppTheme.textMuted : AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            plan.mealTitle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${plan.quantity} × ${plan.chefName} · ${plan.timeSlot}',
            style: TextStyle(fontSize: 13, color: isDark ? AppTheme.textMuted : AppTheme.textMuted),
          ),
          if (extra > 0) ...[
            const SizedBox(height: 4),
            Text(
              '+$extra more plan${extra == 1 ? '' : 's'} due today',
              style: TextStyle(fontSize: 12, color: isDark ? AppTheme.textMuted : AppTheme.textMuted),
            ),
          ],
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
                final added = await addPlanToCart(context: context, ref: ref, plan: plan);
                if (!added || !context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added ${plan.quantity} × ${plan.mealTitle} to cart.'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Add today\'s box', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.push('/customer-plans'),
              child: const Text('Manage plans'),
            ),
          ),
        ],
      ),
    );
  }
}
