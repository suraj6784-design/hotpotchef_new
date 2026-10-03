import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import '../utils/network.dart';

Future<void> submitMealReview({
  required Map<String, dynamic> item,
  required String customerId,
  String? chefId,
  String? orderId,
  required int rating,
  required String comment,
}) async {
  final mealId = mealIdFromOrderItem(item) ?? item['id']?.toString();
  final resolvedOrder = (orderId ?? '').trim();
  if (mealId == null || mealId.isEmpty) {
    throw Exception('This plate cannot be rated.');
  }
  if (resolvedOrder.isEmpty) {
    throw Exception('Rate this plate from the order it was delivered on.');
  }
  final row = <String, dynamic>{
    'meal_id': mealId,
    'customer_id': customerId,
    'chef_id': chefId ?? item['chef_id'],
    'rating': rating,
    'comment': comment,
    'order_id': resolvedOrder,
  };
  try {
    await Supabase.instance.client.from('reviews').upsert(
          row,
          onConflict: 'customer_id,order_id,meal_id',
        );
  } on PostgrestException catch (e) {
    if (e.code == '23505') return;
    try {
      await Supabase.instance.client.from('reviews').insert(row);
    } on PostgrestException catch (insertError) {
      if (insertError.code == '23505') return;
      throw Exception(networkErrorMessage(insertError));
    }
  }
}

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
  int _rating = 0;
  bool _submitting = false;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _rating < 1) return;
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
    final muted = AppTheme.textMuted;

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
            'Tap a star to send. A note is optional.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            maxLines: 2,
            enabled: !_submitting,
            style: TextStyle(color: titleColor),
            decoration: InputDecoration(
              labelText: 'Leave a review (optional)',
              labelStyle: TextStyle(color: muted),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
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
                    : () {
                        setState(() => _rating = index + 1);
                        _submit();
                      },
              );
            }),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: Text('Skip', style: TextStyle(color: muted)),
        ),
        if (_submitting)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
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
    this.orderId,
  });

  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic> item) onRate;
  final String? orderId;

  @override
  Widget build(BuildContext context) {
    final meals = uniqueReviewableOrderItems(items);
    final ids = meals
        .map(mealIdFromOrderItem)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    final orderKey = (orderId ?? '').trim();
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ids.isEmpty || uid.isEmpty || orderKey.isEmpty
          ? Future.value(const [])
          : Supabase.instance.client
              .from('reviews')
              .select('meal_id, rating, order_id')
              .eq('customer_id', uid)
              .eq('order_id', orderKey)
              .inFilter('meal_id', ids)
              .then((rows) => List<Map<String, dynamic>>.from(rows as List)),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox();
        }
        final rated = reviewsForOrderMeals(rows: snap.data ?? const [], orderId: orderKey);
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
