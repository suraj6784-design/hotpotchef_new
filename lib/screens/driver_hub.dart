// lib/screens/driver_hub.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import '../services/kitchen_media.dart';
import '../services/order_lifecycle.dart';
import '../widgets/driver_payout_cadence_card.dart';
import '../widgets/kyc_reminder_banner.dart';
import '../widgets/diner_storefront.dart';
import 'driver_profile_screen.dart';
import 'notifications_inbox_screen.dart';

class DriverHubScreen extends ConsumerStatefulWidget {
  const DriverHubScreen({super.key, this.initialTab = 0, this.initialOrdersStage = 0});

  final int initialTab;
  final int initialOrdersStage;

  @override
  ConsumerState<DriverHubScreen> createState() => _DriverHubScreenState();
}

class _DriverHubScreenState extends ConsumerState<DriverHubScreen> {
  late int _selectedIndex = widget.initialTab;
  late int _ordersStage = widget.initialOrdersStage;
  bool _isOnline = true;
  String? _acceptingOrderId;
  String? _busyOrderId;
  String _welcomeName = 'Partner';
  String _driverFullName = '';
  String _driverPhone = '';
  String? _driverAvatarUrl;
  String _driverIdNo = '';
  String _driverBloodGroup = '';
  String _driverEmergencyPhone = '';

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
      final userRow = await Supabase.instance.client
          .from('users')
          .select('name, full_name, phone, avatar_url, driver_id_no, blood_group, emergency_phone')
          .eq('id', user.id)
          .maybeSingle();
      if (mounted) {
        setState(() {
          if (row != null) _isOnline = row['is_available'] != false;
          final raw = userRow?['name']?.toString() ?? userRow?['full_name']?.toString() ?? '';
          if (raw.trim().isNotEmpty) {
            _driverFullName = raw.trim();
            _welcomeName = raw.trim().split(' ').first;
          }
          final phone = userRow?['phone']?.toString() ??
              user.userMetadata?['phone']?.toString() ??
              user.phone ??
              '';
          if (phone.trim().isNotEmpty) _driverPhone = phone.trim();
          final avatar = userRow?['avatar_url']?.toString();
          if (avatar != null && avatar.trim().isNotEmpty) _driverAvatarUrl = avatar.trim();
          final idNo = userRow?['driver_id_no']?.toString().trim() ?? '';
          if (idNo.isNotEmpty) _driverIdNo = idNo;
          final blood = userRow?['blood_group']?.toString().trim() ?? '';
          if (blood.isNotEmpty) _driverBloodGroup = blood;
          final emergency = userRow?['emergency_phone']?.toString().trim() ?? '';
          if (emergency.isNotEmpty) _driverEmergencyPhone = emergency;
        });
      }
    } catch (_) {}
  }

  void _openDigitalId() {
    context.push('/driver-id-card', extra: {
      'name': _driverFullName.isEmpty ? 'Delivery Partner' : _driverFullName,
      'phone': _driverPhone,
      if (_driverAvatarUrl != null) 'avatarUrl': _driverAvatarUrl,
      'idCardNo': _driverIdNo,
      'bloodGroup': _driverBloodGroup,
      'emergencyPhone': _driverEmergencyPhone,
    });
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
      preferAddress: toCustomer,
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
    var notes = driverFacingOrderNotes(delivery.specialInstructions);
    if (notes.isNotEmpty) {
      notes = notes
          .split('\n')
          .map((line) => line.trim())
          .where((line) {
            if (line.isEmpty) return false;
            final lower = line.toLowerCase();
            if (gate.isNotEmpty && lower.startsWith('gate:')) return false;
            return true;
          })
          .join('\n')
          .trim();
    }
    if (gate.isEmpty && notes.isEmpty) return const SizedBox.shrink();
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
      _buildHomeTab(dashboardState),
      _buildOrdersWorkspace(dashboardState, notifier),
      DriverProfileScreen(
        embedded: true,
        onOpenWallet: () => setState(() {
          _selectedIndex = 1;
          _ordersStage = 2;
        }),
      ),
      NotificationsInboxScreen(
        key: ValueKey('driver-alerts-${Supabase.instance.client.auth.currentUser?.id ?? 'guest'}'),
        embedded: true,
        partnerInbox: true,
      ),
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
            if (_selectedIndex != 2 && _selectedIndex != 3) _buildPartnerHeader(),
                if (_selectedIndex == 0) const KycReminderBanner(profilePath: '/driver-profile'),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: hubDockBodyGap(context)),
                    child: HubTabSwitcher(
                      index: _selectedIndex,
                      children: pages,
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: HubBottomDock(
                selectedIndex: _selectedIndex,
                onSelect: (idx) => setState(() => _selectedIndex = idx),
                destinations: [
                  const HubDockDestination(
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home_rounded,
                    label: 'Home',
                  ),
                  HubDockDestination(
                    icon: Icons.receipt_long_outlined,
                    selectedIcon: Icons.receipt_long,
                    label: 'Orders',
                    badgeCount: dashboardState.availableDeliveries.length,
                  ),
                  const HubDockDestination(
                    icon: Icons.person_outline_rounded,
                    selectedIcon: Icons.person_rounded,
                    label: 'Profile',
                  ),
                  const HubDockDestination(
                    icon: Icons.notifications_none_rounded,
                    selectedIcon: Icons.notifications_rounded,
                    label: 'Alerts',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Sub-Tabs ---

  Widget _buildPartnerHeader() {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      color: AppTheme.canvasOf(context),
      padding: EdgeInsets.fromLTRB(16, top + 8, 8, 8),
      child: Row(
        children: [
          if (_selectedIndex == 0) ...[
            const AppLogo(size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'HotPotChef Partner',
                style: AppTheme.sectionTitleOf(context).copyWith(color: AppTheme.primary, fontSize: 18),
              ),
            ),
          ] else
            Expanded(
              child: Text('Delivery Orders', style: AppTheme.sectionTitleOf(context)),
            ),
          IconButton(
            tooltip: 'Order chats',
            onPressed: () => context.push('/chats'),
            icon: const Icon(Icons.forum_outlined),
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: () => AuthSession.confirmSignOut(context),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab(DriverDashboardState state) {
    final now = DateTime.now();
    final todayEarn = state.recentDeliveries.where((d) {
      final local = d.createdAt.toLocal();
      return local.year == now.year && local.month == now.month && local.day == now.day;
    }).fold<double>(0, (sum, d) => sum + d.payout);

    return RefreshIndicator(
      onRefresh: () => ref.read(driverDashboardProvider.notifier).loadDashboardData(),
      color: AppTheme.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          if (state.errorMessage != null) ...[
            EmptyState(
              icon: Icons.wifi_off_rounded,
              title: "Couldn't load jobs",
              message: state.errorMessage,
              actionLabel: 'Retry',
              onAction: () => ref.read(driverDashboardProvider.notifier).loadDashboardData(),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome back, $_welcomeName!', style: AppTheme.sectionTitleOf(context).copyWith(fontSize: 22)),
                    const SizedBox(height: 4),
                    Text(
                      _isOnline ? 'Online · nearby kitchens can dispatch to you' : 'Offline · you will not see new jobs',
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Switch.adaptive(
                    value: _isOnline,
                    activeThumbColor: AppTheme.live,
                    onChanged: (_) => _toggleOnline(),
                  ),
                  Text(
                    _isOnline ? 'Go Offline' : 'Go Online',
                    style: AppTheme.microOf(context).copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text("Today's Summary", style: AppTheme.homeSectionLabelOf(context)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _driverStatCard('Open Jobs', '${state.availableDeliveries.length}', onTap: () {
                  setState(() {
                    _selectedIndex = 1;
                    _ordersStage = 0;
                  });
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _driverStatCard('Total Earnings', '₹${todayEarn.toStringAsFixed(0)}', onTap: () {
                  setState(() {
                    _selectedIndex = 1;
                    _ordersStage = 2;
                  });
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const DriverPayoutCadenceCard(),
          const SizedBox(height: 18),
          Text('Quick Driver Tools', style: AppTheme.homeSectionLabelOf(context)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _driverToolCard(
                  icon: Icons.radar_rounded,
                  label: 'Scan Jobs',
                  onTap: () => setState(() {
                    _selectedIndex = 1;
                    _ordersStage = 0;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _driverToolCard(
                  icon: Icons.badge_outlined,
                  label: 'Digital ID',
                  onTap: _openDigitalId,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _driverStatCard(String label, String value, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceOf(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.hairlineOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTheme.microOf(context)),
            const SizedBox(height: 6),
            Text(value, style: AppTheme.sectionTitleOf(context).copyWith(fontSize: 22)),
          ],
        ),
      ),
    );
  }

  Widget _driverToolCard({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceOf(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.hairlineOf(context)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primary, size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersWorkspace(DriverDashboardState state, DriverDashboardNotifier notifier) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: DinerSegmentBar(
            labels: [
              'Available (${state.availableDeliveries.length})',
              'Active (${state.activeDeliveries.length})',
              'Completed',
            ],
            index: _ordersStage,
            onChanged: (index) => setState(() => _ordersStage = index),
          ),
        ),
        Expanded(
          child: _ordersStage == 0
              ? _buildAvailableTab(state.availableDeliveries, notifier)
              : _ordersStage == 1
                  ? _buildActiveDeliveryTab(state.activeDeliveries, notifier)
                  : _buildCompletedRuns(state),
        ),
      ],
    );
  }

  Widget _buildCompletedRuns(DriverDashboardState state) {
    if (state.recentDeliveries.isEmpty) {
      return const EmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'No delivery history yet',
        message: 'Completed runs will show up here with payouts in ₹.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        AppCard(
          child: Column(
            children: [
              Text('Run wallet', style: AppTheme.metaOf(context)),
              const SizedBox(height: 6),
              Text(
                '₹${state.totalEarnings.toStringAsFixed(0)}',
                style: AppTheme.sectionTitleOf(context).copyWith(color: AppTheme.success, fontSize: 28),
              ),
              Text(
                '${state.completedCount} completed · delivery fee + tip. Bank payout is arranged by ops after KYC.',
                textAlign: TextAlign.center,
                style: AppTheme.metaOf(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...state.recentDeliveries.asMap().entries.map((entry) {
          final delivery = entry.value;
          return AppCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(delivery.chefName, style: AppTheme.listTitleOf(context)),
                      const SizedBox(height: 4),
                      Text('Order #${delivery.displayOrderNumber}', style: AppTheme.caption),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '+₹${delivery.payout.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.live),
                    ),
                    Text(formatOrderDate(delivery.createdAt.toIso8601String()), style: AppTheme.microOf(context)),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ignore: unused_element
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
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Wallet = delivery fee + tip on completed runs. Bank payout is arranged by ops after KYC — not an automatic weekly transfer.',
                  style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const DriverPayoutCadenceCard(),
          const SizedBox(height: 8),
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
                      Text('Active Runs', style: AppTheme.caption),
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
                      Text('Available Pool', style: AppTheme.caption),
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
                loading: _acceptingOrderId == delivery.orderId,
                onPressed: _acceptingOrderId != null
                    ? null
                    : () async {
                        setState(() => _acceptingOrderId = delivery.orderId);
                        final success = await notifier.acceptOrder(delivery.orderId);
                        if (!mounted) return;
                        setState(() => _acceptingOrderId = null);
                        if (success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Order accepted. Open Active to navigate.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          setState(() => _ordersStage = 1);
                          return;
                        }
                        final reason = ref.read(driverDashboardProvider).errorMessage ??
                            'Could not accept this run. Try again.';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(reason), backgroundColor: Colors.redAccent),
                        );
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
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: AppTheme.dialogShape,
          title: const Text('Delivery PIN required'),
          content: const Text(
            'This order has no PIN on the server yet. Ask the diner to open Orders or Tracking and share the 4-digit PIN. Completing without a PIN is not allowed.',
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return false;
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
    if (matched != true) return false;
    if (!mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: AppTheme.dialogShape,
        title: const Text('Door photo'),
        content: const Text(
          'Take a timestamped photo at the door. Ops uses this with the PIN if a refund is raised.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open camera')),
        ],
      ),
    );
    return proceed == true;
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
                            String? podUrl;
                            if (isOut) {
                              try {
                                podUrl = await captureDeliveryPodPhoto(orderId: delivery.orderId);
                              } catch (_) {
                                podUrl = null;
                              }
                              if (podUrl == null || podUrl.isEmpty) {
                                if (mounted) {
                                  setState(() => _busyOrderId = null);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Door photo is required to mark delivered.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                                return;
                              }
                            }
                            final nextStatus = isOut ? DeliveryStatus.delivered : DeliveryStatus.outForDelivery;
                            final ok = await notifier.updateDeliveryStatus(
                              delivery.orderId,
                              nextStatus,
                              deliveryOtp: isOut ? delivery.deliveryOtp : null,
                              podPhotoUrl: podUrl,
                            );
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