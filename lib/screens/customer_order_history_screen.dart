// lib/screens/customer_order_history_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

import '../utils/helpers.dart';
import '../utils/app_theme.dart';
import '../widgets/customer_ui_components.dart';

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
    final chefName = items.isNotEmpty ? (items.first['chef_name'] ?? 'Home Chef') : 'Home Chef';
    final status = orderRecord['status']?.toString() ?? 'Completed';
    final orderType = orderRecord['order_type']?.toString() ?? (items.isNotEmpty ? (items.first['service_type']?.toString() ?? 'Delivery') : 'Delivery');
    final addressValue = orderRecord['delivery_address']?.toString() ?? (items.isNotEmpty ? (items.first['delivery_address']?.toString() ?? 'Unknown Address') : 'Unknown Address');

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
                        const Text('Order History Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Support chat coming soon!'))),
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
                              const Icon(Icons.location_on, size: 14, color: Colors.red),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text('Address: $addressValue',
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
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(chefName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMain)),
                                const Text('Home Kitchen', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                              ],
                            ),
                          ]),
                          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Colors.black12)),
                          Text('Order ID: $displayOrderIdStr', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          ...items.map((item) {
                            double parsedPrice = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
                            int parsedQty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;

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
                                          Text('Slot: ${item['time_slot']}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
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
                        ],
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
        body: const Center(child: Text('Please sign in to view your order history.', style: TextStyle(color: AppTheme.textMuted))),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Order History', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMain)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textMain),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('orders')
            .stream(primaryKey: ['id'])
            .eq('customer_id', user.id)
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }

          if (snapshot.hasError) {
            FirebaseCrashlytics.instance.recordError(snapshot.error, snapshot.stackTrace, reason: 'Order history stream failure');
            return const Center(child: Text('Failed to load order history.', style: TextStyle(color: AppTheme.textMuted)));
          }

          final allOrders = snapshot.data ?? [];

          final pastOrders = allOrders.where((order) {
            final status = order['status']?.toString().toLowerCase() ?? '';
            return status == 'delivered' ||
                status == 'completed' ||
                status == 'cancelled' ||
                status == 'rejected';
          }).toList();

          if (pastOrders.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No past order history found.',
                        style: TextStyle(color: AppTheme.textMain, fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 6),
                    Text('Completed or cancelled orders will appear here.',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                    
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: pastOrders.length,
            itemBuilder: (context, index) {
              final order = pastOrders[index];
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
                    double itemsTotal = totalPrice;
                    double packagingFee = items.isNotEmpty ? 20.0 : 0.0;
                    double deliveryFee = (order['order_type']?.toString().toLowerCase() ?? '').contains('delivery') ? 40.0 : 0.0;
                    double finalGrandTotal = itemsTotal + packagingFee + deliveryFee;

                    String deliveryTimeStr = 'ASAP';
                    if (items.isNotEmpty) {
                      final item = items.first;
                      deliveryTimeStr = item['selected_date'] != null && item['exact_time'] != null
                          ? "${item['selected_date']} at ${item['exact_time']}"
                          : (item['time_slot']?.toString() ?? 'ASAP');
                    }

                    _showOrderDetailsBottomSheet(
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
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSuccessful ? Colors.green.shade50 : Colors.red.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  color: isSuccessful ? Colors.green.shade700 : Colors.red.shade700,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(title,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
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
                              children: const [
                                Text('View Details', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                SizedBox(width: 4),
                                Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}