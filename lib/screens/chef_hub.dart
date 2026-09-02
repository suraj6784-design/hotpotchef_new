// lib/screens/chef_hub.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../utils/helpers.dart';
import '../models/cart_enums.dart';
import '../widgets/customer_ui_components.dart';
import '../widgets/app_widgets.dart';
import '../widgets/app_status_badge.dart';
import '../services/order_lifecycle.dart';
import '../services/auth_session.dart';
import 'packaging_store_screen.dart';

class ChefDashboardScreen extends StatefulWidget {
  const ChefDashboardScreen({super.key});

  @override
  State<ChefDashboardScreen> createState() => _ChefDashboardScreenState();
}

class _ChefDashboardScreenState extends State<ChefDashboardScreen> {
  final _supabase = Supabase.instance.client;
  final _orderLifecycle = OrderLifecycle();

  int _selectedIndex = 0;
  bool _isKitchenOpen = true;
  String _fulfillmentFilter = 'All';

  final List<String> _fulfillmentTabs = const [
    'All',
    'Delivery Partner',
    'Chef-Self',
    'Customer Pickup',
    'Dine In',
  ];

  String get _currentUserId => _supabase.auth.currentUser?.id ?? '';
  String get _currentUserEmail => _supabase.auth.currentUser?.email ?? 'Chef';

  // Resolved customer_id -> display name cache (orders only store customer_id).
  final Map<String, String> _customerNameCache = {};
  final Set<String> _customerNameLoading = {};

  @override
  void initState() {
    super.initState();
    _loadKitchenStatus();
  }

  // --- Order data helpers (orders use the legacy schema: `items` JSON text,
  // `total_price`, `order_type`, `customer_id`). ---

