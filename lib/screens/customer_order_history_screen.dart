// lib/screens/customer_order_history_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'dart:convert';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

import '../utils/helpers.dart';
import '../utils/network.dart';
import '../utils/support.dart';
import '../widgets/customer_ui_components.dart';
import '../widgets/app_widgets.dart';
import '../widgets/app_status_badge.dart';
import '../widgets/meal_review_dialog.dart';
import '../services/chef_directory.dart';
import '../services/reorder_service.dart';
import '../providers/cart_provider.dart';
import 'customer_hub.dart';

class CustomerOrderHistoryScreen extends StatelessWidget {
  const CustomerOrderHistoryScreen({super.key});

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

  Future<void> _showReviewDialog(BuildContext context, Map order) async {
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
              'meal_id': mealIdFromOrderItem(Map<String, dynamic>.from(order)) ?? order['id'],
              'customer_id': user.id,
              'chef_id': order['chef_id'],
              'rating': rating,
              'comment': comment,
            });
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(networkErrorMessage(e)), backgroundColor: Colors.red),
              );
            }
            rethrow;
          }
        },
      ),
    );

    if (!context.mounted || submitted != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Review submitted!'), backgroundColor: Colors.green),
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
    bool isDelivered,
    Map<String, dynamic> orderRecord,
  ) {
    final hasDelivery = (orderRecord['order_type']?.toString().toLowerCase() ?? '').contains('delivery');
    final bill = orderBillBreakdown(items: items, order: orderRecord, hasDelivery: hasDelivery);
    itemsTotal = bill.itemsTotal;
    packagingFee = bill.packagingFee;
    deliveryFee = bill.deliveryFee;
    finalGrandTotal = bill.grandTotal;

    final chefId = orderRecord['chef_id']?.toString() ??
        (items.isNotEmpty ? items.first['chef_id']?.toString() : null);
    final orderType = orderRecord['order_type']?.toString() ?? (items.isNotEmpty ? (items.first['service_type']?.toString() ?? 'Delivery') : 'Delivery');
    final addressValue = orderDropoffAddress(orderRecord, items: items);
    final displayAddress = addressValue.isEmpty ? 'Unknown Address' : addressValue;

    IconData statusIcon = isDelivered ? Icons.check_circle : Icons.cancel;
    Color statusColor = isDelivered ? Colors.green : Colors.red;
    String statusText = isDelivered ? 'Order was delivered' : 'Order Cancelled';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.90,
          decoration: AppTheme.bottomSheetDecoration(isDark: Theme.of(context).brightness == Brightness.dark),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceOf(context),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        GestureDetector(onTap: () => Navigator.pop(ctx), child: Icon(Icons.arrow_back, color: AppTheme.onSurfaceOf(context))),
                        const SizedBox(width: 12),
                        Text('Order history details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context))),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => showContactSupportSheet(
                        ctx,
                        orderNumber: displayOrderIdStr,
                        orderUuid: orderRecord['id']?.toString(),
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
                          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: Colors.black12)),
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
                          if (isDelivered) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.done_all, size: 14, color: Colors.green),
                                const SizedBox(width: 6),
                                const Text('Delivered: ', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                Text(
                                  formatOrderDate(
                                    orderRecord['delivered_at']?.toString() ??
                                        orderRecord['updated_at']?.toString() ??
                                        orderRecord['created_at']?.toString(),
                                  ),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.green),
                                ),
                              ],
                            ),
                          ],
                          if (!isDelivered) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.cancel_outlined, size: 14, color: Colors.redAccent),
                                const SizedBox(width: 6),
                                const Text('Cancelled: ', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                Text(
                                  formatOrderDate(orderRecord['updated_at']?.toString() ?? orderRecord['created_at']?.toString()),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.redAccent),
                                ),
                              ],
                            ),
                          ],
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
                              const Icon(Icons.location_on, size: 14, color: Colors.red),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text('Address: $displayAddress',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AppCard(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            CircleAvatar(backgroundColor: AppTheme.primary.withValues(alpha: 0.1), radius: 20, child: const Icon(Icons.restaurant, color: AppTheme.primary, size: 20)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FutureBuilder<String>(
                                    future: lookupChefDisplayName(
                                      chefId,
                                      hint: items.isNotEmpty ? items.first : orderRecord,
                                    ),
                                    builder: (context, snap) {
                                      final name = snap.data ??
                                          chefDisplayName(
                                            items.isNotEmpty ? items.first : orderRecord,
                                            fallback: 'Loading chef...',
                                          );
                                      return Text(
                                        name,
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.onSurfaceOf(context)),
                                      );
                                    },
                                  ),
                                  const Text('Home kitchen', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Order group',
                              icon: const Icon(Icons.chat_bubble_outline, color: AppTheme.primary),
                              onPressed: () {
                                final roomId = resolvedOrderId(orderRecord) ?? '';
                                if (roomId.isEmpty) return;
                                Navigator.pop(ctx);
                                context.push(chatPath(
                                  roomId,
                                  roomName: 'Order $displayOrderIdStr',
                                  otherUserId: chefId,
                                  memberIds: orderChatMemberIds(orderRecord),
                                  isGroup: true,
                                ));
                              },
                            ),
                          ]),
                          Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: AppTheme.hairlineOf(context))),
                          orderIdCopyRow(context, displayOrderIdStr),
                          const SizedBox(height: 16),
                          ...items.map((item) {
                            double parsedPrice = lineItemUnitPrice(item);
                            int parsedQty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
                            final placedDate = getTrueOrderDateTime(
                              orderRecord['order_id']?.toString() ?? '',
                              orderRecord['created_at']?.toString(),
                            );
                            final itemSlot = smartTimeSlot(
                              item['time_slot']?.toString(),
                              placedDate,
                              selectedDateStr: item['selected_date']?.toString(),
                            );

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
                                        if (item['time_slot'] != null) ...[
                                          const SizedBox(height: 2),
                                          Text('Slot: $itemSlot', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                                        ]
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
                          if (!isDelivered) ...[
                            const SizedBox(height: 10),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Refund amount', style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold)), Text('₹${finalGrandTotal.toInt()}', style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold))]),
                          ],
                        ],
                      ),
                    ),
                    if (isDelivered && items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: FutureBuilder<Map<String, dynamic>?>(
                          future: Supabase.instance.client
                              .from('reviews')
                              .select()
                              .eq('meal_id', mealIdFromOrderItem(items.first) ?? items.first['id'])
                              .eq('customer_id', Supabase.instance.client.auth.currentUser?.id ?? '')
                              .maybeSingle(),
                          builder: (reviewContext, reviewSnap) {
                            if (reviewSnap.connectionState == ConnectionState.waiting) {
                              return const SizedBox();
                            }
                            final existingReview = reviewSnap.data;
                            if (existingReview != null) {
                              return OutlinedButton.icon(
                                icon: const Icon(Icons.star, size: 18),
                                label: Text('Rated ${existingReview['rating']}/5 Stars'),
                                onPressed: () => ScaffoldMessenger.of(reviewContext).showSnackBar(
                                  const SnackBar(content: Text('You have already rated this meal!')),
                                ),
                              );
                            }
                            return OutlinedButton.icon(
                              icon: const Icon(Icons.star_border, size: 18),
                              label: const Text('Rate this meal'),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showReviewDialog(context, items.first);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order History', style: TextStyle(fontWeight: FontWeight.bold))),
        body: const EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Sign in to see history',
          message: 'Completed and cancelled orders will appear here after you log in.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: const HubAppBar(title: 'Order History'),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('orders')
            .stream(primaryKey: ['id'])
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }

          if (snapshot.hasError) {
            FirebaseCrashlytics.instance.recordError(snapshot.error, snapshot.stackTrace, reason: 'Order history stream failure');
            return const EmptyState(
              icon: Icons.wifi_off_rounded,
              title: 'Couldn\'t load history',
              message: 'Check your connection and try again in a moment.',
            );
          }

          final allOrders = snapshot.data ?? [];

          final pastOrders = allOrders.where((order) {
            final owner = order['customer_id']?.toString() ?? order['user_id']?.toString() ?? '';
            if (owner != user.id) return false;
            final status = order['status']?.toString().toLowerCase() ?? '';
            return status == 'delivered' ||
                status == 'completed' ||
                status == 'cancelled' ||
                status == 'rejected';
          }).toList();

          if (pastOrders.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No past orders yet',
              message: 'Completed or cancelled orders will appear here.',
            );
          }

          return _HistoryOrdersList(pastOrders: pastOrders, host: this);
        },
      ),
    );
  }
}

