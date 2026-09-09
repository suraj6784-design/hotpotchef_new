import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/meal_plans_provider.dart';
import '../utils/app_theme.dart';
import '../utils/meal_plans.dart';
import '../widgets/app_widgets.dart';
import '../widgets/weekly_plan_banner.dart';

class CustomerMealPlansScreen extends ConsumerWidget {
  const CustomerMealPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final plans = ref.watch(mealPlansProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const BrandMark(title: 'Weekly plans'),
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? AppTheme.textMainDark : AppTheme.textMain),
      ),
      body: plans.isEmpty
          ? const EmptyState(
              icon: Icons.event_repeat,
              title: 'No weekly plans yet',
              message: 'Open any dish and tap Weekly plan. We never auto-charge — you add today\'s box when you want it.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              itemCount: plans.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final plan = plans[index];
                return _PlanCard(plan: plan);
              },
            ),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan});

  final MealPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final due = plan.isDueToday;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: due ? AppTheme.primary.withValues(alpha: 0.45) : AppTheme.hairlineOf(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.mealTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : AppTheme.textMain,
                  ),
                ),
              ),
              if (due)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Due today',
                    style: TextStyle(color: AppTheme.link, fontWeight: FontWeight.w800, fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${plan.chefName} · ${plan.quantity} portion${plan.quantity == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 13, color: isDark ? AppTheme.textMuted : AppTheme.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            '${plan.daysLabel} · ${plan.timeSlot}',
            style: TextStyle(fontSize: 13, color: isDark ? AppTheme.textMuted : AppTheme.textMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (due)
                Expanded(
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
                )
              else
                Expanded(
                  child: Text(
                    'Next on ${plan.daysLabel}',
                    style: TextStyle(fontSize: 13, color: isDark ? AppTheme.textMuted : AppTheme.textMuted),
                  ),
                ),
              TextButton(
                onPressed: () async {
                  final ok = await ref.read(mealPlansProvider.notifier).pausePlan(plan.id);
                  if (!ok || !context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Paused ${plan.mealTitle}.')),
                  );
                },
                child: const Text('Pause'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
