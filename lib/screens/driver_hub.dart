// lib/screens/driver_hub.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/helpers.dart';
import '../widgets/customer_ui_components.dart';
import '../widgets/app_widgets.dart';
import '../widgets/app_status_badge.dart';
import '../providers/driver_dashboard_provider.dart';
import '../models/driver_delivery_model.dart';
import '../services/auth_session.dart';
import '../services/delivery_estimator_service.dart';

class DriverHubScreen extends ConsumerStatefulWidget {
  const DriverHubScreen({super.key});

  @override
  ConsumerState<DriverHubScreen> createState() => _DriverHubScreenState();
}

class _DriverHubScreenState extends ConsumerState<DriverHubScreen> {
  int _selectedIndex = 0;
  bool _isOnline = true;
  String? _busyOrderId;

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final row = await Supabase.instance.client
          .from('driver_profiles')
          .select('is_available')
          .eq('user_id', user.id)
          .maybeSingle();
      if (mounted && row != null) {
        setState(() => _isOnline = row['is_available'] != false);
      }
    } catch (_) {}
  }

  Future<void> _toggleOnline() async {
    final next = !_isOnline;
    setState(() => _isOnline = next);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.from('driver_profiles').upsert({
        'user_id': user.id,
        'is_available': next,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      try {
        await Supabase.instance.client
            .from('driver_profiles')
            .update({'is_available': next})
            .eq('user_id', user.id);
      } catch (e) {
        if (mounted) {
          setState(() => _isOnline = !next);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not update availability: $e'), backgroundColor: Colors.red),
          );
          return;
        }
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next ? 'Online • Receiving dispatches' : 'You are offline'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _callCustomer(String customerId) async {
    if (customerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No customer contact on this order.'), backgroundColor: Colors.orange),
      );
      return;
    }
    try {
      final userDoc = await Supabase.instance.client.from('users').select('phone').eq('id', customerId).maybeSingle();
      final phoneStr = userDoc?['phone']?.toString() ?? '';
      if (phoneStr.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No phone number available.'), backgroundColor: Colors.orange),
          );
        }
        return;
      }
      final uri = Uri(scheme: 'tel', path: phoneStr);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open phone dialer.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

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
        backgroundColor: AppTheme.canvasOf(context),
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Column(
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
                        onTap: _toggleOnline,
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
                        onTap: () => context.push('/chats'),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                          child: const Icon(Icons.forum_outlined, color: Colors.white, size: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          context.push('/driver-profile');
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
                Expanded(
                  child: HubTabSwitcher(
                    index: _selectedIndex,
                    children: pages,
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: HubBottomDock(
                selectedIndex: _selectedIndex,
                onSelect: (idx) => setState(() => _selectedIndex = idx),
                destinations: const [
                  HubDockDestination(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Home'),
                  HubDockDestination(icon: Icons.list_alt_outlined, selectedIcon: Icons.list_alt, label: 'Jobs'),
                  HubDockDestination(icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Active'),
                ],
              ),
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
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
        children: [
          if (state.errorMessage != null) ...[
            EmptyState(
              icon: Icons.wifi_off_rounded,
              title: 'Couldn\'t load jobs',
              message: state.errorMessage,
              actionLabel: 'Retry',
              onAction: () => ref.read(driverDashboardProvider.notifier).loadDashboardData(),
            ),
            const SizedBox(height: 16),
          ],
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
                    Text(
                        '${state.completedCount} Successful ${state.completedCount == 1 ? 'Delivery' : 'Deliveries'}',
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
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context))),
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
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context))),
                      const SizedBox(height: 4),
                      const Text('Available Pool', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Recent completed deliveries',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.onSurfaceOf(context))),
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
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.onSurfaceOf(context))),
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
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
                  Text('Order #${formatOrderId(null, delivery.orderId)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                  Text('+₹${delivery.payout.toStringAsFixed(0)} Payout',
                      style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 10),
              Text('Pickup: ${delivery.chefName}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.onSurfaceOf(context))),
              const SizedBox(height: 4),
              Text(delivery.pickupAddress, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Text('Dropoff: ${delivery.customerAddress}', style: TextStyle(fontSize: 12, color: AppTheme.onSurfaceOf(context))),
              if (delivery.distanceKm > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${delivery.distanceKm.toStringAsFixed(1)} km • ~${DeliveryEstimatorService.estimateEtaMinutes(delivery.distanceKm)} min',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                ),
              ],
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
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
                  Text('Run #${formatOrderId(null, delivery.orderId)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted)),
                  AppStatusBadge(status: delivery.status.toDbValue()),
                ],
              ),
              const SizedBox(height: 12),
              Text('Pickup from ${delivery.chefName}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.onSurfaceOf(context))),
              const SizedBox(height: 4),
              Text(delivery.pickupAddress, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Text('Deliver to: ${delivery.customerAddress}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceOf(context))),
              const SizedBox(height: 10),
              _DeliverySlotRow(order: delivery.slotSource),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: const Text('Chat'),
                      onPressed: () {
                        final roomId = delivery.chatRoomId.isNotEmpty ? delivery.chatRoomId : delivery.orderId;
                        context.push(chatPath(
                          roomId,
                          roomName: 'Order ${formatOrderId(null, delivery.orderId)}',
                          otherUserId: delivery.customerId,
                          memberIds: [
                            delivery.customerId,
                            delivery.chefId,
                            Supabase.instance.client.auth.currentUser?.id ?? '',
                          ],
                          isGroup: true,
                        ));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.phone_outlined, size: 16),
                      label: const Text('Call'),
                      onPressed: () => _callCustomer(delivery.customerId),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
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
              const SizedBox(height: 10),
              GradientButton(
                label: isOut ? 'Mark Delivered' : 'Start Delivery',
                icon: isOut ? Icons.check_rounded : Icons.delivery_dining_rounded,
                height: 48,
                loading: _busyOrderId == delivery.orderId,
                gradient: isOut
                    ? const LinearGradient(colors: [AppTheme.success, Color(0xFF43C478)])
                    : AppTheme.primaryGradient,
                onPressed: _busyOrderId != null
                    ? null
                    : () async {
                        setState(() => _busyOrderId = delivery.orderId);
                        final nextStatus = isOut ? DeliveryStatus.delivered : DeliveryStatus.outForDelivery;
                        final ok = await notifier.updateDeliveryStatus(delivery.orderId, nextStatus);
                        if (!mounted) return;
                        setState(() => _busyOrderId = null);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? (isOut ? 'Marked as delivered.' : 'Out for delivery.')
                                  : (ref.read(driverDashboardProvider).errorMessage ??
                                      'Could not update this run. Try again.'),
                            ),
                            backgroundColor: ok ? Colors.green : Colors.red,
                          ),
                        );
                      },
              ),
            ],
          ),
        ).entrance(index: index);
      },
    );
  }
}

class _DeliverySlotRow extends StatefulWidget {
  const _DeliverySlotRow({required this.order});

  final Map<String, dynamic> order;

  @override
  State<_DeliverySlotRow> createState() => _DeliverySlotRowState();
}

class _DeliverySlotRowState extends State<_DeliverySlotRow> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = formatDeliverySlotLabel(widget.order);
    final start = orderSlotStart(widget.order);
    final left = formatSlotCountdown(start);
    final late = start != null && start.isBefore(DateTime.now());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 18, color: late ? AppTheme.error : AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Slot $slot', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.onSurfaceOf(context))),
                if (left.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    left,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: late ? AppTheme.error : AppTheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}