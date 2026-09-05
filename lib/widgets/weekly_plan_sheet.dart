import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/meal_plans_provider.dart';
import '../screens/auth_screen.dart';
import '../utils/app_theme.dart';
import '../utils/meal_plans.dart';

Future<void> showWeeklyPlanSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> meal,
  int quantity = 1,
}) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) {
    final signedIn = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => const AuthScreen(
        asSheet: true,
        sheetTitle: 'Sign in to save a weekly plan',
        sheetSubtitle: 'We will not charge you. You add today\'s box when you want it.',
      ),
    );
    if (signedIn == true) {
      await ref.read(mealPlansProvider.notifier).fetchPlans();
    }
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: WeeklyPlanSheet(meal: meal, quantity: quantity),
    ),
  );
}

class WeeklyPlanSheet extends ConsumerStatefulWidget {
  const WeeklyPlanSheet({
    super.key,
    required this.meal,
    this.quantity = 1,
  });

  final Map<String, dynamic> meal;
  final int quantity;

  @override
  ConsumerState<WeeklyPlanSheet> createState() => _WeeklyPlanSheetState();
}

class _WeeklyPlanSheetState extends ConsumerState<WeeklyPlanSheet> {
  late Set<int> _days;
  late int _quantity;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final mealId = widget.meal['id']?.toString() ?? '';
    final existing = activePlanForMeal(ref.read(mealPlansProvider), mealId);
    _days = {
      ...(existing?.weekdays ?? kWeekdaysMonToFri),
    };
    _quantity = existing?.quantity ?? (widget.quantity < 1 ? 1 : widget.quantity);
  }

  Future<void> _save() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _days.isEmpty || _saving) return;

    setState(() => _saving = true);
    final draft = mealPlanDraftFromMeal(
      widget.meal,
      customerId: user.id,
      quantity: _quantity,
      weekdays: _days.toList()..sort(),
    );
    final ok = await ref.read(mealPlansProvider.notifier).savePlan(draft);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save this plan. Try again.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved ${draft.mealTitle} for ${draft.daysLabel}.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mealId = widget.meal['id']?.toString() ?? '';
    final existing = activePlanForMeal(ref.watch(mealPlansProvider), mealId);
    final title = widget.meal['title']?.toString() ?? widget.meal['name']?.toString() ?? 'Home meal';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            existing == null ? 'Weekly plan' : 'Update weekly plan',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We will not charge you automatically. On plan days, add today\'s box from Home when you want it.',
            style: TextStyle(fontSize: 13, height: 1.4, color: isDark ? Colors.grey.shade400 : AppTheme.textMuted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _presetChip('Mon–Fri', kWeekdaysMonToFri),
              _presetChip('Weekends', const [6, 7]),
              _presetChip('Every day', kWeekdaysMonToSun),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final day in kWeekdaysMonToSun)
                FilterChip(
                  label: Text(kWeekdayShort[day] ?? '$day'),
                  selected: _days.contains(day),
                  selectedColor: AppTheme.primary.withValues(alpha: 0.18),
                  checkmarkColor: AppTheme.primary,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _days.add(day);
                      } else {
                        _days.remove(day);
                      }
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Portions',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppTheme.textMain,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                icon: const Icon(Icons.remove_circle_outline, color: AppTheme.primary),
              ),
              Text(
                '$_quantity',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : AppTheme.textMain,
                ),
              ),
              IconButton(
                onPressed: _quantity < 20 ? () => setState(() => _quantity++) : null,
                icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              onPressed: _days.isEmpty || _saving ? null : _save,
              child: Text(
                _saving
                    ? 'Saving…'
                    : existing == null
                        ? 'Save weekly plan'
                        : 'Update weekly plan',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, List<int> days) {
    final selected = _days.length == days.length && days.every(_days.contains);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppTheme.primary.withValues(alpha: 0.18),
      onSelected: (_) => setState(() => _days = {...days}),
    );
  }
}