  double _toAmount(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  List<Map<String, dynamic>> _parseItems(dynamic raw) {
    if (raw == null) return const [];
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is List) {
        return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {
      // Malformed JSON — fall through to empty list.
    }
    return const [];
  }

  double _orderTotal(Map<String, dynamic> order) =>
      _toAmount(order['total_price'] ?? order['total_amount']);

  ServiceType _orderService(Map<String, dynamic> order) =>
      ServiceType.fromString(order['order_type']?.toString() ?? order['service_type']?.toString());

  String _orderTitle(Map<String, dynamic> order) {
    final items = _parseItems(order['items']);
    if (items.isEmpty) return order['title']?.toString() ?? 'Meal Order';
    final first = items.first['title']?.toString() ?? 'Meal Order';
    return items.length > 1 ? '$first +${items.length - 1} more' : first;
  }

  int _orderQuantity(Map<String, dynamic> order) {
    final items = _parseItems(order['items']);
    if (items.isEmpty) return int.tryParse(order['quantity']?.toString() ?? '1') ?? 1;
    return items.fold<int>(
        0, (sum, it) => sum + (int.tryParse(it['quantity']?.toString() ?? '1') ?? 1));
  }

  String _customerName(Map<String, dynamic> order) {
    final id = order['customer_id']?.toString() ?? '';
    if (id.isEmpty) return order['customer_name']?.toString() ?? 'Guest';
    final cached = _customerNameCache[id];
    if (cached != null) return cached;
    _loadCustomerName(id);
    return 'Customer';
  }

  Future<void> _loadCustomerName(String customerId) async {
    if (_customerNameCache.containsKey(customerId) || _customerNameLoading.contains(customerId)) {
      return;
    }
    _customerNameLoading.add(customerId);
    try {
      final row = await _supabase
          .from('users')
          .select('name, full_name, email')
          .eq('id', customerId)
          .maybeSingle();
      final resolved = (row?['name'] ?? row?['full_name'] ?? row?['email'] ?? 'Customer')
          .toString()
          .trim();
      final name = resolved.isEmpty ? 'Customer' : resolved;
      if (mounted) {
        setState(() => _customerNameCache[customerId] = name);
      } else {
        _customerNameCache[customerId] = name;
      }
    } catch (_) {
      // Leave uncached so it can be retried on the next rebuild.
    } finally {
      _customerNameLoading.remove(customerId);
    }
  }

  Future<void> _loadKitchenStatus() async {
    if (_currentUserId.isEmpty) return;
    try {
      final res = await _supabase
          .from('chef_profiles')
          .select('is_open')
          .eq('user_id', _currentUserId)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() => _isKitchenOpen = res['is_open'] == true);
      }
    } catch (e) {
      debugPrint('Failed to load kitchen status: $e');
    }
  }

  Future<void> _toggleKitchenStatus() async {
    final nextState = !_isKitchenOpen;
    setState(() => _isKitchenOpen = nextState);

    try {
      await _supabase
          .from('chef_profiles')
          .update({'is_open': nextState})
          .eq('user_id', _currentUserId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextState ? '🟢 Kitchen is Online & Accepting Orders' : '🔴 Kitchen is Offline'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _isKitchenOpen = !nextState);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update kitchen status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  bool _matchesFilter(Map<String, dynamic> order, String filter) {
    if (filter == 'All') return true;
    final svc = _orderService(order);
    switch (filter) {
      case 'Delivery Partner':
        return svc == ServiceType.deliveryPlatform;
      case 'Chef-Self':
        return svc == ServiceType.deliverySelf;
      case 'Customer Pickup':
        return svc == ServiceType.pickup;
      case 'Dine In':
        return svc == ServiceType.dineIn;
      default:
        return true;
    }
  }

  // --- Order State Transitions ---

  Future<void> _cancelCustomerOrder(Map<String, dynamic> order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppTheme.error),
          SizedBox(width: 8),
          Expanded(child: Text('Cancel & Restock?')),
        ]),
        content: const Text(
          'Are you sure you want to cancel this order? It will be refunded, and inventory will be automatically restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Order'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _orderLifecycle.cancel(
        orderId: order['id'].toString(),
        chefId: _currentUserId,
        reason: 'Cancelled by kitchen',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order cancelled, inventory restored, and refund started.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'Chef order cancellation failure');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _advanceKitchen(Map<String, dynamic> order) async {
    try {
      final current = order['status']?.toString() ?? '';
      final next = OrderLifecycle.nextKitchenStatus(current);
      await _orderLifecycle.advanceKitchen(orderId: order['id'].toString(), currentStatus: current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to: $next'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _dispatchOrder(Map<String, dynamic> order) async {
    try {
      final current = order['status']?.toString() ?? '';
      final svc = ServiceType.fromString(order['service_type']?.toString());
      final next = OrderLifecycle.nextDispatchStatus(current, svc);
      await _orderLifecycle.dispatch(
        orderId: order['id'].toString(),
        currentStatus: current,
        service: svc,
      );
      if (!mounted) return;
      if (next == null && svc.usesDeliveryPartner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ready for a delivery partner. Drivers can accept this order now.'),
            backgroundColor: Colors.teal,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to: $next'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // --- Main Build ---

  @override
  Widget build(BuildContext context) {
    if (_currentUserId.isEmpty) {
      return const Scaffold(body: Center(child: Text('Authentication required.')));
    }

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
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase
            .from('orders')
            .stream(primaryKey: ['id'])
            .eq('chef_id', _currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
            return Scaffold(
              backgroundColor: AppTheme.background,
              body: Column(
                children: [
                  _buildHeader(),
                  const Expanded(child: OrderListSkeleton()),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Scaffold(
              backgroundColor: AppTheme.background,
              body: EmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Kitchen connection lost',
                message: 'We couldn\'t load your orders. Check your connection and try again.',
                actionLabel: 'Retry',
                onAction: () => setState(() {}),
              ),
            );
          }

          final orders = snapshot.data ?? [];

          final pendingCount = orders.where((o) => OrderLifecycle.isPendingKitchen(o['status']?.toString())).length;
          final dispatchCount = orders.where((o) => OrderLifecycle.isDispatchQueue(o['status']?.toString())).length;

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _supabase
                .from('customer_requests')
                .stream(primaryKey: ['id'])
                .eq('status', 'Open'),
            builder: (context, reqSnapshot) {
              final openLeadsCount = reqSnapshot.data?.length ?? 0;

              final List<Widget> tabs = [
                _buildOrdersTab(orders),
                _buildDispatchTab(orders),
                _buildMenuTab(),
                _buildHistoryTab(orders),
                _buildCustomerLeadsTab(reqSnapshot.data ?? []),
                const PackagingStoreScreen(),
              ];

              return Scaffold(
                backgroundColor: AppTheme.background,
                body: Column(
                  children: [
                    _buildHeader(),
                    Expanded(child: tabs[_selectedIndex]),
                  ],
                ),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
                  destinations: [
                    NavigationDestination(
                      icon: Badge(label: Text('$pendingCount'), isLabelVisible: pendingCount > 0, child: const Icon(Icons.receipt_long_outlined)),
                      selectedIcon: Badge(label: Text('$pendingCount'), isLabelVisible: pendingCount > 0, child: const Icon(Icons.receipt_long, color: AppTheme.primary)),
                      label: 'Orders',
                    ),
                    NavigationDestination(
                      icon: Badge(label: Text('$dispatchCount'), isLabelVisible: dispatchCount > 0, child: const Icon(Icons.local_shipping_outlined)),
                      selectedIcon: Badge(label: Text('$dispatchCount'), isLabelVisible: dispatchCount > 0, child: const Icon(Icons.local_shipping, color: AppTheme.primary)),
                      label: 'Dispatch',
                    ),
                    const NavigationDestination(icon: Icon(Icons.restaurant_menu_outlined), selectedIcon: Icon(Icons.restaurant_menu, color: AppTheme.primary), label: 'Menu'),
                    const NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet, color: AppTheme.primary), label: 'History'),
                    NavigationDestination(
                      icon: Badge(label: Text('$openLeadsCount'), isLabelVisible: openLeadsCount > 0, child: const Icon(Icons.campaign_outlined)),
                      selectedIcon: Badge(label: Text('$openLeadsCount'), isLabelVisible: openLeadsCount > 0, child: const Icon(Icons.campaign, color: AppTheme.primary)),
                      label: 'Leads',
                    ),
                    const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2, color: AppTheme.primary), label: 'Supplies'),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // --- Sub-Components ---

  Widget _headerIcon(IconData icon, String tooltip, VoidCallback onPressed) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, color: Colors.white, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, left: 20, right: 20, bottom: 20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
        boxShadow: AppTheme.brandGlow(opacity: 0.28),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Chef Dashboard', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(_currentUserEmail, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _toggleKitchenStatus,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white38),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _isKitchenOpen
                          ? const Icon(Icons.circle, color: Colors.greenAccent, size: 9)
                              .animate(onPlay: (c) => c.repeat(reverse: true))
                              .fade(begin: 0.35, end: 1, duration: 900.ms)
                          : const Icon(Icons.circle, color: Colors.redAccent, size: 9),
                      const SizedBox(width: 6),
                      Text(
                        _isKitchenOpen ? 'Online • Taking Orders' : 'Offline',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              _headerIcon(Icons.insights, 'Analytics', () => context.push('/chef-analytics')),
              _headerIcon(Icons.person_outline, 'Profile', () => context.push('/chef-profile')),
              _headerIcon(Icons.logout, 'Log Out', () => AuthSession.logout(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersTab(List<Map<String, dynamic>> allOrders) {
    final activeOrders = allOrders.where((o) => OrderLifecycle.isKitchenActive(o['status']?.toString())).toList()
      ..sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));

    final filteredOrders = activeOrders.where((o) => _matchesFilter(o, _fulfillmentFilter)).toList();

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: _fulfillmentTabs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final label = _fulfillmentTabs[index];
              final isSelected = _fulfillmentFilter == label;
              final count = label == 'All'
                  ? activeOrders.length
                  : activeOrders.where((o) => _matchesFilter(o, label)).length;

              return GestureDetector(
                onTap: () => setState(() => _fulfillmentFilter = label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primary : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isSelected ? AppTheme.primary : Colors.grey.shade300),
                    boxShadow: isSelected ? AppTheme.brandGlow(opacity: 0.28) : const [],
                  ),
                  child: Text(
                    '$label ($count)',
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppTheme.textMain,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: filteredOrders.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No active orders',
                  message: 'New orders in this queue will appear here in real time.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredOrders.length,
                  itemBuilder: (context, index) => _buildOrderCard(filteredOrders[index]).entrance(index: index),
                ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status']?.toString() ?? 'Pending';
    final isPending = OrderLifecycle.isPendingKitchen(status);
    final isPreparing = status.toLowerCase() == 'preparing';

    final orderId = formatOrderId(order['order_id']?.toString(), order['id'].toString());
    final title = _orderTitle(order);
    final quantity = _orderQuantity(order);
    final totalAmount = _orderTotal(order);
    final instructions = order['special_instructions']?.toString() ?? '';
    final customer = _customerName(order);
    final initial = customer.isNotEmpty ? customer[0].toUpperCase() : 'C';
    final svc = _orderService(order);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(orderId, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.textMuted)),
              const Spacer(),
              AppStatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                child: Text(initial, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$title (x$quantity)',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textMain)),
                    const SizedBox(height: 2),
                    Text(customer, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: AppTheme.radiusMd,
                ),
                child: Text('₹${totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          PillTag(
            label: svc.toDisplayString(),
            icon: svc.isDelivery ? Icons.delivery_dining : Icons.storefront,
            color: AppTheme.info,
          ),
          if (instructions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.12),
                borderRadius: AppTheme.radiusSm,
              ),
              child: Text('Note: $instructions',
                  style: const TextStyle(color: AppTheme.textMain, fontSize: 12, fontStyle: FontStyle.italic)),
            ),
          ],
          const SizedBox(height: 14),
          if (isPending)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: const BorderSide(color: AppTheme.error)),
                    onPressed: () => _cancelCustomerOrder(order),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GradientButton(
                    label: 'Confirm',
                    icon: Icons.check_rounded,
                    gradient: const LinearGradient(colors: [AppTheme.success, Color(0xFF43C478)]),
                    onPressed: () => _advanceKitchen(order),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: GradientButton(
                    label: isPreparing ? 'Ready for Pickup' : 'Start Preparing',
                    icon: isPreparing ? Icons.check_circle_rounded : Icons.soup_kitchen_rounded,
                    gradient: isPreparing
                        ? const LinearGradient(colors: [Color(0xFF00897B), Color(0xFF26A69A)])
                        : AppTheme.primaryGradient,
                    onPressed: () => _advanceKitchen(order),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.cancel_outlined, color: AppTheme.error),
                  tooltip: 'Cancel & Restock',
                  onPressed: () => _cancelCustomerOrder(order),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDispatchTab(List<Map<String, dynamic>> allOrders) {
    final dispatches = allOrders.where((o) => OrderLifecycle.isDispatchQueue(o['status']?.toString())).toList();

    if (dispatches.isEmpty) {
      return const EmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'Nothing to dispatch',
        message: 'Orders ready for pickup or delivery will show up here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: dispatches.length,
      itemBuilder: (context, index) {
        final order = dispatches[index];
        final isOut = OrderLifecycle.normalize(order['status']?.toString()) == 'out for delivery';
        final svc = _orderService(order);
        final dispatchLabel = () {
          if (isOut) return 'Mark Delivered';
          if (svc.usesDeliveryPartner) return 'Release to Delivery Partners';
          if (svc == ServiceType.deliverySelf) return 'Dispatch (Chef-Self)';
          if (svc == ServiceType.dineIn) return 'Mark Dine-In Complete';
          return 'Mark Picked Up';
        }();

        return AppCard(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(formatOrderId(order['order_id']?.toString(), order['id'].toString()),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.textMuted)),
                  const Spacer(),
                  AppStatusBadge(status: order['status']?.toString() ?? ''),
                ],
              ),
              const SizedBox(height: 12),
              Text('${_orderTitle(order)} (x${_orderQuantity(order)})',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Text('${_customerName(order)} • ₹${_orderTotal(order).toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
              const SizedBox(height: 10),
              PillTag(
                label: svc.toDisplayString(),
                icon: svc.isDelivery ? Icons.delivery_dining : Icons.storefront,
                color: isOut ? AppTheme.success : AppTheme.info,
              ),
              const SizedBox(height: 14),
              GradientButton(
                label: dispatchLabel,
                icon: isOut ? Icons.check_rounded : Icons.delivery_dining_rounded,
                gradient: isOut
                    ? const LinearGradient(colors: [AppTheme.success, Color(0xFF43C478)])
                    : const LinearGradient(colors: [Color(0xFF00897B), Color(0xFF26A69A)]),
                onPressed: () => _dispatchOrder(order),
              ),
            ],
          ),
        ).entrance(index: index);
      },
    );
  }

  Widget _buildMenuTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase
          .from('meals')
          .stream(primaryKey: ['id'])
          .eq('chef_id', _currentUserId),
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GradientButton(
              label: 'Publish New Dish',
              icon: Icons.add_rounded,
              onPressed: () => context.push('/chef-publish-meal'),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              const EmptyState(
                icon: Icons.restaurant_menu_rounded,
                title: 'No dishes yet',
                message: 'Publish your first dish to start receiving orders from hungry customers.',
              )
            else
              ...items.asMap().entries.map((entry) {
                final meal = entry.value;
                final isPaused = meal['status']?.toString().toLowerCase() == 'paused';
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: meal['image_url'] != null
                          ? CachedNetworkImage(
                              imageUrl: meal['image_url'].toString(),
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => const AppShimmer(
                                child: ShimmerBox(width: 52, height: 52),
                              ),
                              errorWidget: (_, _, _) => Container(
                                  width: 52, height: 52, color: Colors.grey.shade200, child: const Icon(Icons.fastfood)),
                            )
                          : Container(width: 52, height: 52, color: Colors.grey.shade200, child: const Icon(Icons.fastfood)),
                    ),
                    title: Text(meal['title'] ?? 'Meal', style: TextStyle(fontWeight: FontWeight.bold, decoration: isPaused ? TextDecoration.lineThrough : null)),
                    subtitle: Text('₹${meal['price']} • Stock: ${meal['quantity']} remaining'),
                    trailing: Switch.adaptive(
                      activeThumbColor: AppTheme.primary,
                      value: !isPaused,
                      onChanged: (active) async {
                        await _supabase.from('meals').update({'status': active ? 'Available' : 'Paused'}).eq('id', meal['id']);
                      },
                    ),
                  ),
                ).entrance(index: entry.key);
              }),
          ],
        );
      },
    );
  }

  Widget _buildHistoryTab(List<Map<String, dynamic>> orders) {
    final history = orders.where((o) => (o['status']?.toString().toLowerCase() ?? '') == 'delivered').toList();
    final double revenue = history.fold(0.0, (sum, o) => sum + _orderTotal(o));

    if (history.isEmpty) {
      return const EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'No completed sales yet',
        message: 'Delivered orders will appear here with a running sales total.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            children: [
              const Text('Delivered Order Sales', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              const SizedBox(height: 6),
              Text('₹${revenue.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.success, fontSize: 28, fontWeight: FontWeight.w900)),
              Text('${history.length} completed orders', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
        ).popIn(),
        const SizedBox(height: 16),
        ...history.asMap().entries.map((entry) {
          final h = entry.value;
          return AppCard(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppTheme.success.withValues(alpha: 0.12),
                child: const Icon(Icons.check_circle, color: AppTheme.success),
              ),
              title: Text(_orderTitle(h), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text(formatOrderDate(h['created_at']?.toString() ?? '')),
              trailing: Text('₹${_orderTotal(h).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ).entrance(index: entry.key);
        }),
      ],
    );
  }

  Widget _buildCustomerLeadsTab(List<Map<String, dynamic>> requests) {
    if (requests.isEmpty) {
      return const EmptyState(
        icon: Icons.campaign_outlined,
        title: 'No open leads',
        message: 'Bulk catering broadcasts from customers will show up here for you to claim.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final req = requests[index];
        return AppCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(req['title'] ?? 'Bulk Catering Lead',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  Text('₹${req['budget'] ?? '0'}',
                      style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Quantity: ${req['quantity']} • Needed by: ${req['target_date_time'] ?? 'ASAP'}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 14),
              GradientButton(
                label: 'Claim Lead',
                icon: Icons.handshake_rounded,
                gradient: const LinearGradient(colors: [AppTheme.success, Color(0xFF43C478)]),
                onPressed: () async {
                    final res = await _supabase
                        .from('customer_requests')
                        .update({'status': 'Accepted', 'accepted_chef_id': _currentUserId})
                        .eq('id', req['id'])
                        .eq('status', 'Open')
                        .select();

                    if (context.mounted) {
                      if (res.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lead was already claimed.')));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lead claimed! Coordinate via chat.')));
                      }
                    }
                  },
              ),
            ],
          ),
        ).entrance(index: index);
      },
    );
  }
}