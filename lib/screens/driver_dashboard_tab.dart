// lib/screens/driver_dashboard_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/driver_dashboard_provider.dart';
import '../models/driver_delivery_model.dart';
import '../utils/helpers.dart';
import '../utils/app_theme.dart';

class DriverDashboardTab extends ConsumerStatefulWidget {
  final VoidCallback onProfileTap;
  final VoidCallback onLogout;

  const DriverDashboardTab({
    super.key,
    required this.onProfileTap,
    required this.onLogout,
  });

  @override
  ConsumerState<DriverDashboardTab> createState() => _DriverDashboardTabState();
}

class _DriverDashboardTabState extends ConsumerState<DriverDashboardTab>
    with AutomaticKeepAliveClientMixin {
  String _selectedTimeRange = 'This Week'; // Options: 'Today', 'This Week', 'This Month', 'All Time'

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(driverDashboardProvider);
    final notifier = ref.read(driverDashboardProvider.notifier);

    // Filter deliveries based on the selected time range
    final now = DateTime.now();
    final filteredDeliveries = state.recentDeliveries.where((delivery) {
      final orderDate = delivery.createdAt;
      if (_selectedTimeRange == 'Today') {
        return orderDate.year == now.year && orderDate.month == now.month && orderDate.day == now.day;
      } else if (_selectedTimeRange == 'This Week') {
        return now.difference(orderDate).inDays <= 7;
      } else if (_selectedTimeRange == 'This Month') {
        return orderDate.year == now.year && orderDate.month == now.month;
      }
      return true; // All Time
    }).toList();

    final filteredEarnings = filteredDeliveries.fold(0.0, (sum, d) => sum + d.payout);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Driver Dashboard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            onPressed: widget.onProfileTap,
            tooltip: 'Profile',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: widget.onLogout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: () => notifier.loadDashboardData(),
              color: AppTheme.primary,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Top Overview Banner with Time Range Selector Dropdown
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryGradientEnd],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Fleet Earnings',
                              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: DropdownButton<String>(
                                value: _selectedTimeRange,
                                underline: const SizedBox(),
                                isDense: true,
                                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
                                items: ['Today', 'This Week', 'This Month', 'All Time']
                                    .map((range) => DropdownMenuItem(value: range, child: Text(range)))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedTimeRange = val);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '₹${filteredEarnings.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${filteredDeliveries.length} Successful Deliveries in $_selectedTimeRange',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Quick Stats Grid
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Icon(Icons.bolt, color: AppTheme.primary),
                              SizedBox(height: 8),
                              Text('Active Runs', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              SizedBox(height: 4),
                              Text('Live Sync', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Icon(Icons.verified, color: Colors.green),
                              SizedBox(height: 8),
                              Text('Status', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              SizedBox(height: 4),
                              Text('Verified Partner', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'Recent Deliveries ($_selectedTimeRange)',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                  ),
                  const SizedBox(height: 12),

                  if (filteredDeliveries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text('No completed deliveries found for this timeframe.', style: TextStyle(color: AppTheme.textMuted)),
                      ),
                    )
                  else
                    ...filteredDeliveries.map((delivery) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const CircleAvatar(
                                    backgroundColor: Colors.green,
                                    radius: 16,
                                    child: Icon(Icons.check, color: Colors.white, size: 16),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(delivery.chefName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(height: 2),
                                      Text(formatOrderDate(delivery.createdAt.toIso8601String()),
                                          style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                    ],
                                  ),
                                ],
                              ),
                              Text(
                                '+₹${delivery.payout.toStringAsFixed(0)}',
                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 15),
                              ),
                            ],
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}