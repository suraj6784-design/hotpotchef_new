// lib/widgets/ai_recommendations_section.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/app_theme.dart';
import '../utils/helpers.dart';
import '../widgets/customer_ui_components.dart';

class AiRecommendationsSection extends ConsumerStatefulWidget {
  const AiRecommendationsSection({super.key});

  @override
  ConsumerState<AiRecommendationsSection> createState() => _AiRecommendationsSectionState();
}

class _AiRecommendationsSectionState extends ConsumerState<AiRecommendationsSection> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _recommendedMeals = [];
  String _favoriteCategory = 'Maharashtrian';

  @override
  void initState() {
    super.initState();
    _fetchSmartRecommendations();
  }

  Future<void> _fetchSmartRecommendations() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final email = user.email ?? '';
      final pastOrders = await _supabase
          .from('meals')
          .select('category, title')
          .eq('customer_name', email);

      if (!mounted) return;

      Map<String, int> categoryCounts = {};
      for (var order in pastOrders) {
        String cat = order['category']?.toString() ?? 'Maharashtrian';
        categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
      }

      if (categoryCounts.isNotEmpty) {
        _favoriteCategory = categoryCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      }

      final mealsResponse = await _supabase
          .from('meals')
          .select()
          .ilike('category', '%$_favoriteCategory%')
          .limit(5);

      if (!mounted) return;

      final validMeals = List<Map<String, dynamic>>.from(mealsResponse).where((m) {
        final status = m['status']?.toString().toLowerCase() ?? '';
        final isInventory = (m['customer_name'] == null || m['customer_name'].toString().isEmpty);
        return isInventory && status != 'paused' && status != 'cancelled';
      }).toList();

      if (mounted) {
        setState(() {
          _recommendedMeals = validMeals;
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch smart recommendations');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _recommendedMeals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Because you like $_favoriteCategory',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.onSurfaceOf(context)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recommendedMeals.length,
            itemBuilder: (context, index) {
              final meal = _recommendedMeals[index];
              final double price = (meal['price'] as num?)?.toDouble() ?? 0.0;
              final imageUrl = meal['image_url']?.toString();

              return GestureDetector(
                onTap: () => showMealDetailsDialog(context, meal, ref),
                child: Container(
                  width: 160,
                  margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 110,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          color: Colors.grey.shade200,
                          image: imageUrl != null && imageUrl.isNotEmpty
                              ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
                              : null,
                        ),
                        child: (imageUrl == null || imageUrl.isEmpty)
                            ? const Icon(Icons.restaurant, color: Colors.grey)
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              meal['title']?.toString() ?? 'Meal',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textMain),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              chefDisplayName(meal),
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('₹${price.toStringAsFixed(0)}',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppTheme.primary)),
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add, color: AppTheme.primary, size: 14),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}