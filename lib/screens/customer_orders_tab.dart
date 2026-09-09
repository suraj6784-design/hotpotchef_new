// lib/screens/customer_orders_tab.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../utils/app_page.dart';
import '../utils/helpers.dart';
import '../utils/network.dart';
import '../utils/support.dart';
import '../widgets/customer_ui_components.dart';
import '../widgets/app_widgets.dart';
import '../widgets/last_order_banner.dart';
import '../widgets/order_slot_banner.dart';
import '../widgets/meal_review_dialog.dart';
import '../services/chef_directory.dart';
import '../services/order_lifecycle.dart';
import '../services/reorder_service.dart';
import '../services/invoice_pdf_service.dart';
import '../providers/cart_provider.dart';
import '../providers/last_order_provider.dart';
import 'checkout_screen.dart';

class CustomerOrdersTab extends ConsumerStatefulWidget {
  final VoidCallback onProfileTap;
  final VoidCallback onLogout;
  final VoidCallback? onReorderToCart;
  final int refreshEpoch;

  const CustomerOrdersTab({
    super.key,
    required this.onProfileTap,
    required this.onLogout,
    this.onReorderToCart,
    this.refreshEpoch = 0,
  });

  @override
  ConsumerState<CustomerOrdersTab> createState() => _CustomerOrdersTabState();
}

