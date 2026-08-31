// lib/screens/chef_hub.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/app_theme.dart';
import '../utils/helpers.dart';
import '../models/cart_enums.dart';
import '../widgets/customer_ui_components.dart';
import '../services/order_repository.dart';
import 'packaging_store_screen.dart';

class ChefDashboardScreen extends StatefulWidget {
  const ChefDashboardScreen({super.key});

  @override
  State<ChefDashboardScreen> createState() => _ChefDashboardScreenState();
}

class _ChefDashboardScreenState extends State<ChefDashboardScreen> {
  final _supabase = Supabase.instance.client;
  final _orderRepo = OrderRepository();

  int _selectedIndex = 0;
  bool _isKitchenOpen = true;
  String _fulfillmentFilter = 'All';

  final List<String> _fulfillmentTabs = const [
    'All',
    'Platform Delivery',
    'Self Delivery',
    'Pickup',
    'Dine-In',
  ];

  String get _currentUserId => _supabase.auth.currentUser?.id ?? '';
  String get _currentUserEmail => _supabase.auth.currentUser?.email ?? 'Chef';

  @override
  void initState() {
    super.initState();
    _loadKitchenStatus();
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
    final svc = ServiceType.fromString(order['service_type']?.toString());
    switch (filter) {
      case 'Platform Delivery':
        return svc == ServiceType.deliveryPlatform;
      case 'Self Delivery':
        return svc == ServiceType.deliverySelf;
      case 'Pickup':
        return svc == ServiceType.pickup;
      case 'Dine-In':
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
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
          Text('Cancel & Restock?', style: TextStyle(color: Colors.white)),
        ]),
        content: const Text(
          'Are you sure you want to cancel this order? It will be refunded, and inventory will be automatically restored.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Order', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final res = await _supabase.rpc('cancel_and_restock_order', params: {
        'p_order_id': order['id'],
        'p_chef_id': _currentUserId,
        'p_reason': 'Cancelled by kitchen',
      });

      if (res?['success'] != true) {
        throw Exception(res?['error'] ?? 'Cancellation rejected by server');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order Cancelled & Inventory Restocked'), backgroundColor: Colors.orange),
        );
      }
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'Chef order cancellation failure');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _advanceOrderStatus(Map<String, dynamic> order, String nextStatus) async {
    try {
      await _orderRepo.updateOrderStatus(
        orderId: order['id'],
        newStatus: nextStatus,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to: $nextStatus'), backgroundColor: Colors.green),
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
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase
            .from('orders')
            .stream(primaryKey: ['id'])
            .eq('chef_id', _currentUserId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text('Connection issue: ${snapshot.error}', style: const TextStyle(color: Colors.grey)),
                    TextButton(onPressed: () => setState(() {}), child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final orders = snapshot.data ?? [];

          final pendingCount = orders.where((o) => (o['status']?.toString().toLowerCase() ?? '') == 'pending chef approval').length;
          final dispatchCount = orders.where((o) {
            final s = o['status']?.toString().toLowerCase() ?? '';
            return s == 'ready for pickup' || s == 'out for delivery';
          }).length;

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
                  backgroundColor: Colors.white,
                  indicatorColor: AppTheme.primary.withValues(alpha: 0.15),
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

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, left: 20, right: 20, bottom: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.primaryGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
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
                      Icon(Icons.circle, color: _isKitchenOpen ? Colors.greenAccent : Colors.redAccent, size: 9),
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
              IconButton(
                icon: const Icon(Icons.insights, color: Colors.white),
                tooltip: 'Analytics',
                onPressed: () => context.push('/chef-analytics'),
              ),
              IconButton(
                icon: const Icon(Icons.person_outline, color: Colors.white),
                tooltip: 'Profile',
                onPressed: () => context.push('/chef-profile'),
              ),
              // --- ADDED LOGOUT BUTTON HERE ---
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                tooltip: 'Log Out',
                onPressed: () async {
                  await _supabase.auth.signOut();
                  if (mounted) context.go('/auth');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersTab(List<Map<String, dynamic>> allOrders) {
    final activeOrders = allOrders.where((o) {
      final s = o['status']?.toString().toLowerCase() ?? '';
      return s == 'pending chef approval' || s == 'confirmed' || s == 'preparing';
    }).toList()
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

              return FilterChip(
                label: Text('$label ($count)'),
                selected: isSelected,
                selectedColor: AppTheme.primary,
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textMain,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onSelected: (_) => setState(() => _fulfillmentFilter = label),
              );
            },
          ),
        ),
        Expanded(
          child: filteredOrders.isEmpty
              ? const Center(child: Text('No active orders in this queue.', style: TextStyle(color: AppTheme.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredOrders.length,
                  itemBuilder: (context, index) => _buildOrderCard(filteredOrders[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status']?.toString() ?? 'Pending';
    final isPending = status.toLowerCase() == 'pending chef approval';
    final isPreparing = status.toLowerCase() == 'preparing';

    final orderId = formatOrderId(order['order_id']?.toString(), order['id'].toString());
    final title = order['title'] ?? 'Meal Order';
    final quantity = int.tryParse(order['quantity']?.toString() ?? '1') ?? 1;
    final totalAmount = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final instructions = order['special_instructions']?.toString() ?? '';

    return AppCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(orderId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
              buildStatusBadge(status),
            ],
          ),
          const SizedBox(height: 8),
          Text('$title (x$quantity)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMain)),
          const SizedBox(height: 4),
          Text('Customer: ${order['customer_name'] ?? 'Guest'} • ₹${totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          if (instructions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text('Note: $instructions', style: TextStyle(color: Colors.amber.shade900, fontSize: 12, fontStyle: FontStyle.italic)),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (isPending) ...[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () => _cancelCustomerOrder(order),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    onPressed: () => _advanceOrderStatus(order, 'Confirmed'),
                    child: const Text('Confirm'),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPreparing ? Colors.teal : AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(isPreparing ? Icons.check_circle : Icons.soup_kitchen, size: 18),
                    label: Text(isPreparing ? 'Ready for Pickup' : 'Start Preparing'),
                    onPressed: () => _advanceOrderStatus(order, isPreparing ? 'Ready for Pickup' : 'Preparing'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                  tooltip: 'Cancel & Restock',
                  onPressed: () => _cancelCustomerOrder(order),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDispatchTab(List<Map<String, dynamic>> allOrders) {
    final dispatches = allOrders.where((o) {
      final s = o['status']?.toString().toLowerCase() ?? '';
      return s == 'ready for pickup' || s == 'out for delivery';
    }).toList();

    if (dispatches.isEmpty) {
      return const Center(child: Text('No orders waiting for pickup or delivery.', style: TextStyle(color: AppTheme.textMuted)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: dispatches.length,
      itemBuilder: (context, index) {
        final order = dispatches[index];
        final isOut = (order['status']?.toString().toLowerCase() ?? '') == 'out for delivery';
        final svc = ServiceType.fromString(order['service_type']?.toString());

        return AppCard(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatOrderId(order['order_id']?.toString(), order['id'].toString()),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                  buildStatusBadge(order['status']),
                ],
              ),
              const SizedBox(height: 8),
              Text('${order['title']} (x${order['quantity']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              Text('Method: ${svc.toDisplayString()}', style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isOut ? Colors.green : Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(isOut ? Icons.check : Icons.delivery_dining),
                  label: Text(isOut ? 'Mark Delivered' : 'Dispatch Order'),
                  onPressed: () => _advanceOrderStatus(order, isOut ? 'Delivered' : 'Out for Delivery'),
                ),
              ),
            ],
          ),
        );
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
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Publish New Dish', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => context.push('/chef-publish-meal'),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No menu items active.')))
            else
              ...items.map((meal) {
                final isPaused = meal['status']?.toString().toLowerCase() == 'paused';
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: meal['image_url'] != null
                          ? Image.network(meal['image_url'], width: 50, height: 50, fit: BoxFit.cover)
                          : Container(width: 50, height: 50, color: Colors.grey.shade200, child: const Icon(Icons.fastfood)),
                    ),
                    title: Text(meal['title'] ?? 'Meal', style: TextStyle(fontWeight: FontWeight.bold, decoration: isPaused ? TextDecoration.lineThrough : null)),
                    subtitle: Text('₹${meal['price']} • Stock: ${meal['quantity']} remaining'),
                    trailing: Switch.adaptive(
                      activeColor: AppTheme.primary,
                      value: !isPaused,
                      onChanged: (active) async {
                        await _supabase.from('meals').update({'status': active ? 'Available' : 'Paused'}).eq('id', meal['id']);
                      },
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Widget _buildHistoryTab(List<Map<String, dynamic>> orders) {
    final history = orders.where((o) => (o['status']?.toString().toLowerCase() ?? '') == 'delivered').toList();
    final double revenue = history.fold(0.0, (sum, o) => sum + ((o['total_amount'] as num?)?.toDouble() ?? 0.0));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            children: [
              const Text('Delivered Order Sales', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              const SizedBox(height: 6),
              Text('₹${revenue.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontSize: 26, fontWeight: FontWeight.w900)),
              Text('${history.length} completed orders', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...history.map((h) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(h['title'] ?? 'Order', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text(formatOrderDate(h['created_at']?.toString() ?? '')),
              trailing: Text('₹${(h['total_amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            )),
      ],
    );
  }

  Widget _buildCustomerLeadsTab(List<Map<String, dynamic>> requests) {
    if (requests.isEmpty) {
      return const Center(child: Text('No broadcast requests currently open.', style: TextStyle(color: AppTheme.textMuted)));
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(req['title'] ?? 'Bulk Catering Lead', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('₹${req['budget'] ?? '0'}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Quantity: ${req['quantity']} • Needed by: ${req['target_date_time'] ?? 'ASAP'}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
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
                  child: const Text('Claim Lead'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}