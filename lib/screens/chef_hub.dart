// lib/screens/chef_hub.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/helpers.dart';
import '../utils/fssai_certificate_scan.dart';
import '../utils/network.dart';
import '../utils/meal_nutrition.dart';
import '../models/cart_enums.dart';
import '../widgets/customer_ui_components.dart';
import '../widgets/app_widgets.dart';
import '../widgets/app_status_badge.dart';
import '../widgets/order_slot_banner.dart';
import '../models/app_role.dart';
import '../services/order_lifecycle.dart';
import '../services/auth_session.dart';
import '../services/alert_service.dart';
import '../services/invoice_pdf_service.dart';
import '../services/kitchen_media.dart';
import '../widgets/chef_boost_sheet.dart';
import '../widgets/kyc_reminder_banner.dart';
import '../widgets/chef_onboarding_coach.dart';
import '../widgets/diner_storefront.dart';
import 'packaging_store_screen.dart';
import 'chef_publish_meal_screen.dart';
import 'chef_profile_screen.dart';
import 'notifications_inbox_screen.dart';

class ChefDashboardScreen extends StatefulWidget {
  final int initialTab;

  const ChefDashboardScreen({super.key, this.initialTab = 0});

  @override
  State<ChefDashboardScreen> createState() => _ChefDashboardScreenState();
}

class _ChefDashboardScreenState extends State<ChefDashboardScreen> {
  final _supabase = Supabase.instance.client;
  final _orderLifecycle = OrderLifecycle();

  late int _selectedIndex = widget.initialTab == 5 ? 1 : widget.initialTab;
  bool _isKitchenOpen = true;
  String _fulfillmentFilter = 'All';
  String _historyFilter = 'Delivered';
  String _menuFilter = 'Active'; // Active | History
  late int _ordersStage = widget.initialTab == 5 ? 2 : 0; // 0 new, 1 in progress, 2 dispatch, 3 completed
  final Set<String> _autoArchivedMealIds = {};
  bool _isPlatformOps = false;

  final List<String> _fulfillmentTabs = const [
    'All',
    'Delivery Partner',
    'Chef-Self',
    'Customer Pickup',
    'Dine In',
  ];

  String get _currentUserId => _supabase.auth.currentUser?.id ?? '';
  String get _currentUserEmail => _supabase.auth.currentUser?.email ?? 'Chef';
  Map<String, dynamic>? _chefPin;
  Map<String, dynamic> _chefProfile = {};
  bool _hasActiveDish = false;

  /// Stable stream instances so rebuilds do not recreate realtime subscriptions.
  Stream<List<Map<String, dynamic>>>? _ordersStream;
  Stream<List<Map<String, dynamic>>>? _requestsStream;
  Stream<List<Map<String, dynamic>>>? _myQuotesStream;
  RealtimeChannel? _kitchenChannel;

  // Resolved customer_id -> display name cache (orders only store customer_id).
  final Map<String, String> _customerNameCache = {};
  final Set<String> _customerNameLoading = {};

  @override
  void initState() {
    super.initState();
    unawaited(AuthSession.ensureHubRole(context, AppRole.chef));
    _ensureHubStreams();
    _loadKitchenStatus();
    _subscribeKitchenStatus();
    _loadChefPin();
    unawaited(_loadActiveDishCount());
    unawaited(_loadOpsAccess());
  }

