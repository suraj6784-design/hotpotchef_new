import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/gst_invoice.dart';
import '../utils/helpers.dart';

class InvoicePdfService {
  static Future<void> download({
    required BuildContext context,
    required String orderId,
    required String date,
    required List<Map<String, dynamic>> items,
    required double itemsTotal,
    required double packagingFee,
    required double deliveryFee,
    double tipAmount = 0,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );

    try {
      final chefId = items.isNotEmpty ? items.first['chef_id']?.toString() : null;
      Map<String, dynamic>? chef;
      if (chefId != null && chefId.isNotEmpty) {
        chef = await Supabase.instance.client
            .from('users')
            .select('name, full_name, gstin, fssai_number, address')
            .eq('id', chefId)
            .maybeSingle();
      }

      final bill = gstInvoiceBreakdown(
        itemsTotal: itemsTotal,
        packagingFee: packagingFee,
        deliveryFee: deliveryFee,
        tipAmount: tipAmount,
        chefGstin: chef?['gstin']?.toString(),
        chefName: chefDisplayName(chef),
        fssaiNumber: chef?['fssai_number']?.toString(),
        chefAddress: chef?['address']?.toString(),
      );

      final bytes = await _buildPdf(
        orderId: orderId,
        date: date,
        items: items,
        bill: bill,
      );
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/HotPotChef_Invoice_$orderId.pdf';
      await File(filePath).writeAsBytes(bytes);

      if (context.mounted) Navigator.pop(context);
      if (!context.mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('Invoice Ready')]),
          content: Text(
            bill.isTaxInvoice
                ? 'GST tax invoice generated with the kitchen GSTIN and 5% tax break-up.'
                : 'Bill of supply generated. A GST tax invoice appears after the kitchen adds a GSTIN.',
            style: TextStyle(fontSize: 13, color: AppTheme.onSurfaceOf(context)),
          ),
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

  static Future<List<int>> _buildPdf({
    required String orderId,
    required String date,
    required List<Map<String, dynamic>> items,
    required GstInvoiceBreakdown bill,
  }) async {
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
                pw.Text('HOTPOTCHEF ${bill.documentTitle}', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Text('Marketplace: HotPotChef  |  Place of supply: India'),
                pw.Text('Kitchen: ${bill.chefName}'),
                if (bill.chefGstin != null) pw.Text('Kitchen GSTIN: ${bill.chefGstin}'),
                if (bill.fssaiNumber.isNotEmpty) pw.Text('FSSAI: ${bill.fssaiNumber}'),
                if (bill.chefAddress.isNotEmpty) pw.Text('Kitchen address: ${bill.chefAddress}'),
                pw.SizedBox(height: 12),
                pw.Text('Order ID: $orderId'),
                pw.Text('Date: $date'),
                pw.Text('HSN / SAC: ${bill.hsn}'),
                pw.SizedBox(height: 16),
                pw.Divider(),
                ...items.map((item) {
                  final price = lineItemUnitPrice(item);
                  final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('$qty x ${item['title']}'),
                        pw.Text('Rs. ${(price * qty).toStringAsFixed(0)}'),
                      ],
                    ),
                  );
                }),
                pw.Divider(),
                pw.SizedBox(height: 8),
                _line('Items', bill.itemsTotal),
                _line('Packaging', bill.packagingFee),
                _line('Delivery', bill.deliveryFee),
                if (bill.isTaxInvoice) ...[
                  pw.SizedBox(height: 6),
                  _line('Taxable value', bill.taxableValue),
                  _line('CGST @ ${((bill.gstRate / 2) * 100).toStringAsFixed(1)}%', bill.cgst),
                  _line('SGST @ ${((bill.gstRate / 2) * 100).toStringAsFixed(1)}%', bill.sgst),
                ],
                if (bill.tipAmount > 0) _line('Tip (not a taxable supply)', bill.tipAmount),
                pw.Divider(thickness: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Grand Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('Rs. ${bill.grandTotal.toStringAsFixed(0)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.Text(bill.legalNote, style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 8),
                pw.Center(child: pw.Text('Payment Mode: Online / Prepaid', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                pw.Center(child: pw.Text('Payment Status: PAID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
              ],
            ),
          );
        },
      ),
    );
    return pdf.save();
  }

  static pw.Widget _line(String label, double amount) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label),
        pw.Text('Rs. ${amount.toStringAsFixed(0)}'),
      ],
    );
  }
}
