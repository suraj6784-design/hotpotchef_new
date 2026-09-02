// lib/screens/driver_hub.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../utils/helpers.dart';
import '../widgets/customer_ui_components.dart';
import '../widgets/app_widgets.dart';
import '../widgets/app_status_badge.dart';
import '../providers/driver_dashboard_provider.dart';
import '../models/driver_delivery_model.dart';
import '../services/auth_session.dart';
import 'driver_profile_screen.dart';

class DriverHubScreen extends ConsumerStatefulWidget {
  const DriverHubScreen({super.key});

  @override
  ConsumerState<DriverHubScreen> createState() => _DriverHubScreenState();
}

class _DriverHubScreenState extends ConsumerState<DriverHubScreen> {
  int _selectedIndex = 0;
  bool _isOnline = true;

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(driverDashboardProvider);
    final notifier = ref.read(driverDashboardProvider.notifier);

    final List<Widget> pages = [
      _buildDashboardTab(dashboardState),
      _buildAvailableTab(dashboardState.availableDeliveries, notifier),
      _buildActiveDeliveryTab(dashboardState.activeDeliveries, notifier),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Exit App'),
            content: const Text('Are you sure you want to exit?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Exit'),
              ),
            ],
          ),
        );

        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Column(
          children: [
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 24,
                right: 24,
                bottom: 24,
              ),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
                boxShadow: AppTheme.brandGlow(opacity: 0.28),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Delivery Partner',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () {
                          setState(() => _isOnline = !_isOnline);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_isOnline ? '🟢 Online • Receiving Dispatches' : '🔴 Offline'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white54),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _isOnline
                                  ? const Icon(Icons.circle, color: Colors.greenAccent, size: 10)
                                      .animate(onPlay: (c) => c.repeat(reverse: true))
                                      .fade(begin: 0.35, end: 1, duration: 900.ms)
                                  : const Icon(Icons.circle, color: Colors.redAccent, size: 10),
                              const SizedBox(width: 6),
                              Text(
                                _isOnline ? 'Online • Live Feed' : 'Offline',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const DriverProfileScreen()),
                          );
                        },
                        child: const CircleAvatar(
                          backgroundColor: Colors.white,
                          radius: 20,
                          child: Icon(Icons.person, color: AppTheme.primary, size: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => AuthSession.logout(context),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                          child: const Icon(Icons.logout, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(child: pages[_selectedIndex]),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard, color: AppTheme.primary),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.list_alt_outlined),
              selectedIcon: Icon(Icons.list_alt, color: AppTheme.primary),
              label: 'Available',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map, color: AppTheme.primary),
              label: 'Active',
            ),
          ],
        ),
      ),
    );
  }

  // --- Sub-Tabs ---

  Widget _buildDashboardTab(DriverDashboardState state) {
    return RefreshIndicator(
      onRefresh: () => ref.read(driverDashboardProvider.notifier).loadDashboardData(),
      color: AppTheme.primary,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: AppTheme.radiusLg,
              boxShadow: AppTheme.brandGlow(opacity: 0.3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Fleet Earnings',
                    style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('₹${state.totalEarnings.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${state.completedCount} Successful Deliveries',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const Text('Payout: Weekly',
                        style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.local_shipping, color: AppTheme.primary, size: 24),
                      const SizedBox(height: 12),
                      Text('${state.activeDeliveries.length}',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                      const SizedBox(height: 4),
                      const Text('Active Runs', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.inventory_2_outlined, color: Colors.blue, size: 24),
                      const SizedBox(height: 12),
                      Text('${state.availableDeliveries.length}',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                      const SizedBox(height: 4),
                      const Text('Available Pool', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Recent Completed Deliveries',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
          const SizedBox(height: 12),
          if (state.recentDeliveries.isEmpty)
            const SizedBox(
              height: 260,
              child: EmptyState(
                icon: Icons.local_shipping_outlined,
                title: 'No delivery history yet',
                message: 'Completed runs will show up here with payouts.',
              ),
            )
          else
            ...state.recentDeliveries.asMap().entries.map((entry) {
              final delivery = entry.value;
              return AppCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppTheme.success.withValues(alpha: 0.15),
                            radius: 16,
                            child: const Icon(Icons.check, color: AppTheme.success, size: 16),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(delivery.chefName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textMain)),
                              const SizedBox(height: 2),
                              Text(formatOrderDate(delivery.createdAt.toIso8601String()),
                                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                      Text(
                        '+₹${delivery.payout.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.success, fontSize: 15),
                      ),
                    ],
                  ),
                ).entrance(index: entry.key);
            }),
        ],
      ),
    );
  }

  Widget _buildAvailableTab(List<DriverDeliveryModel> available, DriverDashboardNotifier notifier) {
    if (!_isOnline) {
      return const EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'You\'re offline',
        message: 'Go online from the header to receive nearby dispatches.',
      );
    }
    if (available.isEmpty) {
      return const EmptyState(
        icon: Icons.radar_rounded,
        title: 'Scanning nearby kitchens',
        message: 'New partner deliveries will appear here as chefs release them.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: available.length,
      itemBuilder: (context, index) {
        final delivery = available[index];

        return AppCard(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Order #${delivery.orderId.substring(0, 6).toUpperCase()}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                  Text('+₹${delivery.payout.toStringAsFixed(0)} Payout',
                      style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 10),
              Text('Pickup: ${delivery.chefName}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textMain)),
              const SizedBox(height: 4),
              Text(delivery.pickupAddress, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Text('Dropoff: ${delivery.customerAddress}', style: const TextStyle(fontSize: 12, color: AppTheme.textMain)),
              const SizedBox(height: 16),
              GradientButton(
                label: 'Accept Delivery',
                icon: Icons.check_rounded,
                onPressed: () async {
                    final success = await notifier.acceptOrder(delivery.orderId);
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Order accepted successfully! Check Active tab.'), backgroundColor: Colors.green),
                      );
                    }
                  },
              ),
            ],
          ),
        ).entrance(index: index);
      },
    );
  }

  Widget _buildActiveDeliveryTab(List<DriverDeliveryModel> active, DriverDashboardNotifier notifier) {
    if (active.isEmpty) {
      return const EmptyState(
        icon: Icons.map_outlined,
        title: 'No active runs',
        message: 'Accepted deliveries will land here so you can navigate and complete them.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: active.length,
      itemBuilder: (context, index) {
        final delivery = active[index];
        final isOut = delivery.status == DeliveryStatus.outForDelivery;

        return AppCard(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Run #${delivery.orderId.substring(0, 6).toUpperCase()}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted)),
                  AppStatusBadge(status: delivery.status.toDbValue()),
                ],
              ),
              const SizedBox(height: 12),
              Text('Pickup from ${delivery.chefName}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textMain)),
              const SizedBox(height: 4),
              Text(delivery.pickupAddress, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Text('Deliver to: ${delivery.customerAddress}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textMain)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.navigation, size: 16),
                      label: const Text('Navigate'),
                      onPressed: () {
                        context.push('/tracking', extra: {
                          'order': {
                            'id': delivery.orderId,
                            'delivery_address': delivery.customerAddress,
                            'pickup_address': delivery.pickupAddress,
                            'title': delivery.chefName,
                          },
                          'isDriver': true,
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: isOut ? 'Mark Delivered' : 'Start Delivery',
                      icon: isOut ? Icons.check_rounded : Icons.delivery_dining_rounded,
                      gradient: isOut
                          ? const LinearGradient(colors: [AppTheme.success, Color(0xFF43C478)])
                          : AppTheme.primaryGradient,
                      onPressed: () async {
                        final nextStatus = isOut ? DeliveryStatus.delivered : DeliveryStatus.outForDelivery;
                        await notifier.updateDeliveryStatus(delivery.orderId, nextStatus);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ).entrance(index: index);
      },
    );
  }
}