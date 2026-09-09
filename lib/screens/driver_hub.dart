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
import '../widgets/order_slot_banner.dart';
import '../providers/driver_dashboard_provider.dart';
import '../models/app_role.dart';
import '../models/driver_delivery_model.dart';
import '../services/auth_session.dart';
import '../services/delivery_estimator_service.dart';
import '../services/order_lifecycle.dart';
import '../widgets/kyc_reminder_banner.dart';

class DriverHubScreen extends ConsumerStatefulWidget {
  const DriverHubScreen({super.key});

  @override
  ConsumerState<DriverHubScreen> createState() => _DriverHubScreenState();
}

class _DriverHubScreenState extends ConsumerState<DriverHubScreen> {
  int _selectedIndex = 0;
  bool _isOnline = true;
  String? _busyOrderId;
  final Set<String> _warnedMissingOtpOrderIds = {};

  @override
  void initState() {
    super.initState();
    unawaited(AuthSession.ensureHubRole(context, AppRole.driver));
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

  Future<void> _openNavigation(DriverDeliveryModel delivery) async {
    if (!mounted) return;
    context.push('/tracking', extra: {
      'order': delivery.toTrackingOrderExtra(),
      'isDriver': true,
    });
  }

  Future<void> _openExternalMaps(DriverDeliveryModel delivery) async {
    final toCustomer = delivery.navigateToCustomer;
    final mapsUri = googleMapsDirectionsUri(
      lat: toCustomer ? delivery.deliveryLat : delivery.pickupLat,
      lng: toCustomer ? delivery.deliveryLng : delivery.pickupLng,
      address: toCustomer ? delivery.customerAddress : delivery.pickupAddress,
    );
    if (mapsUri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            toCustomer
                ? 'Customer pin missing — use the address on the card.'
                : 'Kitchen pin missing — use the pickup address on the card.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    try {
      await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open Maps: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _addressBlock({
    required String title,
    required String address,
    required String coordLabel,
    required bool active,
    required IconData icon,
  }) {
    final color = active ? AppTheme.primary : AppTheme.textMuted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: active ? AppTheme.primary.withValues(alpha: 0.06) : AppTheme.surfaceOf(context),
        borderRadius: AppTheme.radiusLg,
        border: Border.all(
          color: active ? AppTheme.primary.withValues(alpha: 0.35) : AppTheme.hairlineOf(context),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.homeKickerOf(context).copyWith(color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  style: AppTheme.bodyOf(context),
                ),
                if (coordLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Pinned $coordLabel',
                    style: AppTheme.micro,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropoffNotesCard(DriverDeliveryModel delivery) {
    final gate = delivery.gateInstructions?.trim() ?? '';
    final otp = delivery.deliveryOtp?.trim() ?? '';
    var notes = delivery.specialInstructions?.trim() ?? '';
    if (notes.isNotEmpty) {
      notes = notes
          .split('\n')
          .map((line) => line.trim())
          .where((line) {
            if (line.isEmpty) return false;
            final lower = line.toLowerCase();
            if (gate.isNotEmpty && lower.startsWith('gate:')) return false;
            if (otp.isNotEmpty && (lower.contains('delivery pin:') || lower.startsWith('otp:'))) {
              return false;
            }
            return true;
          })
          .join('\n')
          .trim();
    }
    if (gate.isEmpty && otp.isEmpty && notes.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.10),
        borderRadius: AppTheme.radiusLg,
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GATE / DELIVERY NOTES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppTheme.onSurfaceOf(context),
            ),
          ),
          if (gate.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Gate instructions', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(gate, style: TextStyle(fontSize: 13, height: 1.35, color: AppTheme.onSurfaceOf(context), fontWeight: FontWeight.w600)),
          ],
          if (otp.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Delivery PIN / OTP', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              otp,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                fontFamily: 'monospace',
                color: AppTheme.onSurfaceOf(context),
              ),
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Special instructions', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(notes, style: TextStyle(fontSize: 13, height: 1.35, color: AppTheme.onSurfaceOf(context))),
          ],
        ],
      ),
    );
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
                  Expanded(
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          AppLogo(size: 32, onDark: true),
                          SizedBox(width: 10),
                          Flexible(
                            child: Text('Delivery Partner',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _toggleOnline,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: AppTheme.radiusLg,
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
                const KycReminderBanner(profilePath: '/driver-profile'),
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
                      const Text('Active Runs', style: AppTheme.caption),
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
                      const Text('Available Pool', style: AppTheme.caption),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Recent completed deliveries', style: AppTheme.homeSectionLabelOf(context)),
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
              final detail = delivery.driverHistoryDetail;
              return AppCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.success.withValues(alpha: 0.15),
                        radius: 16,
                        child: const Icon(Icons.check, color: AppTheme.success, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Order #${delivery.displayOrderNumber}',
                                    style: AppTheme.listTitleOf(context),
                                  ),
                                ),
                                Text(
                                  '+₹${delivery.payout.toStringAsFixed(0)}',
                                  style: AppTheme.priceOf(context).copyWith(color: AppTheme.success, fontSize: 15),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                delivery.chefName,
                style: AppTheme.caption,
              ),
                            if (detail.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                detail,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: AppTheme.onSurfaceOf(context).withValues(alpha: 0.78),
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              formatOrderDate(delivery.createdAt.toIso8601String()),
                              style: AppTheme.micro,
                            ),
                          ],
                        ),
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
      return EmptyState(
        icon: Icons.radar_rounded,
        title: 'Scanning nearby kitchens',
        message: 'Jobs appear here after a chef confirms the order and marks it Ready for Pickup.',
        actionLabel: 'Refresh Jobs',
        onAction: () => ref.read(driverDashboardProvider.notifier).loadDashboardData(),
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted)),
                  Text('+₹${delivery.payout.toStringAsFixed(0)} Payout',
                      style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                delivery.statusLabel.isEmpty ? delivery.status.toDbValue() : delivery.statusLabel,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.link),
              ),
              const SizedBox(height: 10),
              Text('Pickup: ${delivery.chefName}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.onSurfaceOf(context))),
              if (delivery.itemsSummary.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(delivery.itemsSummary,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceOf(context))),
              ],
              const SizedBox(height: 4),
              Text(delivery.pickupAddress, style: AppTheme.caption),
              if (delivery.pickupCoordLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Pinned ${delivery.pickupCoordLabel}',
                    style: AppTheme.micro),
              ],
              const SizedBox(height: 8),
              Text('Dropoff: ${delivery.customerAddress}', style: TextStyle(fontSize: 12, color: AppTheme.onSurfaceOf(context))),
              if (delivery.dropoffCoordLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Pinned ${delivery.dropoffCoordLabel}',
                    style: AppTheme.micro),
              ],
              if (delivery.distanceKm > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${delivery.distanceKm.toStringAsFixed(1)} km • ~${DeliveryEstimatorService.estimateEtaMinutes(delivery.distanceKm)} min',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.link),
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

  Future<bool> _confirmMarkDelivered(DriverDeliveryModel delivery) async {
    final expected = delivery.deliveryOtp?.trim() ?? '';
    if (expected.isEmpty) {
      if (_warnedMissingOtpOrderIds.add(delivery.orderId) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No delivery PIN on this order — marking delivered without PIN check.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return true;
    }

    final controller = TextEditingController();
    final matched = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: AppTheme.dialogShape,
          title: const Text('Enter delivery PIN'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '4-digit PIN from customer',
              counterText: '',
            ),
            onSubmitted: (_) {
              final ok = deliveryOtpMatches(expected, controller.text);
              Navigator.pop(ctx, ok);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final ok = deliveryOtpMatches(expected, controller.text);
                if (!ok) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('PIN does not match. Ask the customer for the delivery PIN.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return matched == true;
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
        final rawStatus = delivery.statusLabel.isEmpty ? delivery.status.toDbValue() : delivery.statusLabel;
        final isOut = OrderLifecycle.canDriverCompleteRun(rawStatus);
        final canStart = OrderLifecycle.canDriverStartRun(rawStatus);

        return AppCard(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Run #${formatOrderId(null, delivery.orderId)}',
                      style: AppTheme.micro),
                  AppStatusBadge(status: rawStatus),
                ],
              ),
              const SizedBox(height: 12),
              Text(delivery.activeStepTitle, style: AppTheme.listTitleOf(context)),
              if (delivery.itemsSummary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Order #${delivery.displayOrderNumber} · ${delivery.itemsSummary}',
                  style: AppTheme.caption,
                ),
              ],
              const SizedBox(height: 10),
              _addressBlock(
                title: 'PICKUP · CHEF KITCHEN',
                address: delivery.pickupAddress,
                coordLabel: delivery.pickupCoordLabel,
                active: !delivery.navigateToCustomer,
                icon: Icons.storefront_outlined,
              ),
              const SizedBox(height: 8),
              _addressBlock(
                title: 'DROPOFF · CUSTOMER',
                address: delivery.customerAddress,
                coordLabel: delivery.dropoffCoordLabel,
                active: delivery.navigateToCustomer,
                icon: Icons.home_outlined,
              ),
              if (delivery.hasDropoffNotes) ...[
                const SizedBox(height: 8),
                _dropoffNotesCard(delivery),
              ],
              const SizedBox(height: 10),
              OrderSlotBanner(order: delivery.slotSource),
              const SizedBox(height: 12),
              Row(
                children: [
                  AppIconAction(
                    icon: Icons.chat_bubble_outline,
                    tooltip: orderAllowsPartyChat(rawStatus) ? 'Chat' : 'Chat closed',
                    onPressed: !orderAllowsPartyChat(rawStatus)
                        ? null
                        : () {
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
                  const SizedBox(width: 8),
                  AppIconAction(
                    icon: Icons.phone_outlined,
                    tooltip: orderAllowsPhoneCall(rawStatus) ? 'Call' : 'Chat preferred',
                    onPressed: !orderAllowsPhoneCall(rawStatus)
                        ? null
                        : () => _callCustomer(delivery.customerId),
                  ),
                  const SizedBox(width: 8),
                  AppIconAction(
                    icon: Icons.navigation,
                    tooltip: delivery.navigateButtonLabel,
                    onPressed: () => _openNavigation(delivery),
                  ),
                  const SizedBox(width: 8),
                  AppIconAction(
                    icon: Icons.map_outlined,
                    tooltip: delivery.navigateToCustomer
                        ? 'Open customer in Google Maps'
                        : 'Open kitchen in Google Maps',
                    onPressed: () => _openExternalMaps(delivery),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (isOut || canStart)
                Semantics(
                  button: true,
                  label: isOut ? 'Mark Delivered' : 'Start Delivery',
                  child: GradientButton(
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
                            if (isOut) {
                              final allowed = await _confirmMarkDelivered(delivery);
                              if (!allowed || !mounted) return;
                            }
                            setState(() => _busyOrderId = delivery.orderId);
                            final nextStatus = isOut ? DeliveryStatus.delivered : DeliveryStatus.outForDelivery;
                            final ok = await notifier.updateDeliveryStatus(delivery.orderId, nextStatus);
                            if (!mounted) return;
                            setState(() => _busyOrderId = null);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? (isOut
                                          ? 'Marked as delivered.'
                                          : 'Out for delivery — navigate to the customer.')
                                      : (ref.read(driverDashboardProvider).errorMessage ??
                                          'Could not update this run. Try again.'),
                                ),
                                backgroundColor: ok ? Colors.green : Colors.red,
                              ),
                            );
                          },
                  ),
                )
              else
                const Text(
                  'The kitchen is still preparing this order. Start Delivery unlocks after Ready for Pickup.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.35),
                ),
            ],
          ),
        ).entrance(index: index);
      },
    );
  }
}