class _CustomerOrdersTabState extends ConsumerState<CustomerOrdersTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _activeOrders = [];
  List<Map<String, dynamic>> _activeRequests = [];
  Map<String, dynamic>? _savedDropoffAddress;
  bool _isLoading = true;
  final Map<String, List<Map<String, dynamic>>> _quotesByRequest = {};

  StreamSubscription? _ordersSub;
  StreamSubscription? _reqsSub;
  StreamSubscription? _quotesSub;

  PreferredSizeWidget _ordersAppBar() {
    return HubAppBar(
      title: 'My Orders',
      onProfile: widget.onProfileTap,
      extraActions: [
        IconButton(
          tooltip: 'Past orders',
          icon: const Icon(Icons.history_rounded, color: AppTheme.primary),
          onPressed: () => context.push('/order-history'),
        ),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initScopedStreams();
  }

  @override
  void didUpdateWidget(CustomerOrdersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshEpoch != widget.refreshEpoch) {
      unawaited(_fetchActiveOrders(showSpinner: false));
    }
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    _reqsSub?.cancel();
    _quotesSub?.cancel();
    super.dispose();
  }

  bool _isActiveStatus(String? status) {
    final value = status?.toString().toLowerCase() ?? '';
    return !value.contains('delivered') &&
        !value.contains('completed') &&
        !value.contains('cancelled') &&
        !value.contains('rejected');
  }

  List<Map<String, dynamic>> _activeRows(Iterable<dynamic> rows) {
    return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).where((row) {
      return _isActiveStatus(row['status']?.toString());
    }).toList();
  }

  List<Map<String, dynamic>> _cateringRows(Iterable<dynamic> rows) {
    return _activeRows(rows).where((row) => !isPackagingSupplyRequest(row)).toList();
  }

  void _applyQuotes(Iterable<dynamic> rows, {bool replaceAll = true}) {
    final next = <String, List<Map<String, dynamic>>>{};
    for (final row in rows.whereType<Map>()) {
      final map = Map<String, dynamic>.from(row);
      final rid = map['request_id']?.toString() ?? '';
      if (rid.isEmpty) continue;
      next.putIfAbsent(rid, () => <Map<String, dynamic>>[]).add(map);
    }
    for (final entry in next.entries) {
      next[entry.key] = cateringQuotesSorted(entry.value);
    }
    if (replaceAll) {
      _quotesByRequest
        ..clear()
        ..addAll(next);
    } else {
      _quotesByRequest.addAll(next);
    }
  }

  Future<void> _refreshQuotes({Iterable<String>? requestIds}) async {
    final ids = (requestIds ?? _activeRequests.map((r) => r['id']?.toString() ?? ''))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      if (mounted) setState(() => _quotesByRequest.clear());
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('customer_request_quotes')
          .select()
          .inFilter('request_id', ids);
      if (!mounted) return;
      setState(() => _applyQuotes(rows as List));
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Catering quotes refresh failed');
    }
  }

  Future<void> _fetchActiveOrders({bool showSpinner = true}) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _activeOrders = [];
          _activeRequests = [];
          _isLoading = false;
        });
      }
      return;
    }

    if (showSpinner && mounted) setState(() => _isLoading = true);

    try {
      List<dynamic> orderRows = const [];
      try {
        orderRows = await supabase
            .from('orders')
            .select()
            .eq('customer_id', user.id)
            .order('created_at', ascending: false);
      } catch (_) {
        orderRows = await supabase
            .from('orders')
            .select()
            .or('customer_id.eq.${user.id},user_id.eq.${user.id}')
            .order('created_at', ascending: false);
      }

      List<dynamic> requestRows = const [];
      try {
        requestRows = await supabase
            .from('customer_requests')
            .select()
            .eq('customer_id', user.id)
            .order('created_at', ascending: false);
      } catch (_) {}

      await _loadSavedDropoffAddress(user.id);

      if (!mounted) return;
      setState(() {
        _activeOrders = _activeRows(orderRows);
        _activeRequests = _cateringRows(requestRows);
        _isLoading = false;
      });
      unawaited(_refreshQuotes());
      unawaited(ref.read(lastOrderProvider.notifier).fetchLastOrder());
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Customer orders refresh failed');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _initScopedStreams() {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    unawaited(_fetchActiveOrders());

    _ordersSub?.cancel();
    _reqsSub?.cancel();
    _quotesSub?.cancel();

    _ordersSub = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen(
      (data) {
        if (!mounted) return;
        final mine = data.where((order) {
          final owner = order['customer_id']?.toString() ?? order['user_id']?.toString() ?? '';
          return owner == user.id;
        });
        setState(() {
          _activeOrders = _activeRows(mine);
          _isLoading = false;
        });
      },
      onError: (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Customer orders stream error');
        if (mounted) setState(() => _isLoading = false);
      },
    );

    _reqsSub = supabase
        .from('customer_requests')
        .stream(primaryKey: ['id'])
        .eq('customer_id', user.id)
        .order('created_at', ascending: false)
        .listen(
      (data) {
        if (!mounted) return;
        setState(() {
          _activeRequests = _cateringRows(data);
          _isLoading = false;
        });
        unawaited(_refreshQuotes());
      },
      onError: (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Customer bulk requests stream error');
      },
    );

    _quotesSub = supabase
        .from('customer_request_quotes')
        .stream(primaryKey: ['id'])
        .listen(
      (data) {
        if (!mounted) return;
        final mineRequestIds = _activeRequests.map((r) => r['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
        // Avoid wiping the quote map before requests have loaded.
        if (mineRequestIds.isEmpty) return;
        final relevant = data.where((row) {
          final rid = row['request_id']?.toString() ?? '';
          return mineRequestIds.contains(rid);
        });
        setState(() => _applyQuotes(relevant));
      },
      onError: (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Customer catering quotes stream error');
      },
    );

    // Orders stream already covers live updates; skip a second postgres channel.
  }

  Future<void> _loadSavedDropoffAddress(String userId) async {
    try {
      final rows = await Supabase.instance.client.from('user_addresses').select().eq('user_id', userId);
      _savedDropoffAddress = preferredCheckoutAddress(
        uniqueSavedAddresses(List<Map<String, dynamic>>.from(rows as List)),
      );
    } catch (_) {}
    if (_savedDropoffAddress != null) return;
    try {
      final profile = await Supabase.instance.client
          .from('users')
          .select('address, house_no, street, city, state, pincode, lat, lng, latitude, longitude')
          .eq('id', userId)
          .maybeSingle();
      _savedDropoffAddress = checkoutAddressFromUserProfile(profile);
    } catch (_) {}
  }

  String _dropoffLabel(Map<String, dynamic> order, List<Map<String, dynamic>> items) {
    final value = orderDropoffAddress(order, items: items, fallbackAddress: _savedDropoffAddress);
    return value.isEmpty ? 'Unknown Location' : value;
  }

  String _pickupLabel(Map<String, dynamic> order, List<Map<String, dynamic>> items) {
    final value = orderPickupAddress(order, items: items);
    return value.isEmpty ? 'Kitchen Location' : value;
  }

  // Delegates to the shared helper so slot resolution (including the
  // "delivery date is never before the order date" guard) stays consistent
  // across every screen.
  String _slotLabel(Map<String, dynamic> item, {List<Map<String, dynamic>>? orderItems}) {
    return formatDeliverySlotLabel({
      ...item,
      if (orderItems != null) 'items': orderItems,
    });
  }

  bool _canCancelOrder(Map<String, dynamic> order) {
    return OrderLifecycle.canCustomerCancelOrder(order);
  }

  Future<void> _cancelOrderGroup(List<Map<String, dynamic>> groupItems) async {
    final hasDelivery = groupItems.any((item) {
      final service = item['service_type']?.toString().toLowerCase() ?? '';
      return service.contains('delivery');
    });
    final bill = orderBillBreakdown(
      items: groupItems,
      order: groupItems.isNotEmpty ? groupItems.first : null,
      hasDelivery: hasDelivery,
    );
    final refundRupees = bill.grandTotal.toInt();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: AppTheme.dialogShape,
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Cancel Order'),
        ]),
        content: Text(
          'You can cancel until the chef starts cooking, or until your delivery slot begins.\n\n'
          'Refund ₹$refundRupees will be sent to the original payment method (usually 5–7 business days).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, Keep it', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final String orderId = groupItems.first['order_id']?.toString() ?? groupItems.first['id'].toString();
        await OrderLifecycle().cancel(
          orderId: orderId,
          reason: 'Cancelled by customer',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order cancelled. Refund is on the way if you paid online.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _showReviewDialog(Map order) async {
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => MealReviewDialog(
        mealTitle: order['title']?.toString() ?? 'this meal',
        onSubmit: (rating, comment) async {
          final supabase = Supabase.instance.client;
          final user = supabase.auth.currentUser;
          if (user == null) throw Exception('Please log in to rate meals.');

          try {
            await supabase.from('reviews').insert({
              'meal_id': order['source_meal_id'] ?? order['id'],
              'customer_id': user.id,
              'chef_id': order['chef_id'],
              'rating': rating,
              'comment': comment,
            });
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(networkErrorMessage(e)), backgroundColor: Colors.red),
              );
            }
            rethrow;
          }
        },
      ),
    );

    if (!mounted || submitted != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Review submitted!'), backgroundColor: Colors.green),
    );
  }

  Future<void> _downloadInvoicePDF(
    BuildContext context,
    String orderId,
    String date,
    List<Map<String, dynamic>> items,
    double itemsTotal,
    double packagingFee,
    double deliveryFee,
    double grandTotal, {
    double tipAmount = 0,
    double coinsApplied = 0,
  }) {
    return InvoicePdfService.download(
      context: context,
      orderId: orderId,
      date: date,
      items: items,
      itemsTotal: itemsTotal,
      packagingFee: packagingFee,
      deliveryFee: deliveryFee,
      tipAmount: tipAmount,
      coinsApplied: coinsApplied,
    );
  }

  void _showOrderDetailsBottomSheet(
    BuildContext context,
    String displayOrderIdStr,
    String dateTimeString,
    String deliveryTimeStr,
    List<Map<String, dynamic>> items,
    double itemsTotal,
    double packagingFee,
    double deliveryFee,
    double finalGrandTotal,
    bool canCancelGroup,
    bool isDelivered,
    Map<String, dynamic>? trackableItem,
  ) {
    final chefId = items.first['chef_id']?.toString() ?? '';
    final status = items.first['status']?.toString() ?? 'Pending';
    final bill = orderBillBreakdown(
      items: items,
      order: items.first,
      hasDelivery: (items.first['service_type']?.toString().toLowerCase() ?? '').contains('delivery'),
    );
    itemsTotal = bill.itemsTotal;
    packagingFee = bill.packagingFee;
    deliveryFee = bill.deliveryFee;
    finalGrandTotal = bill.grandTotal;
    final orderType = items.first['service_type']?.toString() ?? 'Delivery';
    final slotLabel = formatDeliverySlotLabel({
      ...items.first,
      'items': items,
    });

    IconData statusIcon = Icons.hourglass_empty;
    Color statusColor = Colors.orange;
    String statusText = 'Processing Order';

    if (status.toLowerCase().contains('delivered') || status.toLowerCase().contains('completed')) {
      statusIcon = Icons.check_circle;
      statusColor = Colors.green;
      statusText = 'Order was delivered';
    } else if (status.toLowerCase().contains('cancelled') || status.toLowerCase().contains('rejected')) {
      statusIcon = Icons.cancel;
      statusColor = Colors.red;
      statusText = 'Order Cancelled';
    } else if (OrderLifecycle.isTrackable(status) && !status.toLowerCase().contains('ready')) {
      statusIcon = Icons.delivery_dining;
      statusColor = AppTheme.primary;
      statusText = 'Order is on the way';
    } else if (hasDispatchPhoto(items.first) || status.toLowerCase().contains('ready')) {
      statusIcon = Icons.inventory_2_outlined;
      statusColor = AppTheme.success;
      statusText = dispatchPackedLabel(takenAt: orderDispatchPhotoAt(items.first));
    } else if (status.toLowerCase().contains('preparing')) {
      statusIcon = Icons.soup_kitchen;
      statusColor = Colors.orange;
      statusText = 'Chef is preparing your food';
    } else if (status.toLowerCase().contains('confirm')) {
      statusIcon = Icons.thumb_up_alt_outlined;
      statusColor = AppTheme.success;
      statusText = 'Chef accepted your order';
    } else if (OrderLifecycle.isPendingKitchen(status)) {
      statusIcon = Icons.hourglass_empty;
      statusColor = Colors.orange;
      statusText = 'Waiting for the chef to accept';
    }

    final bool isCancelled = status.toLowerCase().contains('cancelled') || status.toLowerCase().contains('rejected');
    final bool isTrackable = OrderLifecycle.isTrackable(status) && trackableItem != null;

    final serviceTypeStr = items.first['service_type']?.toString().toLowerCase() ?? '';
    final isPickupOrDineIn = serviceTypeStr.contains('pickup') || serviceTypeStr.contains('dine');
    final addressLabel = isPickupOrDineIn ? 'Pickup Location' : 'Delivery Address';
    final addressValue = isPickupOrDineIn
        ? _pickupLabel(items.first, items)
        : _dropoffLabel(items.first, items);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.92,
          decoration: AppTheme.bottomSheetDecoration(isDark: Theme.of(context).brightness == Brightness.dark),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceOf(context),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.rXl)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        GestureDetector(onTap: () => Navigator.pop(ctx), child: Icon(Icons.arrow_back, color: AppTheme.onSurfaceOf(context))),
                        const SizedBox(width: 12),
                        Text('Order details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context))),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => showContactSupportSheet(
                        ctx,
                        orderNumber: displayOrderIdStr,
                        orderUuid: items.first['order_id']?.toString() ?? items.first['id']?.toString(),
                      ),
                      child: const Text('Support', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                    )
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    AppCard(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(statusIcon, color: statusColor, size: 24),
                              const SizedBox(width: 12),
                              Expanded(child: Text(statusText, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.onSurfaceOf(context)))),
                            ],
                          ),
                          if (hasDispatchPhoto(items.first)) ...[
                            const SizedBox(height: 12),
                            DispatchPackedPhoto(
                              url: orderDispatchPhotoUrl(items.first)!,
                              caption: dispatchPackedLabel(takenAt: orderDispatchPhotoAt(items.first)),
                            ),
                          ],
                          if (!orderAllowsPartyChat(status)) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.08),
                                borderRadius: AppTheme.radiusSm,
                              ),
                              child: const Text(
                                'Order chat with the kitchen and delivery partner is closed. Tap Support above for any post-delivery issues.',
                                style: TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: AppTheme.hairlineOf(context))),
                          
                          // Timings & Delivery Type in Details Sheet
                          Row(
                            children: [
                              const Icon(Icons.local_shipping_outlined, size: 14, color: AppTheme.primary),
                              const SizedBox(width: 6),
                              const Text('Type: ', style: AppTheme.caption),
                              Text(orderType, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.access_time, size: 14, color: AppTheme.textMuted),
                              const SizedBox(width: 6),
                              const Text('Placed: ', style: AppTheme.caption),
                              Text(dateTimeString, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.onSurfaceOf(context))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.event_available, size: 14, color: Colors.green),
                              const SizedBox(width: 6),
                              const Text('Promised slot: ', style: AppTheme.caption),
                              Expanded(
                                child: Text(slotLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                              ),
                            ],
                          ),
                          if (dinerSlotCountdownActive(status)) ...[
                            const SizedBox(height: 10),
                            OrderSlotBanner(order: {...items.first, 'items': items}, diner: true),
                          ],
                          if (!isDelivered) ...[
                            Builder(
                              builder: (_) {
                                final pin = items.first['delivery_otp']?.toString().trim() ?? '';
                                if (pin.isEmpty) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withValues(alpha: 0.08),
                                      borderRadius: AppTheme.radiusMd,
                                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                                    ),
                                    child: Text(
                                      'Delivery PIN: $pin — share with driver at the door',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.onSurfaceOf(context),
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(isPickupOrDineIn ? Icons.storefront : Icons.location_on, size: 14, color: isPickupOrDineIn ? Colors.blue : Colors.red),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text('$addressLabel: $addressValue',
                                    style: AppTheme.caption,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),

                          if (isDelivered) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.done_all, size: 14, color: Colors.green),
                                const SizedBox(width: 6),
                                Text(
                                  'Delivered: ${formatOrderDate(items.first['delivered_at']?.toString() ?? items.first['updated_at']?.toString() ?? items.first['created_at']?.toString())}',
                                  style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                          if (isTrackable) ...[
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: AppIconAction(
                                icon: Icons.map_outlined,
                                tooltip: 'Track live location',
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _openTracking(trackableItem, items);
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    AppCard(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(children: [
                                CircleAvatar(backgroundColor: AppTheme.primary.withValues(alpha: 0.1), radius: 20, child: const Icon(Icons.restaurant, color: AppTheme.primary, size: 20)),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    FutureBuilder<String>(
                                      future: lookupChefDisplayName(chefId, hint: items.first),
                                      builder: (context, snap) {
                                        final name = snap.data ??
                                            chefDisplayName(items.first, fallback: 'Loading chef...');
                                        return Text(
                                          name,
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.onSurfaceOf(context)),
                                        );
                                      },
                                    ),
                                    const Text('Home kitchen', style: AppTheme.caption),
                                  ],
                                ),
                              ]),
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      if (!orderAllowsPartyChat(status)) {
                                        showContactSupportSheet(
                                          ctx,
                                          orderNumber: displayOrderIdStr,
                                          orderUuid: items.first['order_id']?.toString() ?? items.first['id']?.toString(),
                                        );
                                        return;
                                      }
                                      context.push(chatPath(
                                        items.first['order_id']?.toString() ?? items.first['id']?.toString() ?? '',
                                        roomName: 'Order $displayOrderIdStr',
                                        otherUserId: chefId,
                                        memberIds: orderChatMemberIds(items.first),
                                        isGroup: true,
                                      ));
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: AppTheme.hairlineOf(context)),
                                        color: orderAllowsPartyChat(status) ? null : AppTheme.surfaceMutedOf(context),
                                      ),
                                      child: Icon(
                                        Icons.chat_bubble_outline,
                                        color: orderAllowsPartyChat(status) ? AppTheme.primary : Colors.grey,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: orderAllowsPhoneCall(status)
                                        ? () => _initiateCall(chefId)
                                        : () {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Phone is for active prep/delivery. Prefer Chat.'),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: AppTheme.hairlineOf(context)),
                                        color: orderAllowsPhoneCall(status) ? null : AppTheme.surfaceMutedOf(context),
                                      ),
                                      child: Icon(
                                        Icons.phone_outlined,
                                        color: orderAllowsPhoneCall(status) ? Colors.redAccent : Colors.grey,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                  if (_driverIdOf(items.first) != null) ...[
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: orderAllowsPhoneCall(status)
                                          ? () => _initiateCall(_driverIdOf(items.first)!)
                                          : () {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Phone is for active prep/delivery. Prefer Chat.'),
                                                  backgroundColor: Colors.orange,
                                                ),
                                              );
                                            },
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: AppTheme.hairlineOf(context)),
                                          color: orderAllowsPhoneCall(status) ? null : AppTheme.surfaceMutedOf(context),
                                        ),
                                        child: Icon(
                                          Icons.sports_motorsports_outlined,
                                          color: orderAllowsPhoneCall(status) ? Colors.blueAccent : Colors.grey,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            ],
                          ),
                          Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: AppTheme.hairlineOf(context))),
                          orderIdCopyRow(context, displayOrderIdStr),
                          const SizedBox(height: 16),
                          ...items.map((item) {
                            double parsedPrice = lineItemListPrice(item);
                            int parsedQty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;

                            final smartSlot = _slotLabel(item, orderItems: items);
                            final shownSlot = smartSlot == 'ASAP' ? slotLabel : smartSlot;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 2, right: 8),
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(border: Border.all(color: Colors.green), borderRadius: BorderRadius.circular(2)),
                                    child: Center(
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${item['quantity']} x ${item['title']}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context))),
                                        const SizedBox(height: 2),
                                        Text('Slot: $shownSlot', style: AppTheme.caption),
                                      ],
                                    ),
                                  ),
                                  Text('₹${(parsedPrice * parsedQty).toInt()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    AppCard(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(children: const [
                                Icon(Icons.receipt_long, color: AppTheme.textMuted, size: 18),
                                SizedBox(width: 8),
                                Text('Bill Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
                              ]),
                              if (isDelivered)
                                GestureDetector(
                                  onTap: () => _downloadInvoicePDF(
                                    context,
                                    displayOrderIdStr,
                                    dateTimeString,
                                    items,
                                    itemsTotal,
                                    packagingFee,
                                    deliveryFee,
                                    finalGrandTotal,
                                    tipAmount: bill.tipAmount,
                                    coinsApplied: bill.coinsApplied,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                                    ),
                                    child: const Icon(Icons.download, color: Colors.redAccent, size: 16),
                                  ),
                                )
                            ],
                          ),
                          const SizedBox(height: 16),
                          ...orderBillItemRows(context, bill),
                          const SizedBox(height: 10),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Packaging fees', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)), Text('₹${packagingFee.toInt()}', style: TextStyle(color: AppTheme.onSurfaceOf(context), fontSize: 13, fontWeight: FontWeight.w500))]),
                          const SizedBox(height: 10),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Delivery fee', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)), Text('₹${deliveryFee.toInt()}', style: TextStyle(color: AppTheme.onSurfaceOf(context), fontSize: 13, fontWeight: FontWeight.w500))]),
                          ...orderBillAdjustmentRows(context, bill),
                          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: AppTheme.hairlineOf(context))),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Grand total', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.onSurfaceOf(context))), Text('₹${finalGrandTotal.toInt()}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.onSurfaceOf(context)))]),
                          if (isCancelled) ...[
                            const SizedBox(height: 10),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Refund amount', style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold)), Text('₹${finalGrandTotal.toInt()}', style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold))]),
                          ],
                        ],
                      ),
                    ),
                    if (isDelivered)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AppIconAction(
                            icon: Icons.ios_share,
                            tooltip: 'Share your plate',
                            onPressed: () => showPlateShareSheet(
                              ctx,
                              items: items,
                              chefId: chefId,
                            ),
                          ),
                        ),
                      ),
                    if (isDelivered || isCancelled)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.replay, size: 18),
                          label: const Text('Reorder these meals'),
                          onPressed: () => _reorderItems(items),
                        ),
                      ),
                    if (isDelivered)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: OrderItemReviewButtons(
                          items: items,
                          onRate: (item) {
                            Navigator.pop(ctx);
                            if (!mounted) return;
                            _showReviewDialog(item);
                          },
                        ),
                      ),
                    if (canCancelGroup)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _cancelOrderGroup(items);
                          },
                          child: const Text('Cancel Full Order', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        ),
                      )
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _reorderItems(List<Map<String, dynamic>> items) async {
    final result = await ReorderService.addOrderItemsToCart(
      cart: ref.read(cartProvider.notifier),
      items: items,
    );
    if (!mounted) return;
    if (result.added <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ReorderService.resultMessage(result))),
      );
      return;
    }
    Navigator.of(context).maybePop();
    widget.onReorderToCart?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ReorderService.resultMessage(result))),
    );
  }

  Future<void> _selectCateringQuote(Map<String, dynamic> request, Map<String, dynamic> quote) async {
    final quoteId = quote['id']?.toString() ?? '';
    if (quoteId.isEmpty) return;
    try {
      final ok = await Supabase.instance.client.rpc(
            'select_customer_request_quote',
            params: {'p_quote_id': quoteId},
          ) ==
          true;
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not select that kitchen. Try again.')),
        );
        return;
      }
      await _fetchActiveOrders(showSpinner: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${cateringQuoteChefLabel(quote)} selected. Confirm & pay when ready.',
          ),
        ),
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Select catering quote failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not select kitchen: $e')),
      );
    }
  }

  Future<void> _payCateringRequest(Map<String, dynamic> request) async {
    final chefId = request['accepted_chef_id']?.toString() ?? '';
    if (chefId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a kitchen quote first.')),
      );
      return;
    }
    final items = checkoutItemsFromCateringRequest(request);
    if (!mounted) return;
    Navigator.push(
      context,
      appMaterialRoute(
        CheckoutScreen(
          cartItems: items,
          sourceRequestId: request['id']?.toString(),
          preferredAddress: {
            'address': request['delivery_address'],
            'street': request['delivery_address'],
            'latitude': request['latitude'],
            'longitude': request['longitude'],
          },
          onOrderPlacedSuccess: () {
            unawaited(_fetchActiveOrders(showSpinner: false));
          },
        ),
      ),
    );
  }

  String? _driverIdOf(Map<String, dynamic> item) {
    final driverId = item['driver_id']?.toString() ?? item['delivery_partner_id']?.toString() ?? '';
    return driverId.isEmpty ? null : driverId;
  }

  void _openTracking(Map<String, dynamic> trackableItem, List<Map<String, dynamic>> items) {
    final orderUuid = resolvedOrderId(trackableItem) ?? resolvedOrderId(items.first);
    Map<String, dynamic>? fullOrder;
    for (final row in _activeOrders) {
      if (row['id']?.toString() == orderUuid) {
        fullOrder = row;
        break;
      }
    }
    final status = items.first['status']?.toString() ?? '';
    context.push('/tracking', extra: {
      'order': fullOrder ??
          {
            ...trackableItem,
            'id': orderUuid,
            'order_id': orderUuid,
          },
      'isDriver': false,
      'isDineInNavigation': status.toLowerCase().contains('ready') &&
          !(items.first['service_type']?.toString().toLowerCase().contains('delivery') ?? false),
    });
  }

  Future<void> _initiateCall(String targetUserId) async {
    try {
      final userDoc = await Supabase.instance.client.from('users').select('phone').eq('id', targetUserId).maybeSingle();
      final phoneStr = userDoc?['phone']?.toString();

      if (phoneStr != null && phoneStr.isNotEmpty) {
        final Uri launchUri = Uri(scheme: 'tel', path: phoneStr);
        if (await canLaunchUrl(launchUri)) {
          await launchUrl(launchUri);
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open phone dialer.'), backgroundColor: Colors.red));
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No phone number available.'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _buildBulkRequestCard(Map<String, dynamic> req) {
    final status = req['status']?.toString() ?? 'Open';
    final isOpen = status.toLowerCase() == 'open';
    final isAccepted = status.toLowerCase() == 'accepted';
    final isOrdered = status.toLowerCase() == 'ordered' || status.toLowerCase() == 'paid';
    final isCancelled = status.toLowerCase() == 'cancelled';
    final chefName = req['accepted_chef_name'] ?? 'Pending Chef Acceptance';
    final chefId = req['accepted_chef_id'];
    final requestId = req['id']?.toString() ?? '';
    final quotes = _quotesByRequest[requestId] ?? const <Map<String, dynamic>>[];

    final displayRequestId =
        requestId.length > 8 ? 'REQ-${requestId.substring(0, 8).toUpperCase()}' : 'REQ-$requestId';

    return AppCard(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.12), borderRadius: AppTheme.radiusSm),
                    child: const Text('Bulk broadcast', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  const SizedBox(width: 8),
                  Text(displayRequestId, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.bold, fontSize: 11)),
                ],
              ),
              Text(status.toUpperCase(),
                  style: TextStyle(
                      color: isAccepted ? Colors.green : (isCancelled ? Colors.red : Colors.orange),
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Text('${req['quantity']}x ${req['title']}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context))),
          const SizedBox(height: 4),
          Text(
            cateringPayableTotal(req) > 0 &&
                    cateringPayableTotal(req) != parseMoney(req['budget'])
                ? 'Selected quote: ₹${cateringPayableTotal(req).toStringAsFixed(0)}  (budget ₹${req['budget']})'
                : 'Budget: ₹${req['budget']}',
            style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(children: [const Icon(Icons.calendar_today, size: 14, color: AppTheme.textMuted), const SizedBox(width: 6), Text('Needed By: ${req['target_date_time']}', style: AppTheme.caption)]),
          if ((isOpen || isAccepted) && !isCancelled) ...[
            Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: AppTheme.hairlineOf(context))),
            Text(
              quotes.isEmpty
                  ? 'Waiting for kitchen quotes…'
                  : '${quotes.length} quote${quotes.length == 1 ? '' : 's'} — pick one',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            if (quotes.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Nearby chefs can bid. You choose who cooks, then pay.',
                  style: AppTheme.caption,
                ),
              )
            else
              ...quotes.map((quote) {
                final amount = parseMoney(quote['quoted_total']);
                final selected = quote['status']?.toString().toLowerCase() == 'selected' ||
                    (isAccepted && quote['chef_id']?.toString() == chefId?.toString());
                final label = cateringQuoteChefLabel(quote);
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: AppTheme.radiusMd,
                      border: Border.all(
                        color: selected ? AppTheme.primary : AppTheme.hairlineOf(context),
                        width: selected ? 1.5 : 1,
                      ),
                      color: selected ? AppTheme.primary.withValues(alpha: 0.06) : null,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(
                                '₹${amount.toStringAsFixed(0)}',
                                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                        if (selected)
                          const Text('Selected', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12))
                        else
                          TextButton(
                            onPressed: () => _selectCateringQuote(req, quote),
                            child: const Text('Select'),
                          ),
                      ],
                    ),
                  ),
                );
              }),
          ],
          if (isAccepted || isOrdered) ...[
            Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: AppTheme.hairlineOf(context))),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [const Icon(Icons.person, size: 16, color: Colors.green), const SizedBox(width: 6), Text('Kitchen: $chefName', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13))]),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _initiateCall(chefId?.toString() ?? ''),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.hairlineOf(context)),
                        ),
                        child: const Icon(Icons.phone, color: Colors.teal, size: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => context.push(chatPath(
                        req['id'].toString(),
                        roomName: chefName.toString(),
                        otherUserId: chefId?.toString(),
                      )),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.hairlineOf(context)),
                        ),
                        child: const Icon(Icons.chat_bubble, color: Colors.blue, size: 16),
                      ),
                    ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 12),
            if (isAccepted)
              GradientButton(
                label: 'Confirm & pay chef',
                icon: Icons.payments_outlined,
                onPressed: () => _payCateringRequest(req),
              )
            else
              const Text('Paid. This catering job is now a regular kitchen order.',
                  style: AppTheme.caption),
          ] else if (!isCancelled) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () async {
                  await Supabase.instance.client.from('customer_requests').update({'status': 'Cancelled'}).eq('id', req['id']);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Broadcast cancelled'), backgroundColor: Colors.orange));
                    unawaited(_fetchActiveOrders(showSpinner: false));
                  }
                },
                child: const Text('Cancel Broadcast', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            )
          ]
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.canvasOf(context),
        appBar: const HubAppBar(title: 'My Orders'),
        body: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Sign in to track orders',
          message: 'Your live kitchen and delivery updates will show up here.',
          actionLabel: 'Sign In',
          onAction: () => showAuthBottomSheet(context, () {
            setState(() => _isLoading = true);
            _initScopedStreams();
          }),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.canvasOf(context),
        appBar: _ordersAppBar(),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    if (_activeOrders.isEmpty && _activeRequests.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.canvasOf(context),
        appBar: _ordersAppBar(),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            LastOrderReorderBanner(
              compact: true,
              onAddedToCart: widget.onReorderToCart,
            ),
            EmptyState(
              icon: Icons.soup_kitchen_outlined,
              title: 'No active orders',
              message: 'Placed meals show up here with live kitchen and delivery status.',
              actionLabel: 'Browse past orders',
              onAction: () => context.push('/order-history'),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => unawaited(_fetchActiveOrders()),
                child: const Text('Refresh'),
              ),
            ),
          ],
        ),
      );
    }

    Map<String, List<Map<String, dynamic>>> groupedOrders = {};
    for (var order in _activeOrders) {
      final rawId = order['id'].toString();
      final parsedMaps = parseOrderItemsList(order['items']);
      final resolvedDropoff = orderDropoffAddress(
        order,
        items: parsedMaps,
        fallbackAddress: _savedDropoffAddress,
      );

      List<Map<String, dynamic>> enrichedItems = [];
      for (var item in parsedMaps) {
        enrichedItems.add({
          ...item,
          'order_id': order['id'],
          'customer_id': order['customer_id'] ?? order['user_id'],
          'chef_id': order['chef_id'],
          'status': order['status'] ?? 'New Order',
          'service_type': order['order_type'] ?? order['service_type'] ?? 'Delivery',
          'delivery_address': resolvedDropoff.isEmpty ? order['delivery_address'] : resolvedDropoff,
          'driver_id': order['driver_id'] ?? order['delivery_partner_id'],
          'delivery_otp': order['delivery_otp'],
          'created_at': order['created_at'] ?? DateTime.now().toIso8601String(),
          'updated_at': order['updated_at'],
          'delivered_at': order['delivered_at'],
          'total_price': order['total_price'],
          'delivery_fee': order['delivery_fee'],
          'packaging_fee': order['packaging_fee'],
          'tip_amount': order['tip_amount'],
          'coins_applied': order['coins_applied'],
        });
      }

      if (enrichedItems.isEmpty) {
        enrichedItems.add({
          'order_id': order['id'],
          'customer_id': order['customer_id'] ?? order['user_id'],
          'chef_id': order['chef_id'],
          'status': order['status'] ?? 'New Order',
          'service_type': order['order_type'] ?? 'Delivery',
          'delivery_address': resolvedDropoff.isEmpty ? order['delivery_address'] : resolvedDropoff,
          'driver_id': order['driver_id'] ?? order['delivery_partner_id'],
          'delivery_otp': order['delivery_otp'],
          'created_at': order['created_at'] ?? DateTime.now().toIso8601String(),
          'updated_at': order['updated_at'],
          'delivered_at': order['delivered_at'],
          'title': order['title'] ?? 'Custom Order',
          'quantity': 1,
          'price': order['price'] ?? 0,
          'total_price': order['total_price'],
          'delivery_fee': order['delivery_fee'],
          'packaging_fee': order['packaging_fee'],
          'tip_amount': order['tip_amount'],
          'coins_applied': order['coins_applied'],
        });
      }

      groupedOrders[rawId] = enrichedItems;
    }

    final sortedKeys = groupedOrders.keys.toList();

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: _ordersAppBar(),
      body: RefreshIndicator(
        onRefresh: () => _fetchActiveOrders(showSpinner: false),
        color: AppTheme.primary,
        child: ListView(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 100),
          children: [
            LastOrderReorderBanner(
              compact: true,
              onAddedToCart: widget.onReorderToCart,
            ),
            if (_activeRequests.isNotEmpty) ...[
              Text('My broadcasts & catering', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.onSurfaceOf(context))),
              const SizedBox(height: 12),
              ..._activeRequests.map((req) => _buildBulkRequestCard(req)),
              const SizedBox(height: 24),
              Divider(color: AppTheme.hairlineOf(context), thickness: 1.5),
              const SizedBox(height: 24),
            ],
            if (sortedKeys.isNotEmpty) ...[
              Text('Regular orders', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.onSurfaceOf(context))),
              const SizedBox(height: 12),
              ...sortedKeys.map((key) {
                final rawOrderIdStr = key;
                final items = groupedOrders[rawOrderIdStr]!;
                final displayOrderIdStr = formatOrderId(rawOrderIdStr, items.first['order_id'].toString());

                double itemsTotal = 0;
                bool canCancelGroup = true;
                bool allCancelled = true;
                bool hasDelivery = false;
                bool isDelivered = false;
                Map<String, dynamic>? trackableItem;

                for (var item in items) {
                  if (!_canCancelOrder(item)) canCancelGroup = false;

                  final status = item['status']?.toString().toLowerCase() ?? '';
                  final serviceType = item['service_type']?.toString().toLowerCase() ?? '';

                  if (serviceType.contains('delivery')) hasDelivery = true;
                  if (!status.contains('cancelled') && !status.contains('rejected')) allCancelled = false;
                  if (status.contains('delivered') || status.contains('completed')) isDelivered = true;

                  if (OrderLifecycle.isTrackable(item['status']?.toString())) {
                    trackableItem = item;
                  }
                }
                if (allCancelled) canCancelGroup = false;

                final bill = orderBillBreakdown(items: items, order: items.first, hasDelivery: hasDelivery);
                itemsTotal = bill.itemsTotal;
                final packagingFee = bill.packagingFee;
                final deliveryFee = bill.deliveryFee;
                final finalGrandTotal = bill.grandTotal;

                String dateTimeString = formatOrderDate(items.first['created_at']?.toString());
                final String smartTimeSlot = _slotLabel(items.first, orderItems: items);

                final groupStatus = items.first['status']?.toString() ?? 'Pending';
                Color statusColor = Colors.green;
                if (groupStatus.toLowerCase().contains('pending') || groupStatus.toLowerCase().contains('new')) {
                  statusColor = Colors.orange;
                }
                if (groupStatus.toLowerCase().contains('cancel') || groupStatus.toLowerCase().contains('reject')) statusColor = Colors.red;

                final orderType = items.first['service_type']?.toString() ?? 'Delivery';
                final serviceTypeStr = orderType.toLowerCase();
                final isPickupOrDineIn = serviceTypeStr.contains('pickup') || serviceTypeStr.contains('dine');
                final addressLabel = isPickupOrDineIn ? 'Pickup: ' : 'Dropoff: ';
                final addressValue = isPickupOrDineIn
                    ? _pickupLabel(items.first, items)
                    : _dropoffLabel(items.first, items);

                return GestureDetector(
                  onTap: () => _showOrderDetailsBottomSheet(
                    context,
                    displayOrderIdStr,
                    dateTimeString,
                    smartTimeSlot,
                    items,
                    itemsTotal,
                    packagingFee,
                    deliveryFee,
                    finalGrandTotal,
                    canCancelGroup,
                    isDelivered,
                    trackableItem,
                  ),
                  child: AppCard(
                    margin: const EdgeInsets.only(bottom: 24),
                    child: Opacity(
                      opacity: allCancelled ? 0.6 : 1.0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceOf(context),
                                  borderRadius: AppTheme.radiusSm,
                                  border: Border.all(color: AppTheme.hairlineOf(context)),
                                ),
                                child: Text(displayOrderIdStr,
                                    style: TextStyle(
                                        color: AppTheme.onSurfaceOf(context), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0)),
                              ),
                              if (items.isNotEmpty)
                                Flexible(
                                  child: DeliveryCountdownSticker(
                                    order: items.first,
                                    timeSlot: smartTimeSlot,
                                    status: items.first['status']?.toString(),
                                    createdAt: items.first['created_at']?.toString(),
                                    orderId: items.first['order_id']?.toString(),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${items.first['quantity']}x ${items.first['title']}',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context))),
                                    if (items.length > 1) ...[
                                      const SizedBox(height: 4),
                                      Text('+ ${items.length - 1} more items', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontStyle: FontStyle.italic)),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                        hasDispatchPhoto(items.first)
                                            ? dispatchPackedLabel(takenAt: orderDispatchPhotoAt(items.first))
                                            : 'Status: $groupStatus',
                                        style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                              Text('₹${finalGrandTotal.toInt()}',
                                  style: TextStyle(color: AppTheme.onSurfaceOf(context).withValues(alpha: 0.55), fontSize: 14, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 🌟 1. Delivery Type Selected
                          Row(
                            children: [
                              const Icon(Icons.local_shipping_outlined, size: 14, color: AppTheme.primary),
                              const SizedBox(width: 6),
                              const Text('Type: ', style: AppTheme.caption),
                              Text(orderType, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context))),
                            ],
                          ),
                          const SizedBox(height: 4),

                          // 🌟 2. Time of the Order Placed
                          Row(
                            children: [
                              const Icon(Icons.access_time, size: 14, color: AppTheme.textMuted),
                              const SizedBox(width: 6),
                              const Text('Placed: ', style: AppTheme.caption),
                              Text(dateTimeString, style: AppTheme.caption),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.event_available, size: 14, color: Colors.green),
                              const SizedBox(width: 6),
                              const Text('Delivery Slot: ', style: AppTheme.caption),
                              Text(smartTimeSlot, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),

                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceOf(context),
                              borderRadius: AppTheme.radiusSm,
                              border: Border.all(color: AppTheme.hairlineOf(context)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(isPickupOrDineIn ? Icons.storefront : Icons.location_on,
                                    size: 14, color: isPickupOrDineIn ? Colors.blue : Colors.red),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text('$addressLabel$addressValue',
                                      style: TextStyle(fontSize: 12, color: AppTheme.onSurfaceOf(context)),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                          if (!isDelivered) ...[
                            Builder(
                              builder: (_) {
                                final pin = items.first['delivery_otp']?.toString().trim() ?? '';
                                if (pin.isEmpty) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withValues(alpha: 0.08),
                                      borderRadius: AppTheme.radiusMd,
                                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                                    ),
                                    child: Text(
                                      'Delivery PIN: $pin — share with driver at the door',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.onSurfaceOf(context),
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                          if (trackableItem != null) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                AppIconAction(
                                  icon: Icons.map_outlined,
                                  tooltip: 'Track',
                                  onPressed: () => _openTracking(trackableItem!, items),
                                ),
                                if (_driverIdOf(items.first) != null) ...[
                                  const SizedBox(width: 8),
                                  AppIconAction(
                                    icon: Icons.phone_outlined,
                                    tooltip: orderAllowsPhoneCall(groupStatus) ? 'Call driver' : 'Chat preferred',
                                    onPressed: orderAllowsPhoneCall(groupStatus)
                                        ? () => _initiateCall(_driverIdOf(items.first)!)
                                        : null,
                                  ),
                                ],
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          Divider(height: 1, color: AppTheme.hairlineOf(context)),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: const [
                              Text('Tap for full details →', style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}