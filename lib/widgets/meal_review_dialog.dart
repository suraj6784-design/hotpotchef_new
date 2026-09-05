import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';

/// Theme-following meal review sheet. Returns `true` when a review is submitted.
class MealReviewDialog extends StatefulWidget {
  const MealReviewDialog({
    super.key,
    required this.mealTitle,
    required this.onSubmit,
  });

  final String mealTitle;
  final Future<void> Function(int rating, String comment) onSubmit;

  @override
  State<MealReviewDialog> createState() => _MealReviewDialogState();
}

class _MealReviewDialogState extends State<MealReviewDialog> {
  int _rating = 5;
  bool _submitting = false;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(_rating, _comment.text.trim());
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppTheme.textMainDark : AppTheme.textMain;
    final muted = isDark ? Colors.grey.shade300 : AppTheme.textMuted;

    return AlertDialog(
      backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Rate ${widget.mealTitle}',
        style: TextStyle(color: titleColor, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'How was the food from this home kitchen?',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              return IconButton(
                icon: Icon(
                  index < _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 32,
                ),
                onPressed: _submitting
                    ? null
                    : () => setState(() => _rating = index + 1),
              );
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _comment,
            maxLines: 3,
            enabled: !_submitting,
            style: TextStyle(color: titleColor),
            decoration: InputDecoration(
              labelText: 'Leave a review (optional)',
              labelStyle: TextStyle(color: muted),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: Text('Skip', style: TextStyle(color: muted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }
}

class OrderItemReviewButtons extends StatelessWidget {
  const OrderItemReviewButtons({
    super.key,
    required this.items,
    required this.onRate,
  });

  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic> item) onRate;

  @override
  Widget build(BuildContext context) {
    final meals = uniqueReviewableOrderItems(items);
    final ids = meals
        .map(mealIdFromOrderItem)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ids.isEmpty || uid.isEmpty
          ? Future.value(const [])
          : Supabase.instance.client
              .from('reviews')
              .select('meal_id, rating')
              .eq('customer_id', uid)
              .inFilter('meal_id', ids)
              .then((rows) => List<Map<String, dynamic>>.from(rows as List)),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox();
        }
        final rated = <String, Map<String, dynamic>>{
          for (final row in snap.data ?? const <Map<String, dynamic>>[])
            if ((row['meal_id']?.toString() ?? '').isNotEmpty) row['meal_id'].toString(): row,
        };
        return Column(
          children: [
            for (final item in meals)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _button(context, item, rated[mealIdFromOrderItem(item) ?? '']),
              ),
          ],
        );
      },
    );
  }

  Widget _button(
    BuildContext context,
    Map<String, dynamic> item,
    Map<String, dynamic>? existing,
  ) {
    final title = item['title']?.toString() ?? item['name']?.toString() ?? 'this meal';
    if (existing != null) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.star, size: 18),
        label: Text('Rated ${existing['rating']}/5 · $title'),
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You have already rated $title.')),
        ),
      );
    }
    return OutlinedButton.icon(
      icon: const Icon(Icons.star_border, size: 18),
      label: Text('Rate $title'),
      onPressed: () => onRate(item),
    );
  }
}