class _HistoryOrdersList extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> pastOrders;
  final CustomerOrderHistoryScreen host;

  const _HistoryOrdersList({required this.pastOrders, required this.host});

  @override
  ConsumerState<_HistoryOrdersList> createState() => _HistoryOrdersListState();
}

class _HistoryOrdersListState extends ConsumerState<_HistoryOrdersList> {
  String _query = '';
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.pastOrders.where((order) {
      final status = order['status']?.toString().toLowerCase() ?? '';
      if (_filter == 'Delivered' && !(status.contains('deliver') || status.contains('complet'))) return false;
      if (_filter == 'Cancelled' && !(status.contains('cancel') || status.contains('reject'))) return false;

      if (_query.trim().isEmpty) return true;
      final rawItems = order['items'] ?? order['cart_items'];
      final haystack = '${order['order_id']} ${order['id']} ${order['status']} $rawItems'.toLowerCase();
      return haystack.contains(_query.trim().toLowerCase());
    }).toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Search meals or order ID',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: ['All', 'Delivered', 'Cancelled'].map((label) {
                    final selected = _filter == label;
                    return ChoiceChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (_) => setState(() => _filter = label),
                    );
                  }).toList(),
                ),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 32),
                    child: EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matching orders',
                      message: 'Try another search or filter.',
                    ),
                  ),
              ],
            ),
          );
        }

        final order = filtered[index - 1];
        final rawId = order['id'].toString();
        final displayId = formatOrderId(order['order_id']?.toString(), rawId);
        final status = order['status']?.toString() ?? 'Completed';

        final rawItems = order['items'] ?? order['cart_items'];
        List<Map<String, dynamic>> items = [];

        if (rawItems is List) {
          items = rawItems.map((e) => Map<String, dynamic>.from(e)).toList();
        } else if (rawItems is String && rawItems.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawItems);
            if (decoded is List) {
              items = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
            }
          } catch (_) {}
        }

        final firstItemTitle = items.isNotEmpty ? items.first['title']?.toString() ?? 'Meal Item' : 'Custom Order';
        final title = items.length > 1
            ? '$firstItemTitle (+${items.length - 1} more)'
            : firstItemTitle;

        final totalPrice = (order['total_price'] as num?)?.toDouble() ??
            (order['total_amount'] as num?)?.toDouble() ??
            (order['price'] as num?)?.toDouble() ??
            0.0;

        final dateStr = formatOrderDate(order['created_at']?.toString());
        final isSuccessful = status.toLowerCase().contains('deliver') || status.toLowerCase().contains('complet');

        return AppCard(
          margin: const EdgeInsets.only(bottom: 14),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              final hasDelivery = (order['order_type']?.toString().toLowerCase() ?? '').contains('delivery');
              final bill = orderBillBreakdown(items: items, order: order, hasDelivery: hasDelivery);
              final itemsTotal = bill.itemsTotal;
              final packagingFee = bill.packagingFee;
              final deliveryFee = bill.deliveryFee;
              final finalGrandTotal = bill.grandTotal;

              String deliveryTimeStr = 'ASAP';
              if (items.isNotEmpty) {
                final item = items.first;
                final truePlacedDate = getTrueOrderDateTime(
                  order['order_id']?.toString() ?? '',
                  order['created_at']?.toString(),
                );
                final baseSlot = item['selected_date'] != null && item['exact_time'] != null
                    ? "${item['selected_date']} at ${item['exact_time']}"
                    : (item['time_slot']?.toString() ?? 'ASAP');
                deliveryTimeStr = smartTimeSlot(
                  baseSlot,
                  truePlacedDate,
                  selectedDateStr: item['selected_date']?.toString(),
                );
              }

              widget.host._showOrderDetailsBottomSheet(
                context,
                displayId,
                dateStr,
                deliveryTimeStr,
                items,
                itemsTotal,
                packagingFee,
                deliveryFee,
                finalGrandTotal,
                isSuccessful,
                order,
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(displayId,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted)),
                      AppStatusBadge(status: status),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context))),
                  const SizedBox(height: 4),
                  Text('Ordered on: $dateStr', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Colors.black12),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total: ₹${totalPrice.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppTheme.primary),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSuccessful)
                            IconButton(
                              tooltip: 'Rate this meal',
                              visualDensity: VisualDensity.compact,
                              onPressed: items.isEmpty
                                  ? null
                                  : () => widget.host._showReviewDialog(context, items.first),
                              icon: const Icon(Icons.star_border, size: 18),
                            ),
                          TextButton.icon(
                            onPressed: items.isEmpty ? null : () => _reorder(items),
                            icon: const Icon(Icons.replay, size: 16),
                            label: const Text('Reorder'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ).entrance(index: index);
      },
    );
  }

  Future<void> _reorder(List<Map<String, dynamic>> items) async {
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
    CustomerHubScreen.returnToCartAfterLogin = true;
    if (context.mounted) context.go('/customer-hub');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ReorderService.resultMessage(result))),
    );
  }
}