  @override
  void dispose() {
    _kitchenChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadOpsAccess() async {
    final ops = await AuthSession.isPlatformOps();
    if (mounted) setState(() => _isPlatformOps = ops);
  }

  void _ensureHubStreams() {
    final uid = _currentUserId;
    if (uid.isEmpty || _ordersStream != null) return;
    _ordersStream = _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('chef_id', uid)
        .map((rows) => rows.map(chefFacingOrderRow).toList());
    _requestsStream = _supabase.from('customer_requests').stream(primaryKey: ['id']);
    _myQuotesStream =
        _supabase.from('customer_request_quotes').stream(primaryKey: ['id']).eq('chef_id', uid);
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

  String _orderUpdateError(Object error) {
    final text = error.toString();
    if (text.contains('delivered_at') || text.contains('PGRST204')) {
      return 'Could not mark this order delivered. Try again.';
    }
    return 'Could not update this order. Try again.';
  }

  String _orderTitle(Map<String, dynamic> order) {
    final items = _parseItems(order['items']);
    if (items.isEmpty) return order['title']?.toString() ?? 'Meal Order';
    final first = items.first;
    final base = first['title']?.toString() ?? 'Meal Order';
    final tag = orderLineSpecialtyTag(first);
    final titled = tag == null ? base : '$tag · $base';
    return items.length > 1 ? '$titled +${items.length - 1} more' : titled;
  }

  int _orderQuantity(Map<String, dynamic> order) {
    final items = _parseItems(order['items']);
    if (items.isEmpty) return int.tryParse(order['quantity']?.toString() ?? '1') ?? 1;
    return items.fold<int>(
        0, (sum, it) => sum + (int.tryParse(it['quantity']?.toString() ?? '1') ?? 1));
  }

  String _deliveryAddress(Map<String, dynamic> order) {
    return orderDropoffAddress(order, items: _parseItems(order['items']));
  }

  void _openChefDeliveryMap(Map<String, dynamic> order) {
    final address = _deliveryAddress(order);
    context.push('/tracking', extra: {
      'order': {
        ...order,
        if (address.isNotEmpty) 'delivery_address': address,
      },
      'isDriver': true,
    });
  }

  Future<void> _callCustomer(String customerId) async {
    if (customerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No customer contact on this order.'), backgroundColor: Colors.orange),
      );
      return;
    }
    try {
      final userDoc = await _supabase.from('users').select('phone').eq('id', customerId).maybeSingle();
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

  void _openOrderChat(Map<String, dynamic> order) {
    if (!orderAllowsPartyChat(order['status']?.toString())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat closes after delivery. Ask the diner to contact HotPotChef support for issues.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final items = _parseItems(order['items'] ?? order['cart_items']);
    final roomId = orderChatRoomId(order, items: items);
    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat is not available for this order.'), backgroundColor: Colors.orange),
      );
      return;
    }
    final label = formatOrderId(order['order_id']?.toString(), order['id'].toString());
    context.push(chatPath(
      roomId,
      roomName: 'Order $label',
      otherUserId: order['customer_id']?.toString(),
      memberIds: orderChatMemberIds(order),
      isGroup: true,
    ));
  }

  Widget _orderContactActions(Map<String, dynamic> order) {
    final customerId = order['customer_id']?.toString() ?? '';
    final status = order['status']?.toString();
    final chatOpen = orderAllowsPartyChat(status);
    final callOpen = orderAllowsPhoneCall(status);
    return Row(
      children: [
        AppIconAction(
          icon: Icons.chat_bubble_outline,
          tooltip: chatOpen ? 'Chat' : 'Chat closed',
          onPressed: chatOpen ? () => _openOrderChat(order) : null,
        ),
        const SizedBox(width: 8),
        AppIconAction(
          icon: Icons.phone_outlined,
          tooltip: callOpen ? 'Call' : 'Chat preferred',
          onPressed: callOpen
              ? () => _callCustomer(customerId)
              : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Phone is for active prep/delivery. Prefer Chat for coordination.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                },
        ),
      ],
    );
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

  Future<void> _loadChefPin() async {
    if (_currentUserId.isEmpty) return;
    try {
      final row = await _supabase
          .from('users')
          .select('lat, lng, latitude, longitude, fssai_number, fssai_proof_url, fssai_verification_status, fssai_valid_until')
          .eq('id', _currentUserId)
          .maybeSingle();
      if (row != null && mounted) {
        setState(() {
          _chefPin = row;
          _chefProfile = Map<String, dynamic>.from(row);
        });
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to load chef kitchen pin');
    }
  }

  Future<void> _loadActiveDishCount() async {
    if (_currentUserId.isEmpty) return;
    try {
      final rows = await _supabase
          .from('meals')
          .select('id, status, time_slot')
          .eq('chef_id', _currentUserId);
      final list = List<Map<String, dynamic>>.from(rows);
      final active = list.where(isChefMenuActiveMeal).isNotEmpty;
      if (mounted) setState(() => _hasActiveDish = active);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to load chef active dishes');
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
          setState(() {
            _isKitchenOpen = res['is_open'] == true;
          });
        }
    } catch (e) {
      debugPrint('Failed to load kitchen status: $e');
    }
  }

  void _subscribeKitchenStatus() {
    if (_currentUserId.isEmpty) return;
    _kitchenChannel?.unsubscribe();
    _kitchenChannel = _supabase
        .channel('public:chef_profiles:$_currentUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chef_profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: _currentUserId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (!mounted || record.isEmpty) return;
            setState(() {
              if (record.containsKey('is_open')) {
                _isKitchenOpen = record['is_open'] == true;
              }
            });
          },
        )
        .subscribe();
  }

  Future<void> _toggleKitchenStatus() async {
    final nextState = !_isKitchenOpen;
    if (!nextState) {
      final proceed = await _confirmGoOffline();
      if (proceed != true || !mounted) return;
    }

    setState(() => _isKitchenOpen = nextState);

    try {
      await _supabase.from('chef_profiles').upsert({
        'user_id': _currentUserId,
        'is_open': nextState,
        if (!nextState) 'is_live': false,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (nextState) {
        AlertService.notifyKitchenLive(chefId: _currentUserId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextState
                ? 'Kitchen is online. Customers can see your dishes again.'
                : 'Kitchen is offline for new orders. Finish or cancel orders you already accepted.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to update kitchen status');
      setState(() => _isKitchenOpen = !nextState);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update kitchen availability. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool?> _confirmGoOffline() async {
    var unfulfilled = 0;
    try {
      final rows = await _supabase
          .from('orders')
          .select('status')
          .eq('chef_id', _currentUserId);
      unfulfilled = rows.where((row) => OrderLifecycle.isUnfulfilledKitchenWork(row['status']?.toString())).length;
    } catch (_) {}

    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go offline?'),
        content: Text(
          unfulfilled > 0
              ? 'You have $unfulfilled accepted order${unfulfilled == 1 ? '' : 's'} still in progress. New customers will not see your dishes, but you still need to finish or cancel those orders.'
              : 'New customers will not see your dishes until you come back online. You can still finish any order you already accepted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay online')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Go offline')),
        ],
      ),
    );
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

  Future<String?> _capturePackedPhoto(Map<String, dynamic> order) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Packed box photo'),
        content: const Text(
          'Take a photo of the sealed box so the diner can see their order is packed before it leaves the kitchen.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open camera')),
        ],
      ),
    );
    if (proceed != true || !mounted) return null;
    try {
      return await capturePackedBoxPhoto(orderId: order['id'].toString());
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Packed box photo upload failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the packed-box photo. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<void> _advanceKitchen(Map<String, dynamic> order) async {
    try {
      final current = order['status']?.toString() ?? '';
      final next = OrderLifecycle.nextKitchenStatus(current);
      if (next == OrderStatus.preparing && !canChefStartPreparing(order)) {
        throw Exception(chefPrepGateHint(order).isEmpty
            ? 'Too early to start preparing. Wait until ${chefPrepEarliestWindowLabel()} before the requested time.'
            : chefPrepGateHint(order));
      }
      String? packedUrl;
      if (next == OrderStatus.readyForPickup) {
        packedUrl = await _capturePackedPhoto(order);
        if (packedUrl == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Take a packed-box photo to mark this order ready.')),
            );
          }
          return;
        }
        final typed = (order['order_type'] ?? order['service_type'] ?? '').toString().trim();
        if (typed.isEmpty) {
          try {
            await _supabase.from('orders').update({
              'order_type': _orderService(order).toDisplayString(),
            }).eq('id', order['id'].toString());
          } catch (_) {}
        }
      }
      await _orderLifecycle.advanceKitchen(
        orderId: order['id'].toString(),
        currentStatus: current,
        dispatchPhotoUrl: packedUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to: $next'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_orderUpdateError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _attachDispatchPhoto(Map<String, dynamic> order) async {
    final url = await _capturePackedPhoto(order);
    if (url == null || !mounted) return;
    try {
      await _supabase.from('orders').update({
        'dispatch_photo_url': url,
        'dispatch_photo_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', order['id'].toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Packed-box photo added. The diner can see it now.')),
        );
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to attach dispatch photo');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not attach the packed-box photo. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _dispatchOrder(Map<String, dynamic> order) async {
    try {
      final current = order['status']?.toString() ?? '';
      final svc = ServiceType.fromString(order['order_type']?.toString() ?? order['service_type']?.toString());
      if (svc.usesDeliveryPartner) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Delivery partners mark partner orders delivered.'),
              backgroundColor: Colors.teal,
            ),
          );
        }
        return;
      }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_orderUpdateError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- Main Build ---

  @override
  Widget build(BuildContext context) {
    if (_currentUserId.isEmpty) {
      return const Scaffold(body: Center(child: Text('Authentication required.')));
    }
    _ensureHubStreams();

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
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
            return Scaffold(
              backgroundColor: AppTheme.canvasOf(context),
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
              backgroundColor: AppTheme.canvasOf(context),
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

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _requestsStream,
            builder: (context, reqSnapshot) {
              final visibleLeads = (reqSnapshot.data ?? []).where((req) {
                if (!_isVisibleLead(req)) return false;
                if (_leadStatus(req) != 'open') return true;
                return isCateringLeadVisibleToChef(
                  req,
                  chefId: _currentUserId,
                  chefPin: _chefPin,
                );
              }).toList()
                ..sort((a, b) {
                  final da = cateringLeadDistanceKm(a, _chefPin) ?? 9999;
                  final db = cateringLeadDistanceKm(b, _chefPin) ?? 9999;
                  return da.compareTo(db);
                });
              final openLeadsCount = visibleLeads.where((req) => _leadStatus(req) == 'open').length;

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: _myQuotesStream ?? Stream.value(const <Map<String, dynamic>>[]),
                builder: (context, quoteSnapshot) {
                  final myQuotes = <String, Map<String, dynamic>>{};
                  if (!quoteSnapshot.hasError) {
                    for (final row in quoteSnapshot.data ?? const <Map<String, dynamic>>[]) {
                      final rid = row['request_id']?.toString() ?? '';
                      if (rid.isEmpty) continue;
                      myQuotes[rid] = row;
                    }
                  }

              final List<Widget> tabs = [
                _buildHomeTab(orders, pendingCount: pendingCount),
                _buildOrdersWorkspace(orders),
                const ChefProfileScreen(embedded: true),
                const NotificationsInboxScreen(embedded: true, partnerInbox: true),
                _buildMenuTab(),
                _buildDispatchTab(orders),
                _buildHistoryTab(orders),
                _buildCustomerLeadsTab(visibleLeads, myQuotes: myQuotes),
                const PackagingStoreScreen(),
              ];

              return Stack(
                children: [
                  Scaffold(
                backgroundColor: AppTheme.canvasOf(context),
                body: Stack(
                  children: [
                    Column(
                  children: [
                    if (_selectedIndex != 2 && _selectedIndex != 3) _buildHeader(),
                    if (_selectedIndex == 0) const KycReminderBanner(profilePath: '/chef-profile'),
                    if (_selectedIndex == 0)
                    ChefSetupStrip(
                      profile: _chefProfile,
                      isKitchenOpen: _isKitchenOpen,
                      hasActiveDish: _hasActiveDish,
                      onOpenProfile: () => setState(() => _selectedIndex = 2),
                      onPublish: () => context.push('/chef-publish-meal'),
                      onGoOnline: () {
                        if (!_isKitchenOpen) unawaited(_toggleKitchenStatus());
                      },
                    ),
                    if (_selectedIndex >= 4)
                      Material(
                        color: AppTheme.surfaceOf(context),
                        child: ListTile(
                          dense: true,
                          leading: IconButton(
                            tooltip: 'Back to home',
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => setState(() => _selectedIndex = 0),
                          ),
                          title: Text(
                            switch (_selectedIndex) {
                              4 => 'Menu',
                              5 => 'Dispatch',
                              6 => 'Kitchen take-home',
                              7 => openLeadsCount > 0 ? 'Catering leads ($openLeadsCount)' : 'Catering leads',
                              _ => 'Packaging supplies',
                            },
                            style: AppTheme.listTitleOf(context),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: hubDockBodyGap(context)),
                        child: HubTabSwitcher(
                          index: _selectedIndex,
                          children: tabs,
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
                        selectedIndex: _selectedIndex > 3 ? 0 : _selectedIndex,
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
                            badgeCount: pendingCount,
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
                  ChefOnboardingCoach(
                    onOpenProfile: () => setState(() => _selectedIndex = 2),
                    onPublish: () => context.push('/chef-publish-meal'),
                  ),
                ],
              );
                },
              );
            },
          );
        },
      ),
    );
  }

  // --- Sub-Components ---

  Widget _buildHeader() {
    final top = MediaQuery.of(context).padding.top;
    final overflow = _selectedIndex >= 4;
    return Container(
      color: AppTheme.canvasOf(context),
      padding: EdgeInsets.fromLTRB(16, top + 8, 16, 8),
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
              child: Text(
                overflow ? '' : 'Chef Orders',
                style: AppTheme.sectionTitleOf(context),
              ),
            ),
          IconButton(
            tooltip: 'Kitchen take-home',
            onPressed: () => setState(() => _selectedIndex = 6),
            icon: const Icon(Icons.payments_outlined),
          ),
          IconButton(
            tooltip: 'Order chats',
            onPressed: () => context.push('/chats'),
            icon: const Icon(Icons.forum_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              switch (value) {
                case 'leads':
                  setState(() => _selectedIndex = 7);
                case 'supplies':
                  setState(() => _selectedIndex = 8);
                case 'menu':
                  setState(() => _selectedIndex = 4);
                case 'ads':
                  context.push('/chef-advertise');
                case 'academy':
                  context.push('/chef-academy');
                case 'profile':
                  setState(() => _selectedIndex = 2);
                case 'ops':
                  context.go('/platform-ops');
                case 'logout':
                  AuthSession.confirmSignOut(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'menu', child: Text('Menu')),
              const PopupMenuItem(value: 'leads', child: Text('Catering leads')),
              const PopupMenuItem(value: 'supplies', child: Text('Packaging supplies')),
              const PopupMenuItem(value: 'ads', child: Text('Refer brand')),
              const PopupMenuItem(value: 'academy', child: Text('Academy')),
              if (_isPlatformOps) const PopupMenuItem(value: 'ops', child: Text('Admin')),
              const PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab(List<Map<String, dynamic>> orders, {required int pendingCount}) {
    final verified = dinerFssaiIsVerified(
      _chefProfile['fssai_verification_status']?.toString(),
      validUntil: parseStoredFssaiValidUntil(_chefProfile['fssai_valid_until']),
    );
    final today = DateTime.now();
    final profit = orders.where((order) {
      final status = order['status']?.toString().toLowerCase() ?? '';
      if (!status.contains('delivered') && !status.contains('completed')) return false;
      final at = DateTime.tryParse(order['delivered_at']?.toString() ?? order['updated_at']?.toString() ?? '');
      if (at == null) return false;
      final local = at.toLocal();
      return local.year == today.year && local.month == today.month && local.day == today.day;
    }).fold<double>(0, (sum, order) => sum + chefPayoutForOrder(order).chefPayout);
    final rawName = _chefProfile['name']?.toString() ??
        _chefProfile['full_name']?.toString() ??
        _currentUserEmail.split('@').first;
    final firstName = rawName.trim().isEmpty ? 'Chef' : rawName.trim().split(' ').first;
    final city = [
      _chefProfile['city']?.toString(),
      _chefProfile['local_kitchen_name']?.toString(),
    ].where((v) => v != null && v.trim().isNotEmpty).cast<String>().join(' · ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome back, $firstName!', style: AppTheme.sectionTitleOf(context).copyWith(fontSize: 22)),
                  const SizedBox(height: 4),
                  Text(
                    city.isEmpty
                        ? (verified ? 'FSSAI verified home kitchen' : 'Complete FSSAI to go fully live')
                        : city,
                    style: AppTheme.caption,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Already known for recipes on YouTube, Instagram, or Facebook? Link those pages on Profile so diners recognize you here.',
                    style: AppTheme.microOf(context),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Switch.adaptive(
                  value: _isKitchenOpen,
                  activeThumbColor: AppTheme.live,
                  onChanged: (_) => _toggleKitchenStatus(),
                ),
                Text(
                  _isKitchenOpen ? 'Go Offline' : 'Go Online',
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
              child: _chefStatCard('New Orders', pendingCount.toString(), onTap: () {
                setState(() {
                  _selectedIndex = 1;
                  _ordersStage = 0;
                });
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _chefStatCard(
                'Total Earnings',
                '₹${profit.toStringAsFixed(0)}',
                onTap: () {
                  setState(() {
                    _selectedIndex = 1;
                    _ordersStage = 3;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('Quick Chef Tools', style: AppTheme.homeSectionLabelOf(context)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _chefToolCard(
                icon: Icons.cloud_upload_outlined,
                label: 'Upload Menu',
                onTap: () => context.push('/chef-publish-meal'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _chefToolCard(
                icon: Icons.restaurant_menu_rounded,
                label: 'Active Dishes',
                onTap: () => setState(() {
                  _selectedIndex = 4;
                  _menuFilter = 'Active';
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chefToolCard({required IconData icon, required String label, required VoidCallback onTap}) {
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

  Widget _chefStatCard(String label, String value, {VoidCallback? onTap}) {
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

  Widget _buildOrdersWorkspace(List<Map<String, dynamic>> allOrders) {
    final newOrders = allOrders.where((o) => OrderLifecycle.isPendingKitchen(o['status']?.toString())).toList()
      ..sort(compareKitchenOrdersBySlot);
    final inProgress = allOrders.where((o) {
      final status = o['status']?.toString();
      return OrderLifecycle.isKitchenActive(status) && !OrderLifecycle.isPendingKitchen(status);
    }).toList()
      ..sort(compareKitchenOrdersBySlot);
    final dispatch = allOrders.where((o) => OrderLifecycle.isDispatchQueue(o['status']?.toString())).toList()
      ..sort(compareKitchenOrdersBySlot);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: DinerSegmentBar(
            labels: [
              'New (${newOrders.length})',
              'In Progress (${inProgress.length})',
              'Dispatch (${dispatch.length})',
              'Completed',
            ],
            index: _ordersStage,
            onChanged: (index) => setState(() => _ordersStage = index),
          ),
        ),
        Expanded(
          child: switch (_ordersStage) {
            2 => _buildDispatchTab(allOrders),
            3 => _buildHistoryTab(allOrders),
            _ => ( _ordersStage == 0 ? newOrders : inProgress).isEmpty
                ? EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: _ordersStage == 0 ? 'No new orders' : 'Nothing in progress',
                    message: _ordersStage == 0
                        ? 'New diner plates will land here for Accept or Decline.'
                        : 'Accepted plates you are cooking show here.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    itemCount: (_ordersStage == 0 ? newOrders : inProgress).length,
                    itemBuilder: (context, index) {
                      final order = (_ordersStage == 0 ? newOrders : inProgress)[index];
                      return _buildOrderCard(order).entrance(index: index);
                    },
                  ),
          },
        ),
      ],
    );
  }

  Widget _buildReadyPickupCard(Map<String, dynamic> order) {
    final customer = _customerName(order);
    return AppCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                formatOrderId(order['order_id']?.toString(), order['id'].toString()),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.textMuted),
              ),
              const Spacer(),
              Text(
                formatRupees(_orderTotal(order)),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(customer, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.onSurfaceOf(context))),
          const SizedBox(height: 4),
          Text(
            '${_orderQuantity(order)} × ${_orderTitle(order)}',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _dispatchOrder(order),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.live,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Ready for Pickup', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  // Fulfillment-filtered kitchen queue; kept for dispatch-style filters from More.
  // ignore: unused_element
  Widget _buildOrdersTab(List<Map<String, dynamic>> allOrders) {
    final activeOrders = allOrders.where((o) => OrderLifecycle.isKitchenActive(o['status']?.toString())).toList()
      ..sort(compareKitchenOrdersBySlot);

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
                    color: isSelected ? AppTheme.primary : AppTheme.surfaceOf(context),
                    borderRadius: AppTheme.radiusXl,
                    border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.hairlineOf(context)),
                    boxShadow: isSelected ? AppTheme.brandGlow(opacity: 0.28) : const [],
                  ),
                  child: Text(
                    '$label ($count)',
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppTheme.onSurfaceOf(context),
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
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
    final instructions = kitchenFacingOrderNotes(order['special_instructions']?.toString());
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
              InkWell(
                onTap: () => copyOrderNumber(context, orderId),
                child: Text(orderId, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.textMuted)),
              ),
              const Spacer(),
              Text(
                formatRupees(_orderTotal(order)),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                child: Text(initial, style: const TextStyle(color: AppTheme.link, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.onSurfaceOf(context))),
                    const SizedBox(height: 2),
                    Text('$quantity × $title', style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          PillTag(
            label: svc.toDisplayString(),
            icon: svc.isDelivery ? Icons.delivery_dining : Icons.storefront,
            color: AppTheme.info,
          ),
          const SizedBox(height: 10),
          OrderSlotBanner(
            order: order,
            hint: isPending || isPreparing ? null : chefPrepGateHint(order),
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
                  style: TextStyle(color: AppTheme.onSurfaceOf(context), fontSize: 12, fontStyle: FontStyle.italic)),
            ),
          ],
          const SizedBox(height: 14),
          _orderContactActions(order),
          const SizedBox(height: 10),
          if (isPending)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: const BorderSide(color: AppTheme.error)),
                    onPressed: () => _cancelCustomerOrder(order),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GradientButton(
                    label: 'Accept Order',
                    icon: Icons.check_rounded,
                    gradient: const LinearGradient(colors: [AppTheme.success, Color(0xFF43C478)]),
                    onPressed: () => _advanceKitchen(order),
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ChefPrepAdvanceButton(
                        order: order,
                        isPreparing: isPreparing,
                        onAdvance: () => _advanceKitchen(order),
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
                if (!isPreparing && chefPrepGateHint(order).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(chefPrepGateHint(order), style: AppTheme.caption),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: dispatches.length,
      itemBuilder: (context, index) {
        final order = dispatches[index];
        final status = order['status']?.toString() ?? '';
        final isOut = OrderLifecycle.normalize(status) == 'out for delivery';
        final driverAssigned = OrderLifecycle.normalize(status).contains('assigned');
        final svc = _orderService(order);
        final dispatchLabel = () {
          if (isOut) return 'Mark Delivered';
          if (svc.usesDeliveryPartner) return 'Waiting for a delivery partner';
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
              Text(
                '${_customerName(order)} • diner paid ${formatRupees(_orderTotal(order))} · payout ${formatRupees(chefPayoutForOrder(order).chefPayout)}',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
              const SizedBox(height: 10),
              PillTag(
                label: svc.toDisplayString(),
                icon: svc.isDelivery ? Icons.delivery_dining : Icons.storefront,
                color: isOut ? AppTheme.success : AppTheme.info,
              ),
              const SizedBox(height: 10),
              OrderSlotBanner(order: order),
              if (hasDispatchPhoto(order)) ...[
                const SizedBox(height: 10),
                DispatchPackedPhoto(url: orderDispatchPhotoUrl(order)!, height: 120),
              ] else ...[
                const SizedBox(height: 10),
                AppIconAction(
                  icon: Icons.photo_camera_outlined,
                  tooltip: 'Add packed-box photo',
                  onPressed: () => _attachDispatchPhoto(order),
                ),
              ],
              if (svc == ServiceType.deliverySelf) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on, size: 16, color: Colors.redAccent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _deliveryAddress(order).isEmpty
                            ? 'Delivery address not saved for this order'
                            : _deliveryAddress(order),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceOf(context)),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              _orderContactActions(order),
              const SizedBox(height: 10),
              if (svc == ServiceType.deliverySelf)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.navigation, size: 16),
                      label: const Text('Navigate'),
                      onPressed: () => _openChefDeliveryMap(order),
                    ),
                    const SizedBox(height: 10),
                    GradientButton(
                      label: dispatchLabel,
                      icon: isOut ? Icons.check_rounded : Icons.delivery_dining_rounded,
                      gradient: isOut
                          ? const LinearGradient(colors: [AppTheme.success, Color(0xFF43C478)])
                          : const LinearGradient(colors: [Color(0xFF00897B), Color(0xFF26A69A)]),
                      onPressed: () => _dispatchOrder(order),
                    ),
                  ],
                )
              else if (svc.usesDeliveryPartner)
                Text(
                  isOut
                      ? 'A delivery partner is on the way. They mark this order delivered.'
                      : driverAssigned
                          ? 'A delivery partner has this order. They will start and complete the run.'
                          : ((order['order_type']?.toString() ?? '').trim().isEmpty)
                              ? 'Drivers only see Delivery Partner jobs. Confirm the service type is Delivery Partner, then mark Ready for Pickup.'
                              : 'Waiting for a delivery partner. Drivers see this job after you mark it Ready for Pickup.',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.35),
                )
              else
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

  void _openMealEditor(Map<String, dynamic> meal) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChefPublishMealScreen(
          existingMeal: Map<String, dynamic>.from(meal),
        ),
      ),
    );
  }

  Future<void> _quickRestockMeal(Map<String, dynamic> meal) async {
    final id = meal['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final current = int.tryParse(meal['quantity']?.toString() ?? '0') ?? 0;
    final controller = TextEditingController(text: current.toString());
    final next = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Restock portions'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(meal['title']?.toString() ?? 'Dish', style: AppTheme.caption),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Portions on the menu'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final n = (int.tryParse(controller.text.trim()) ?? current) + 5;
                controller.text = n.toString();
              },
              child: const Text('+5'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text.trim()) ?? current),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (next == null || next < 0 || !mounted) return;
    try {
      await _supabase.from('meals').update({
        'quantity': next,
        if (next > 0 && meal['status']?.toString().toLowerCase() == 'paused') 'status': 'Available',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(next == 0 ? 'Sold out — diners cannot buy.' : 'Stock set to $next portions.')),
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Quick restock failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(networkErrorMessage(e)), backgroundColor: Colors.red),
      );
    }
  }

  void _duplicateMeal(Map<String, dynamic> meal) {
    final copy = Map<String, dynamic>.from(meal);
    copy.remove('id');
    copy['title'] = '${meal['title'] ?? 'Meal'} (copy)';
    copy['status'] = 'Paused';
    _openMealEditor(copy);
  }

  Future<void> _archiveMeal(Map<String, dynamic> meal, {required String reason}) async {
    final id = meal['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      try {
        await _supabase.from('meals').update({
          'status': 'Archived',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', id);
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST204') rethrow;
        await _supabase.from('meals').update({'status': 'Archived'}).eq('id', id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason == 'expired' ? 'Expired dish moved to History.' : 'Dish removed from Menu.')),
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Archive meal failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove dish: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confirmDeleteMeal(Map<String, dynamic> meal) async {
    final title = meal['title']?.toString() ?? 'this dish';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove dish?'),
        content: Text(
          '“$title” will leave Active Menu and move to History. Past orders keep their receipts.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await _archiveMeal(meal, reason: 'delete');
  }

  String get _chefDisplayName {
    final user = _supabase.auth.currentUser;
    return user?.userMetadata?['name']?.toString() ??
        user?.userMetadata?['full_name']?.toString() ??
        _currentUserEmail.split('@').first;
  }

  Widget _buildMenuTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase
          .from('meals')
          .stream(primaryKey: ['id'])
          .eq('chef_id', _currentUserId),
      builder: (context, snapshot) {
        final all = List<Map<String, dynamic>>.from(snapshot.data ?? const []);
        all.sort((a, b) => (b['updated_at'] ?? b['created_at'] ?? '').toString().compareTo(
              (a['updated_at'] ?? a['created_at'] ?? '').toString(),
            ));

        final active = all.where(isChefMenuActiveMeal).toList();
        final history = all.where((m) => !isChefMenuActiveMeal(m)).toList();
        final showing = _menuFilter == 'History' ? history : active;

        // Soft-clean: archive expired or incomplete dishes still marked Available/Paused.
        for (final meal in all) {
          if (isChefMealArchived(meal)) continue;
          if (!isPublishedMealExpired(meal) && !mealFailsCurrentCatalogRequirements(meal)) {
            continue;
          }
          final id = meal['id']?.toString();
          if (id == null || id.isEmpty || !_autoArchivedMealIds.add(id)) continue;
          unawaited(
            _supabase.from('meals').update({
              'status': 'Archived',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }).eq('id', id),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  for (final label in const ['Active', 'History']) ...[
                    if (label == 'History') const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _menuFilter = label),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _menuFilter == label ? AppTheme.primary : AppTheme.surfaceOf(context),
                            borderRadius: AppTheme.radiusMd,
                            border: Border.all(
                              color: _menuFilter == label ? AppTheme.primary : AppTheme.hairlineOf(context),
                            ),
                          ),
                          child: Text(
                            label == 'Active' ? 'Active (${active.length})' : 'History (${history.length})',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _menuFilter == label ? Colors.white : AppTheme.onSurfaceOf(context),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  if (_menuFilter == 'Active') ...[
                    GradientButton(
                      label: 'Publish New Dish',
                      icon: Icons.add_rounded,
                      onPressed: () => context.push('/chef-publish-meal'),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: AppTheme.radiusMd,
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        'Keep HotPotChef diners on the app — in-app pay unlocks refunds, coins, and Support. Moving orders to WhatsApp/UPI can pause boosts.',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.35, color: AppTheme.onSurfaceOf(context)),
                      ),
                    ),
                    if (!_isKitchenOpen) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.12),
                          borderRadius: AppTheme.radiusMd,
                          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          'Kitchen is offline for new orders. Dishes are hidden on Home. Finish or cancel orders you already accepted.',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceOf(context)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ] else ...[
                    Text(
                      'All dishes you have published — expired windows and removed plates.',
                      style: AppTheme.metaOf(context).copyWith(height: 1.35, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showing.isEmpty)
                    EmptyState(
                      icon: _menuFilter == 'History' ? Icons.history_rounded : Icons.restaurant_menu_rounded,
                      title: _menuFilter == 'History' ? 'No meal history yet' : 'No active dishes',
                      message: _menuFilter == 'History'
                          ? 'Expired and deleted dishes will appear here.'
                          : 'Publish your first dish to start receiving orders from hungry customers.',
                    )
                  else
                    ...showing.asMap().entries.map(
                          (entry) => _buildChefMealCard(
                            entry.value,
                            index: entry.key,
                            historyMode: _menuFilter == 'History',
                          ),
                        ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChefMealCard(
    Map<String, dynamic> meal, {
    required int index,
    required bool historyMode,
  }) {
    final isPaused = meal['status']?.toString().toLowerCase() == 'paused';
    final isAvailable = meal['status']?.toString().toLowerCase().trim() == 'available';
    final archived = isChefMealArchived(meal);
    final expired = isPublishedMealExpired(meal);
    final stock = int.tryParse(meal['quantity']?.toString() ?? '0') ?? 0;
    final canBoost = !historyMode && !isPaused && stock > 0;
    final lowStock = stock > 0 && stock <= 3;
    final slot = meal['time_slot']?.toString().trim() ?? '';
    final services = (meal['service_type']?.toString() ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final statusNote = archived
        ? 'Removed'
        : expired
            ? 'Expired'
            : isPaused
                ? 'Paused'
                : stock <= 0
                    ? 'Sold out — diners cannot buy'
                    : mealFailsCurrentCatalogRequirements(meal)
                        ? 'Hidden on Home — finish plate details'
                        : 'Published';

    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: AppTheme.radiusSm,
                child: meal['image_url'] != null
                    ? CachedNetworkImage(
                        imageUrl: meal['image_url'].toString(),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => const AppShimmer(
                          child: ShimmerBox(width: 56, height: 56),
                        ),
                        errorWidget: (_, _, _) => Container(
                            width: 56, height: 56, color: Colors.grey.shade200, child: const Icon(Icons.fastfood)),
                      )
                    : Container(width: 56, height: 56, color: Colors.grey.shade200, child: const Icon(Icons.fastfood)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal['title'] ?? 'Meal',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        decoration: isPaused || historyMode ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      historyMode
                          ? '₹${meal['price']} · $statusNote'
                          : '₹${meal['price']} • Stock: ${meal['quantity']} remaining',
                      style: TextStyle(
                        fontSize: 12,
                        color: lowStock && !historyMode ? AppTheme.warning : AppTheme.textMuted,
                        fontWeight: lowStock && !historyMode ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (mealNutritionFacts(meal).hasValues) ...[
                      const SizedBox(height: 4),
                      Text(
                        mealNutritionFacts(meal).compactLine,
                        style: const TextStyle(fontSize: 11, color: AppTheme.link, fontWeight: FontWeight.w600),
                      ),
                    ],
                    if (!historyMode && lowStock) ...[
                      const SizedBox(height: 4),
                      const Text('Low stock — restock soon',
                          style: TextStyle(fontSize: 11, color: AppTheme.warning, fontWeight: FontWeight.w600)),
                    ],
                    if (slot.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.schedule, size: 14, color: AppTheme.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              slot,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.link),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (services.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: services
                            .map((s) => PillTag(
                                  label: s,
                                  icon: ServiceType.fromString(s).isDelivery
                                      ? Icons.delivery_dining
                                      : Icons.storefront,
                                  color: AppTheme.primary,
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              if (!historyMode)
                Switch.adaptive(
                  activeThumbColor: AppTheme.primary,
                  value: !isPaused && stock > 0 && isAvailable,
                  onChanged: (active) async {
                    if (active && stock <= 0) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Restock this plate before turning it Available.')),
                        );
                      }
                      return;
                    }
                    await _supabase.from('meals').update({'status': active ? 'Available' : 'Paused'}).eq('id', meal['id']);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!historyMode) ...[
                AppIconAction(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit',
                  onPressed: () => _openMealEditor(meal),
                ),
                const SizedBox(width: 8),
                AppIconAction(
                  icon: Icons.inventory_2_outlined,
                  tooltip: 'Restock',
                  onPressed: () => _quickRestockMeal(meal),
                ),
                const SizedBox(width: 8),
              ],
              AppIconAction(
                icon: Icons.copy_outlined,
                tooltip: 'Duplicate',
                onPressed: () => _duplicateMeal(meal),
              ),
              const SizedBox(width: 8),
              AppIconAction(
                icon: Icons.delete_outline,
                tooltip: historyMode ? 'Remove' : 'Delete',
                color: Colors.red.shade700,
                onPressed: historyMode && archived ? null : () => _confirmDeleteMeal(meal),
              ),
              if (!historyMode) ...[
                const SizedBox(width: 8),
                AppIconAction(
                  icon: Icons.share_outlined,
                  tooltip: 'Share dish',
                  onPressed: () => showMealShareSheet(context, {
                    ...meal,
                    'chef_name': _chefDisplayName,
                  }),
                ),
              ],
            ],
          ),
          if (!historyMode) ...[
            const SizedBox(height: 8),
            if (isMealBoosted(meal))
              Text(
                mealBoostUntilLabel(meal),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.link),
              )
            else ...[
              if (canBoost && !isAvailable)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Stock is back — boost will publish this dish on Home again.',
                    style: AppTheme.caption,
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppTheme.textMuted,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusSm),
                  ),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(
                    'Boost on Home · ₹$kChefBoostRupees',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onPressed: canBoost ? () => showChefBoostSheet(context, meal) : null,
                ),
              ),
            ],
          ] else ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.linkOf(context),
                  side: const BorderSide(color: AppTheme.primary),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusSm),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Publish again', style: TextStyle(fontWeight: FontWeight.w700)),
                onPressed: () => _duplicateMeal(meal),
              ),
            ),
          ],
        ],
      ),
    ).entrance(index: index);
  }

  Widget _buildHistoryTab(List<Map<String, dynamic>> orders) {
    final delivered = orders.where((o) => (o['status']?.toString().toLowerCase() ?? '') == 'delivered').toList();
    final cancelled = orders.where((o) {
      final status = o['status']?.toString().toLowerCase() ?? '';
      return status.contains('cancel') || status.contains('reject') || status.contains('refund');
    }).toList();
    final history = _historyFilter == 'Cancelled' ? cancelled : delivered;
    final double revenue = delivered.fold(0.0, (sum, o) => sum + chefPayoutForOrder(o).chefPayout);
    final dinerGmv = delivered.fold(0.0, (sum, o) => sum + _orderTotal(o));
    final platformPct = (kPlatformMarginRate * 100).toStringAsFixed(0);

    if (delivered.isEmpty && cancelled.isEmpty) {
      return const EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'No completed sales yet',
        message: 'Delivered and cancelled orders will appear here with a running sales total.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        AppCard(
          child: Column(
            children: [
              Text('Kitchen take-home', style: AppTheme.metaOf(context).copyWith(fontSize: 13)),
              const SizedBox(height: 6),
              Text(formatRupees(revenue),
                  style: AppTheme.sectionTitleOf(context).copyWith(color: AppTheme.success, fontSize: 28)),
              Text(
                  '${delivered.length} completed • Diner GMV ${formatRupees(dinerGmv)} · $platformPct% platform fee on food + pack',
                  textAlign: TextAlign.center,
                  style: AppTheme.metaOf(context)),
              const SizedBox(height: 4),
              Text(
                'Food + packaging after platform fee · delivery fee stays with HotPotChef',
                textAlign: TextAlign.center,
                style: AppTheme.metaOf(context).copyWith(fontSize: 11),
              ),
              const SizedBox(height: 4),
              Text(
                '${delivered.where((o) => (o['payout_status']?.toString().toLowerCase() ?? '') == 'released').length} payouts released',
                textAlign: TextAlign.center,
                style: AppTheme.metaOf(context),
              ),
            ],
          ),
        ).popIn(),
        const SizedBox(height: 12),
        Row(
          children: [
            ChoiceChip(
              label: Text('Delivered (${delivered.length})'),
              selected: _historyFilter == 'Delivered',
              onSelected: (_) => setState(() => _historyFilter = 'Delivered'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text('Cancelled (${cancelled.length})'),
              selected: _historyFilter == 'Cancelled',
              onSelected: (_) => setState(() => _historyFilter = 'Cancelled'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (history.isEmpty)
          const EmptyState(
            icon: Icons.filter_alt_off_outlined,
            title: 'Nothing in this filter',
            message: 'Switch tabs to see the rest of your kitchen history.',
          )
        else
          ...history.asMap().entries.map((entry) {
            final h = entry.value;
            final isCancelled = _historyFilter == 'Cancelled';
            return AppCard(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: (isCancelled ? AppTheme.error : AppTheme.success).withValues(alpha: 0.12),
                      child: Icon(isCancelled ? Icons.cancel : Icons.check_circle,
                          color: isCancelled ? AppTheme.error : AppTheme.success),
                    ),
                    title: Text(_orderTitle(h), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(
                      isCancelled
                          ? formatOrderDate(h['created_at']?.toString() ?? '')
                          : '${formatOrderDate(h['created_at']?.toString() ?? '')}\n${chefPayoutStatusLabel(h['payout_status']?.toString())} · diner paid ${formatRupees(_orderTotal(h))}',
                    ),
                    isThreeLine: !isCancelled,
                    trailing: Text(
                      isCancelled
                          ? formatRupees(_orderTotal(h))
                          : formatRupees(chefPayoutForOrder(h).chefPayout),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (!isCancelled)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => InvoicePdfService.downloadForOrder(context, h),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                        label: const Text('Invoice'),
                      ),
                    ),
                ],
              ),
            ).entrance(index: entry.key);
          }),
      ],
    );
  }

  String _leadStatus(Map<String, dynamic> request) =>
      request['status']?.toString().toLowerCase().trim() ?? '';

  bool _isVisibleLead(Map<String, dynamic> request) {
    if (isPackagingSupplyRequest(request)) return false;
    final status = _leadStatus(request);
    if (status == 'open') return true;
    final mine = request['accepted_chef_id']?.toString() == _currentUserId;
    return mine && (status == 'accepted' || status == 'ordered' || status == 'paid');
  }

  Future<double?> _askCateringQuote(Map<String, dynamic> request, {double? existingQuote}) async {
    final budget = parseMoney(request['budget']);
    final seed = existingQuote != null && existingQuote > 0
        ? existingQuote
        : budget;
    final controller = TextEditingController(
      text: seed > 0 ? seed.toStringAsFixed(0) : '',
    );
    final quote = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existingQuote != null && existingQuote > 0 ? 'Update quote' : 'Your quote'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            prefixText: '₹ ',
            labelText: 'Quoted total',
            helperText: budget > 0 ? 'Customer budget ₹${budget.toStringAsFixed(0)}' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final value = parseMoney(controller.text, budget);
              Navigator.pop(ctx, value > 0 ? value : budget);
            },
            child: Text(existingQuote != null && existingQuote > 0 ? 'Update' : 'Submit'),
          ),
        ],
      ),
    );
    controller.dispose();
    return quote;
  }

  Future<void> _submitCateringQuote(Map<String, dynamic> request, {double? existingQuote}) async {
    final quote = await _askCateringQuote(request, existingQuote: existingQuote);
    if (quote == null || !mounted) return;

    var ok = false;
    String? errorText;
    try {
      final id = await _supabase.rpc(
        'submit_customer_request_quote',
        params: {
          'p_request_id': request['id'],
          'p_quoted_total': quote,
          'p_chef_name': _chefDisplayName,
        },
      );
      ok = id != null;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to submit catering quote');
      errorText = e.toString();
    }

    if (!mounted) return;
    final lower = (errorText ?? '').toLowerCase();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Quote sent. The customer can compare kitchens and pick yours from My Orders.'
          : (lower.contains('request_not_open')
              ? 'This lead is no longer open for quotes.'
              : (lower.contains('not_authorized')
                  ? 'Only verified kitchens can submit quotes.'
                  : 'Could not submit quote. Try again.'))),
    ));
  }

  Widget _buildCustomerLeadsTab(
    List<Map<String, dynamic>> requests, {
    Map<String, Map<String, dynamic>> myQuotes = const {},
  }) {
    if (requests.isEmpty) {
      return const EmptyState(
        icon: Icons.campaign_outlined,
        title: 'No catering leads',
        message: 'Open broadcasts and jobs you have quoted or won will show up here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final req = requests[index];
        final status = _leadStatus(req);
        final isOpen = status == 'open';
        final awaitingPay = status == 'accepted';
        final paid = status == 'ordered' || status == 'paid';
        final remaining = req['remaining_quantity'] ?? req['quantity'];
        final km = cateringLeadDistanceKm(req, _chefPin);
        final distance = km == null ? 'Distance unknown' : '${km.toStringAsFixed(1)} km away';
        final myQuote = myQuotes[req['id']?.toString() ?? ''];
        final myQuoteTotal = parseMoney(myQuote?['quoted_total']);
        final hasMyQuote = myQuoteTotal > 0;
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
                  Text(
                    hasMyQuote && isOpen
                        ? 'Your ₹${myQuoteTotal.toStringAsFixed(0)}'
                        : (cateringPayableTotal(req) > 0
                            ? '₹${cateringPayableTotal(req).toStringAsFixed(0)}'
                            : '₹${req['budget'] ?? '0'}'),
                    style: const TextStyle(color: AppTheme.link, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isOpen
                    ? (hasMyQuote
                        ? 'Quote submitted • customer may pick any kitchen'
                        : 'Open • submit a quote (customer picks)')
                    : (awaitingPay
                        ? 'Selected • waiting for customer payment'
                        : 'Paid • cook this from Orders'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: paid ? AppTheme.success : (awaitingPay ? AppTheme.warning : AppTheme.textMuted),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Quantity: ${req['quantity']} • Left: $remaining • $distance • Needed by: ${req['target_date_time'] ?? 'ASAP'}',
                style: AppTheme.caption,
              ),
              const SizedBox(height: 14),
              if (isOpen)
                GradientButton(
                  label: hasMyQuote ? 'Update quote' : 'Submit quote',
                  icon: hasMyQuote ? Icons.edit_outlined : Icons.request_quote_outlined,
                  gradient: const LinearGradient(colors: [AppTheme.success, Color(0xFF43C478)]),
                  onPressed: () => _submitCateringQuote(
                    req,
                    existingQuote: hasMyQuote ? myQuoteTotal : null,
                  ),
                )
              else if (awaitingPay)
                Text('Stay ready. The customer pays from My Orders, then this becomes a kitchen order.',
                    style: AppTheme.caption)
              else
                Text('Payment received. Confirm the new order on the Orders tab.',
                    style: AppTheme.caption),
              const SizedBox(height: 8),
              if (hasMyQuote || awaitingPay || paid)
                Row(
                  children: [
                    AppIconAction(
                      icon: Icons.chat_bubble_outline,
                      tooltip: 'Message',
                      onPressed: () => context.push(chatPath(
                        req['id'].toString(),
                        roomName: req['title']?.toString() ?? 'Catering lead',
                        otherUserId: req['customer_id']?.toString(),
                      )),
                    ),
                    const SizedBox(width: 8),
                    AppIconAction(
                      icon: Icons.phone_outlined,
                      tooltip: paid ? 'Call' : 'Call after pay',
                      onPressed: paid
                          ? () => _callCustomer(req['customer_id']?.toString() ?? '')
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Call unlocks after in-app payment. Use Message to discuss the quote.'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            },
                    ),
                  ],
                )
              else
                Text('Submit a quote to message the customer about this lead.',
                    style: AppTheme.caption),
            ],
          ),
        ).entrance(index: index);
      },
    );
  }
}

class _ChefPrepAdvanceButton extends StatefulWidget {
  const _ChefPrepAdvanceButton({
    required this.order,
    required this.isPreparing,
    required this.onAdvance,
  });

  final Map<String, dynamic> order;
  final bool isPreparing;
  final VoidCallback onAdvance;

  @override
  State<_ChefPrepAdvanceButton> createState() => _ChefPrepAdvanceButtonState();
}

class _ChefPrepAdvanceButtonState extends State<_ChefPrepAdvanceButton> {
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
    final canStart = widget.isPreparing || canChefStartPreparing(widget.order);
    return GradientButton(
      label: widget.isPreparing ? 'Ready for Pickup' : 'Start Preparing',
      icon: widget.isPreparing ? Icons.check_circle_rounded : Icons.soup_kitchen_rounded,
      gradient: widget.isPreparing
          ? const LinearGradient(colors: [Color(0xFF00897B), Color(0xFF26A69A)])
          : AppTheme.primaryGradient,
      onPressed: canStart ? widget.onAdvance : null,
    );
  }
}