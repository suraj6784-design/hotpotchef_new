// lib/screens/chef_analytics_screen.dart

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/app_theme.dart';
import '../widgets/customer_ui_components.dart';

class DailyMetric {
  final String dayLabel;
  final DateTime date;
  final double amount;

  const DailyMetric({
    required this.dayLabel,
    required this.date,
    required this.amount,
  });
}

class TopDishMetric {
  final String title;
  final int totalPortions;
  final double totalEarned;

  const TopDishMetric({
    required this.title,
    required this.totalPortions,
    required this.totalEarned,
  });
}

class ChefAnalyticsScreen extends StatefulWidget {
  const ChefAnalyticsScreen({super.key});

  @override
  State<ChefAnalyticsScreen> createState() => _ChefAnalyticsScreenState();
}

class _ChefAnalyticsScreenState extends State<ChefAnalyticsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;

  double _totalRevenue = 0.0;
  int _completedOrdersCount = 0;
  List<DailyMetric> _dailyTrend = [];
  List<TopDishMetric> _topDishes = [];
  int _selectedDays = 7;

  @override
  void initState() {
    super.initState();
    _fetchChefAnalytics();
  }

  Future<void> _fetchChefAnalytics() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final cutoffDate = DateTime.now().subtract(Duration(days: _selectedDays));

      // 1. Fetch raw orders directly from the orders table
      final response = await _supabase
          .from('orders')
          .select()
          .eq('chef_id', user.id)
          .gte('created_at', cutoffDate.toIso8601String());

      final orders = List<Map<String, dynamic>>.from(response);

      double totalRev = 0.0;
      int completedCount = 0;
      Map<String, double> dailyMap = {};
      Map<String, int> dishVol = {};
      Map<String, double> dishRev = {};

      // 2. Pre-fill the daily map with 0.0 to ensure continuous chart rendering
      for (int i = _selectedDays - 1; i >= 0; i--) {
        final d = DateTime.now().subtract(Duration(days: i));
        final key = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
        dailyMap[key] = 0.0;
      }

      // 3. Aggregate data from JSON items
      for (var order in orders) {
        final status = (order['status']?.toString() ?? '').toLowerCase();
        if (status != 'delivered' && status != 'completed') continue;

        completedCount++;

        final createdAt = DateTime.parse(order['created_at'].toString()).toLocal();
        final dateKey = "${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}";

        // Handle both stringified JSON and native lists safely
        final rawItems = order['items'] ?? order['cart_items'];
        List<dynamic> items = [];
        if (rawItems is List) {
          items = rawItems;
        } else if (rawItems is String && rawItems.isNotEmpty) {
          try {
            items = jsonDecode(rawItems);
          } catch (_) {}
        }

        double orderRev = 0.0;

        for (var item in items) {
          if (item is Map) {
            final title = item['title']?.toString() ?? item['name']?.toString() ?? 'Dish';
            final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
            
            // Safely parse pricing, falling back across known variations
            final priceStr = item['discountedPrice']?.toString() ?? 
                             item['basePrice']?.toString() ?? 
                             item['price']?.toString() ?? '0';
            final price = double.tryParse(priceStr) ?? 0.0;
            
            final itemTotal = price * qty;
            orderRev += itemTotal;

            dishVol[title] = (dishVol[title] ?? 0) + qty;
            dishRev[title] = (dishRev[title] ?? 0.0) + itemTotal;
          }
        }

        // Failsafe: if items lacked pricing data, fallback to the gross order total
        if (orderRev == 0.0) {
          orderRev = double.tryParse(order['total_amount']?.toString() ?? order['total_price']?.toString() ?? '0') ?? 0.0;
        }

        totalRev += orderRev;
        if (dailyMap.containsKey(dateKey)) {
          dailyMap[dateKey] = dailyMap[dateKey]! + orderRev;
        }
      }

      // 4. Map trend data for FlChart
      final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final List<DailyMetric> trendList = dailyMap.entries.map((e) {
        final dateParts = e.key.split('-');
        final d = DateTime(int.parse(dateParts[0]), int.parse(dateParts[1]), int.parse(dateParts[2]));
        final label = weekdays[d.weekday - 1];
        return DailyMetric(dayLabel: label, date: d, amount: e.value);
      }).toList();

      // 5. Map top dishes
      final List<TopDishMetric> dishesList = dishVol.entries.map((e) {
        return TopDishMetric(
          title: e.key,
          totalPortions: e.value,
          totalEarned: dishRev[e.key] ?? 0.0,
        );
      }).toList();

      dishesList.sort((a, b) => b.totalPortions.compareTo(a.totalPortions));
      final topDishes = dishesList.take(10).toList(); // Take Top 10

      if (mounted) {
        setState(() {
          _totalRevenue = totalRev;
          _completedOrdersCount = completedCount;
          _dailyTrend = trendList;
          _topDishes = topDishes;
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chef analytics fetch error');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load analytics: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  double get _maxChartY {
    if (_dailyTrend.isEmpty) return 1000.0;
    final highest = _dailyTrend.map((e) => e.amount).reduce(max);
    return highest > 0 ? (highest * 1.25) : 1000.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          'Chef Earnings & Analytics',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMain),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.calendar_today, color: AppTheme.textMain, size: 20),
            onSelected: (days) {
              setState(() {
                _selectedDays = days;
                _isLoading = true;
              });
              _fetchChefAnalytics();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 7, child: Text('Last 7 Days')),
              const PopupMenuItem(value: 14, child: Text('Last 14 Days')),
              const PopupMenuItem(value: 30, child: Text('Last 30 Days')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _fetchChefAnalytics,
              color: AppTheme.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // KPI Cards
                  Row(
                    children: [
                      Expanded(
                        child: AppCard(
                          margin: EdgeInsets.zero,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Net Earnings',
                                style: TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '₹${_totalRevenue.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppCard(
                          margin: EdgeInsets.zero,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Delivered Orders',
                                style: TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$_completedOrdersCount',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Trend Bar Chart
                  AppCard(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Revenue Trend ($_selectedDays Days)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppTheme.textMain,
                              ),
                            ),
                            const Text(
                              'Amounts in ₹',
                              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 220,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: _maxChartY,
                              barTouchData: BarTouchData(
                                touchTooltipData: BarTouchTooltipData(
                                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                    final item = _dailyTrend[group.x.toInt()];
                                    return BarTooltipItem(
                                      '${item.dayLabel}\n₹${rod.toY.toStringAsFixed(2)}',
                                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    );
                                  },
                                ),
                              ),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (val, meta) {
                                      final idx = val.toInt();
                                      if (idx >= 0 && idx < _dailyTrend.length) {
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Text(
                                            _dailyTrend[idx].dayLabel,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                ),
                                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              gridData: const FlGridData(show: false),
                              borderData: FlBorderData(show: false),
                              barGroups: _dailyTrend.asMap().entries.map((entry) {
                                final index = entry.key;
                                final item = entry.value;

                                return BarChartGroupData(
                                  x: index,
                                  barRods: [
                                    BarChartRodData(
                                      toY: item.amount,
                                      color: item.amount > 0 ? AppTheme.primary : Colors.grey.shade300,
                                      width: _selectedDays > 14 ? 8 : 14,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Top Performing Dishes
                  AppCard(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Top Dishes by Volume',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_topDishes.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'No completed order history yet.',
                                style: TextStyle(color: AppTheme.textMuted),
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _topDishes.length,
                            separatorBuilder: (_, _) => const Divider(height: 16),
                            itemBuilder: (context, index) {
                              final dish = _topDishes[index];
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                                  child: Text(
                                    '#${index + 1}',
                                    style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  dish.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                subtitle: Text(
                                  'Earned ₹${dish.totalEarned.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                                trailing: Text(
                                  '${dish.totalPortions} Sold',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}