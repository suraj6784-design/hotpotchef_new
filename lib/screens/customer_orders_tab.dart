// lib/screens/customer_orders_tab.dart

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'dart:convert';
import '../utils/helpers.dart';
import '../utils/network.dart';
import '../utils/support.dart';
import '../widgets/customer_ui_components.dart';
import '../widgets/app_widgets.dart';
import '../widgets/meal_review_dialog.dart';
import '../services/order_lifecycle.dart';

class CustomerOrdersTab extends StatefulWidget {
  final VoidCallback onProfileTap;
  final VoidCallback onLogout;

  const CustomerOrdersTab({super.key, required this.onProfileTap, required this.onLogout});

  @override
  State<CustomerOrdersTab> createState() => _CustomerOrdersTabState();
}

class _CustomerOrdersTabState extends State<CustomerOrdersTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _activeOrders = [];
  List<Map<String, dynamic>> _activeRequests = [];
  bool _isLoading = true;

  StreamSubscription? _ordersSub;
  StreamSubscription? _reqsSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initScopedStreams();
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    _reqsSub?.cancel();
    super.dispose();
  }

  // --- Scoped Realtime Subscriptions with Fallbacks ---

  void _initScopedStreams() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final userId = user.id;

    try {
      // 1. Initial manual fetch to guarantee data loads even if stream delays or misses
      final initialOrders = await supabase
          .from('orders')
          .select()
          .or('customer_id.eq.$userId,user_id.eq.$userId')
          .order('created_at', ascending: false);

      if (mounted) {
        final active = (initialOrders as List).where((order) {
          final status = order['status']?.toString().toLowerCase() ?? '';
          return !status.contains('delivered') && 
                 !status.contains('completed') && 
                 !status.contains('cancelled') && 
                 !status.contains('rejected');
        }).map((e) => Map<String, dynamic>.from(e)).toList();

        setState(() {
          _activeOrders = active;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Initial orders fetch fallback error: $e');
    }

    // 2. Scoped Orders Realtime Stream
    _ordersSub = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen(
      (data) {
        if (mounted) {
          final active = data.where((order) {
            final orderCustomer = order['customer_id']?.toString() ?? order['user_id']?.toString() ?? '';
            if (orderCustomer != userId) return false;

            final status = order['status']?.toString().toLowerCase() ?? '';
            return !status.contains('delivered') && 
                   !status.contains('completed') && 
                   !status.contains('cancelled') && 
                   !status.contains('rejected');
          }).toList();

          setState(() {
            _activeOrders = active;
            _isLoading = false;
          });
        }
      },
      onError: (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Customer orders stream error');
        if (mounted) setState(() => _isLoading = false);
      },
    );

    // 3. Scoped Bulk Requests Stream
    _reqsSub = supabase
        .from('customer_requests')
        .stream(primaryKey: ['id'])
        .eq('customer_id', userId)
        .order('created_at', ascending: false)
        .listen(
      (data) {
        if (mounted) {
          final active = data.where((req) {
            final status = req['status']?.toString().toLowerCase() ?? '';
            return !status.contains('delivered') && 
                   !status.contains('completed') && 
                   !status.contains('cancelled') && 
                   !status.contains('rejected');
          }).toList();

          setState(() {
            _activeRequests = active;
            _isLoading = false;
          });
        }
      },
      onError: (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Customer bulk requests stream error');
      },
    );
  }

  // Delegates to the shared helper so slot resolution (including the
  // "delivery date is never before the order date" guard) stays consistent
  // across every screen.
  String _getSmartTimeSlot(String? originalSlot, DateTime placedDate, {String? selectedDateStr}) =>
      smartTimeSlot(originalSlot, placedDate, selectedDateStr: selectedDateStr);

  bool _canCancelOrder(Map<String, dynamic> order) {
    return OrderLifecycle.canCustomerCancel(order['status']?.toString());
  }

  Future<void> _cancelOrderGroup(List<Map<String, dynamic>> groupItems) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Cancel Order'),
        ]),
        content: const Text(
          'Cancel this order? Inventory will be restored and a refund will be issued to the original payment method (usually 5–7 business days).',
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
    double grandTotal,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );

    try {
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: pw.PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(24),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('HOTPOTCHEF INVOICE', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 12),
                  pw.Text('Order ID: $orderId'),
                  pw.Text('Date: $date'),
                  pw.SizedBox(height: 20),
                  pw.Divider(),
                  ...items.map((item) {
                    double price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
                    int qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
                    return pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 4),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('$qty x ${item['title']}'),
                          pw.Text('Rs. ${(price * qty).toInt()}'),
                        ],
                      ),
                    );
                  }),
                  pw.Divider(),
                  pw.SizedBox(height: 10),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Items Total'), pw.Text('Rs. ${itemsTotal.toInt()}')]),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Packaging'), pw.Text('Rs. ${packagingFee.toInt()}')]),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Delivery'), pw.Text('Rs. ${deliveryFee.toInt()}')]),
                  pw.Divider(thickness: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Grand Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text('Rs. ${grandTotal.toInt()}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Center(child: pw.Text('Payment Mode: Online / Prepaid', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  pw.Center(child: pw.Text('Payment Status: PAID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                ],
              ),
            );
          },
        ),
      );

      final bytes = await pdf.save();
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/HotPotChef_Invoice_$orderId.pdf';

      final file = File(filePath);
      await file.writeAsBytes(bytes);

      if (context.mounted) Navigator.pop(context);

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('Invoice Ready')]),
            content: const Text('Your invoice has been generated securely. You can open it to view, save, or share it.',
                style: TextStyle(fontSize: 13, color: AppTheme.textMain)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Dismiss', style: TextStyle(color: Colors.grey))),
              ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf, size: 16),
                label: const Text('Open Invoice'),
                onPressed: () {
                  Navigator.pop(ctx);
                  OpenFile.open(filePath);
                },
              ),
            ],
          ),
        );
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PDF invoice generation error');
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate invoice: $e'), backgroundColor: Colors.red),
        );
      }
    }
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
    final chefName = items.first['chef_name'] ?? 'Home Chef';
    final chefId = items.first['chef_id'] ?? '';
    final status = items.first['status']?.toString() ?? 'Pending';
    final orderType = items.first['service_type']?.toString() ?? 'Delivery';

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
    } else if (OrderLifecycle.isTrackable(status)) {
      statusIcon = Icons.delivery_dining;
      statusColor = AppTheme.primary;
      statusText = 'Order is on the way / ready';
    } else if (status.toLowerCase().contains('preparing')) {
      statusIcon = Icons.soup_kitchen;
      statusColor = Colors.orange;
      statusText = 'Chef is preparing your food';
    }

    final bool isCancelled = status.toLowerCase().contains('cancelled') || status.toLowerCase().contains('rejected');
    final bool isTrackable = OrderLifecycle.isTrackable(status) && trackableItem != null;

    final serviceTypeStr = items.first['service_type']?.toString().toLowerCase() ?? '';
    final isPickupOrDineIn = serviceTypeStr.contains('pickup') || serviceTypeStr.contains('dine');
    final addressLabel = isPickupOrDineIn ? 'Pickup Location' : 'Delivery Address';
    final addressValue = isPickupOrDineIn
        ? (items.first['hosting_address'] ?? items.first['chef_address'] ?? 'Kitchen Location')
        : (items.first['delivery_address'] ?? 'Unknown Location');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.92,
          decoration: BoxDecoration(color: AppTheme.background, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              Container(
                decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        GestureDetector(onTap: () => Navigator.pop(ctx), child: const Icon(Icons.arrow_back, color: AppTheme.textMain)),
                        const SizedBox(width: 12),
                        const Text('Order Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => showContactSupportSheet(ctx, orderRef: items.first['order_id']?.toString() ?? items.first['id']?.toString()),
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
                              Expanded(child: Text(statusText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMain))),
                            ],
                          ),
                          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: Colors.black12)),
                          
                          // Timings & Delivery Type in Details Sheet
                          Row(
                            children: [
                              const Icon(Icons.local_shipping_outlined, size: 14, color: AppTheme.primary),
                              const SizedBox(width: 6),
                              const Text('Type: ', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                              Text(orderType, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.access_time, size: 14, color: AppTheme.textMuted),
                              const SizedBox(width: 6),
                              const Text('Placed: ', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                              Text(dateTimeString, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textMain)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.event_available, size: 14, color: Colors.green),
                              const SizedBox(width: 6),
                              const Text('Delivery Slot: ', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                              Text(deliveryTimeStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(isPickupOrDineIn ? Icons.storefront : Icons.location_on, size: 14, color: isPickupOrDineIn ? Colors.blue : Colors.red),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text('$addressLabel: $addressValue',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
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
                                Text('Delivered at: ${formatOrderDate(items.first['updated_at']?.toString() ?? items.first['created_at']?.toString())}',
                                    style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                          if (isTrackable) ...[
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.map, size: 20),
                                label: const Text('Track Live Location'),
                                onPressed: () {
                                  context.push('/tracking', extra: {
                                    'order': trackableItem,
                                    'isDriver': false,
                                    'isDineInNavigation': status.toLowerCase().contains('ready') &&
                                        !(items.first['service_type']?.toString().toLowerCase().contains('delivery') ?? false),
                                  });
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
                                    Text(chefName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMain)),
                                    const Text('Home Kitchen', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                                  ],
                                ),
                              ]),
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => context.push('/chat/${items.first['id']}?roomName=Order%20$displayOrderIdStr'),
                                    child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300)), child: const Icon(Icons.chat_bubble_outline, color: AppTheme.primary, size: 18)),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => _initiateCall(chefId),
                                    child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300)), child: const Icon(Icons.phone_outlined, color: Colors.redAccent, size: 18)),
                                  ),
                                ],
                              )
                            ],
                          ),
                          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Colors.black12)),
                          Row(
                            children: [
                              Text('Order ID: $displayOrderIdStr', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              const Icon(Icons.copy, size: 14, color: AppTheme.textMuted)
                            ],
                          ),
                          const SizedBox(height: 16),
                          ...items.map((item) {
                            double parsedPrice = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
                            int parsedQty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;

                            final truePlacedDate = getTrueOrderDateTime(item['order_id']?.toString() ?? '', item['created_at']?.toString());
                            final smartSlot = _getSmartTimeSlot(item['time_slot'], truePlacedDate, selectedDateStr: item['selected_date']?.toString());

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
                                        Text('${item['quantity']} x ${item['title']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                                        const SizedBox(height: 2),
                                        Text('Slot: $smartSlot', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
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
                                  onTap: () => _downloadInvoicePDF(context, displayOrderIdStr, dateTimeString, items, itemsTotal, packagingFee, deliveryFee, finalGrandTotal),
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
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Item total', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)), Text('₹${itemsTotal.toInt()}', style: const TextStyle(color: AppTheme.textMain, fontSize: 13, fontWeight: FontWeight.w500))]),
                          const SizedBox(height: 10),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Packaging fees', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)), Text('₹${packagingFee.toInt()}', style: const TextStyle(color: AppTheme.textMain, fontSize: 13, fontWeight: FontWeight.w500))]),
                          const SizedBox(height: 10),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Delivery fee', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)), Text('₹${deliveryFee.toInt()}', style: const TextStyle(color: AppTheme.textMain, fontSize: 13, fontWeight: FontWeight.w500))]),
                          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: Colors.black12)),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Grand total', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.textMain)), Text('₹${finalGrandTotal.toInt()}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.textMain))]),
                        ],
                      ),
                    ),
                    if (isDelivered)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: FutureBuilder<Map<String, dynamic>?>(
                          future: Supabase.instance.client
                              .from('reviews')
                              .select()
                              .eq('meal_id', items.first['id'])
                              .eq('customer_id', Supabase.instance.client.auth.currentUser?.id ?? '')
                              .maybeSingle(),
                          builder: (context, reviewSnap) {
                            if (reviewSnap.connectionState == ConnectionState.waiting) return const SizedBox();
                            final existingReview = reviewSnap.data;
                            if (existingReview != null) {
                              return OutlinedButton.icon(
                                icon: const Icon(Icons.star, size: 18),
                                label: Text('Rated ${existingReview['rating']}/5 Stars'),
                                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('You have already rated this meal!')),
                                ),
                              );
                            }
                            return OutlinedButton.icon(
                              icon: const Icon(Icons.star_border, size: 18),
                              label: const Text('Rate this meal'),
                              onPressed: () {
                                Navigator.pop(ctx);
                                if (!mounted) return;
                                _showReviewDialog(items.first);
                              },
                            );
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
    final isAccepted = status.toLowerCase() == 'accepted';
    final isCancelled = status.toLowerCase() == 'cancelled';
    final chefName = req['accepted_chef_name'] ?? 'Pending Chef Acceptance';
    final chefId = req['accepted_chef_id'];

    final rawRequestId = req['id']?.toString() ?? '';
    final displayRequestId = rawRequestId.length > 8 ? 'REQ-${rawRequestId.substring(0, 8).toUpperCase()}' : 'REQ-$rawRequestId';

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
                    decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text('Bulk Broadcast', style: TextStyle(color: Colors.purple.shade700, fontWeight: FontWeight.bold, fontSize: 11)),
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
          Text('${req['quantity']}x ${req['title']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
          const SizedBox(height: 4),
          Text('Budget: ₹${req['budget']}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Row(children: [const Icon(Icons.calendar_today, size: 14, color: AppTheme.textMuted), const SizedBox(width: 6), Text('Needed By: ${req['target_date_time']}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12))]),
          if (isAccepted) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: Colors.black12)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [const Icon(Icons.person, size: 16, color: Colors.green), const SizedBox(width: 6), Text('Accepted by: $chefName', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13))]),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _initiateCall(chefId),
                      child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.15), shape: BoxShape.circle), child: const Icon(Icons.phone, color: Colors.teal, size: 16)),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => context.push('/chat/${req['id']}?roomName=${Uri.encodeComponent(chefName)}'),
                      child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.15), shape: BoxShape.circle), child: const Icon(Icons.chat_bubble, color: Colors.blue, size: 16)),
                    ),
                  ],
                )
              ],
            ),
          ] else if (!isCancelled) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () async {
                  await Supabase.instance.client.from('customer_requests').update({'status': 'Cancelled'}).eq('id', req['id']);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Broadcast cancelled'), backgroundColor: Colors.orange));
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
        appBar: AppBar(title: const Text('My Orders')),
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
        appBar: AppBar(title: const Text('My Orders')),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    if (_activeOrders.isEmpty && _activeRequests.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Orders')),
        body: EmptyState(
          icon: Icons.soup_kitchen_outlined,
          title: 'No active orders',
          message: 'When a chef accepts your meal, it will appear here with live status.',
          actionLabel: 'Refresh Orders',
          onAction: () {
            setState(() => _isLoading = true);
            _initScopedStreams();
          },
        ),
      );
    }

    Map<String, List<Map<String, dynamic>>> groupedOrders = {};
    for (var order in _activeOrders) {
      final rawId = order['id'].toString();
      List<dynamic> parsedItems = [];
      try {
        parsedItems = jsonDecode(order['items']?.toString() ?? '[]');
      } catch (_) {}

      List<Map<String, dynamic>> enrichedItems = [];
      for (var item in parsedItems) {
        if (item is Map) {
          enrichedItems.add({
            ...item.cast<String, dynamic>(),
            'order_id': order['id'],
            'chef_id': order['chef_id'],
            'status': order['status'] ?? 'New Order',
            'service_type': order['order_type'] ?? order['service_type'] ?? 'Delivery',
            'delivery_address': order['delivery_address'],
            'driver_id': order['delivery_partner_id'],
            'created_at': order['created_at'] ?? DateTime.now().toIso8601String(),
          });
        }
      }

      if (enrichedItems.isEmpty) {
        enrichedItems.add({
          'order_id': order['id'],
          'chef_id': order['chef_id'],
          'status': order['status'] ?? 'New Order',
          'service_type': order['order_type'] ?? 'Delivery',
          'delivery_address': order['delivery_address'],
          'driver_id': order['delivery_partner_id'],
          'created_at': order['created_at'] ?? DateTime.now().toIso8601String(),
          'title': order['title'] ?? 'Custom Order',
          'quantity': 1,
          'price': order['total_price'] ?? order['price'] ?? 0,
        });
      }

      groupedOrders[rawId] = enrichedItems;
    }

    final sortedKeys = groupedOrders.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.asset('assets/app_icon.png', height: 24, width: 24)),
            const SizedBox(width: 8),
            const Text('My Orders'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.person, color: AppTheme.primary), onPressed: widget.onProfileTap),
          IconButton(icon: const Icon(Icons.logout, color: Colors.grey), onPressed: widget.onLogout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _initScopedStreams(),
        color: AppTheme.primary,
        child: ListView(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 100),
          children: [
            if (_activeRequests.isNotEmpty) ...[
              const Text('My Broadcasts & Catering', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.textMain)),
              const SizedBox(height: 12),
              ..._activeRequests.map((req) => _buildBulkRequestCard(req)),
              const SizedBox(height: 24),
              const Divider(color: Colors.black12, thickness: 1.5),
              const SizedBox(height: 24),
            ],
            if (sortedKeys.isNotEmpty) ...[
              const Text('Regular Orders', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.textMain)),
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
                  double itemPrice = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
                  int itemQty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
                  itemsTotal += (itemPrice * itemQty);

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

                double packagingFee = 20.0;
                double deliveryFee = hasDelivery ? 40.0 : 0.0;
                double finalGrandTotal = itemsTotal + packagingFee + deliveryFee;

                String dateTimeString = formatOrderDate(items.first['created_at']?.toString());

                final groupStatus = items.first['status']?.toString() ?? 'Pending';
                Color statusColor = Colors.green;
                if (groupStatus.toLowerCase().contains('pending') || groupStatus.toLowerCase().contains('new')) {
                  statusColor = Colors.orange;
                }
                if (groupStatus.toLowerCase().contains('cancel') || groupStatus.toLowerCase().contains('reject')) statusColor = Colors.red;

                final DateTime truePlacedDate = getTrueOrderDateTime(rawOrderIdStr, items.first['created_at']?.toString());
                final String smartTimeSlot = _getSmartTimeSlot(items.first['time_slot'], truePlacedDate, selectedDateStr: items.first['selected_date']?.toString());

                final orderType = items.first['service_type']?.toString() ?? 'Delivery';
                final serviceTypeStr = orderType.toLowerCase();
                final isPickupOrDineIn = serviceTypeStr.contains('pickup') || serviceTypeStr.contains('dine');
                final addressLabel = isPickupOrDineIn ? 'Pickup: ' : 'Dropoff: ';
                final addressValue = isPickupOrDineIn
                    ? (items.first['hosting_address'] ?? items.first['chef_address'] ?? 'Kitchen Location')
                    : (items.first['delivery_address'] ?? 'Unknown Location');

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
                                  color: AppTheme.background,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Text(displayOrderIdStr,
                                    style: const TextStyle(
                                        color: AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0)),
                              ),
                              if (items.isNotEmpty)
                                DeliveryCountdownSticker(
                                  timeSlot: smartTimeSlot,
                                  status: items.first['status'],
                                  createdAt: items.first['created_at']?.toString(),
                                  orderId: items.first['order_id']?.toString(),
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
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                                    if (items.length > 1) ...[
                                      const SizedBox(height: 4),
                                      Text('+ ${items.length - 1} more items', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontStyle: FontStyle.italic)),
                                    ],
                                    const SizedBox(height: 4),
                                    Text('Status: $groupStatus',
                                        style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                              Text('₹${finalGrandTotal.toInt()}',
                                  style: const TextStyle(color: Colors.black38, fontSize: 14, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 🌟 1. Delivery Type Selected
                          Row(
                            children: [
                              const Icon(Icons.local_shipping_outlined, size: 14, color: AppTheme.primary),
                              const SizedBox(width: 6),
                              const Text('Type: ', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                              Text(orderType, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                            ],
                          ),
                          const SizedBox(height: 4),

                          // 🌟 2. Time of the Order Placed
                          Row(
                            children: [
                              const Icon(Icons.access_time, size: 14, color: AppTheme.textMuted),
                              const SizedBox(width: 6),
                              const Text('Placed: ', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                              Text(dateTimeString, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                            ],
                          ),
                          const SizedBox(height: 4),

                          // 🌟 3. Order Delivery Time (Selected Slot)
                          Row(
                            children: [
                              const Icon(Icons.event_available, size: 14, color: Colors.green),
                              const SizedBox(width: 6),
                              const Text('Delivery Slot: ', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                              Text(smartTimeSlot, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),

                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(isPickupOrDineIn ? Icons.storefront : Icons.location_on,
                                    size: 14, color: isPickupOrDineIn ? Colors.blue : Colors.red),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text('$addressLabel$addressValue',
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textMain),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1, color: Colors.black12),
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