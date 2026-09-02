// lib/screens/driver_hub.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../utils/app_theme.dart';
import '../utils/helpers.dart';
import '../widgets/customer_ui_components.dart';
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
            backgroundColor: AppTheme.surfaceDark,
            title: const Text('Exit App', style: TextStyle(color: Colors.white)),
            content: const Text('Are you sure you want to exit?', style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
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
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryGradientEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
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
                              Icon(Icons.circle, color: _isOnline ? Colors.greenAccent : Colors.redAccent, size: 10),
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
          backgroundColor: Colors.white,
          indicatorColor: AppTheme.primary.withValues(alpha: 0.15),
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
              gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryGradientEnd]),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
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
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No delivery history yet.', style: TextStyle(color: AppTheme.textMuted)),
              ),
            )
          else
            ...state.recentDeliveries.map((delivery) => AppCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
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
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 15),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildAvailableTab(List<DriverDeliveryModel> available, DriverDashboardNotifier notifier) {
    if (!_isOnline) {
      return const Center(child: Text('Go Online to receive orders.', style: TextStyle(color: Colors.grey, fontSize: 16)));
    }
    if (available.isEmpty) {
      return const Center(child: Text('Scanning for nearby orders...', style: TextStyle(color: AppTheme.textMuted)));
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
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                  onPressed: () async {
                    final success = await notifier.acceptOrder(delivery.orderId);
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Order accepted successfully! Check Active tab.'), backgroundColor: Colors.green),
                      );
                    }
                  },
                  child: const Text('Accept Delivery', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveDeliveryTab(List<DriverDeliveryModel> active, DriverDashboardNotifier notifier) {
    if (active.isEmpty) {
      return const Center(child: Text('No active deliveries in progress.', style: TextStyle(color: AppTheme.textMuted, fontSize: 15)));
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6)),
                    child: Text(delivery.status.toDbValue().toUpperCase(),
                        style: TextStyle(color: Colors.orange.shade800, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
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
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isOut ? Colors.green : AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final nextStatus = isOut ? DeliveryStatus.delivered : DeliveryStatus.outForDelivery;
                        await notifier.updateDeliveryStatus(delivery.orderId, nextStatus);
                      },
                      child: Text(isOut ? 'Mark Delivered' : 'Start Delivery',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}