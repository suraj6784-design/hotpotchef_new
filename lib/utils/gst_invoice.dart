import 'helpers.dart';

final gstinRegex = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

bool isValidGstin(String? raw) {
  final value = raw?.trim().toUpperCase() ?? '';
  return gstinRegex.hasMatch(value);
}

String? normalizedGstin(String? raw) {
  final value = raw?.trim().toUpperCase() ?? '';
  return isValidGstin(value) ? value : null;
}

/// Restaurant / catering service under GST. Prices in the app are treated as tax-inclusive.
const double restaurantGstRate = 0.05;
const String restaurantHsn = '9963';

class GstInvoiceBreakdown {
  const GstInvoiceBreakdown({
    required this.isTaxInvoice,
    required this.chefGstin,
    required this.chefName,
    required this.fssaiNumber,
    required this.chefAddress,
    required this.hsn,
    required this.gstRate,
    required this.itemsTotal,
    required this.packagingFee,
    required this.deliveryFee,
    required this.tipAmount,
    required this.taxableValue,
    required this.cgst,
    required this.sgst,
    required this.grandTotal,
  });

  final bool isTaxInvoice;
  final String? chefGstin;
  final String chefName;
  final String fssaiNumber;
  final String chefAddress;
  final String hsn;
  final double gstRate;
  final double itemsTotal;
  final double packagingFee;
  final double deliveryFee;
  final double tipAmount;
  final double taxableValue;
  final double cgst;
  final double sgst;
  final double grandTotal;

  double get gstTotal => roundMoney(cgst + sgst);

  String get documentTitle => isTaxInvoice ? 'TAX INVOICE' : 'BILL OF SUPPLY';

  String get legalNote => isTaxInvoice
      ? 'GST @ ${(gstRate * 100).toStringAsFixed(0)}% is included in the prices charged. HSN $hsn (restaurant / catering service).'
      : 'The kitchen has not provided a GSTIN, so this is a bill of supply and not a GST tax invoice.';
}

GstInvoiceBreakdown gstInvoiceBreakdown({
  required double itemsTotal,
  required double packagingFee,
  required double deliveryFee,
  double tipAmount = 0,
  String? chefGstin,
  String? chefName,
  String? fssaiNumber,
  String? chefAddress,
}) {
  final gstin = normalizedGstin(chefGstin);
  final foodGross = roundMoney(itemsTotal + packagingFee + deliveryFee);
  final tip = roundMoney(tipAmount);
  final isTax = gstin != null;
  final taxable = isTax ? roundMoney(foodGross / (1 + restaurantGstRate)) : foodGross;
  final gst = isTax ? roundMoney(foodGross - taxable) : 0.0;
  final cgst = roundMoney(gst / 2);
  final sgst = roundMoney(gst - cgst);

  return GstInvoiceBreakdown(
    isTaxInvoice: isTax,
    chefGstin: gstin,
    chefName: (chefName ?? '').trim().isEmpty ? 'Home kitchen' : chefName!.trim(),
    fssaiNumber: (fssaiNumber ?? '').trim(),
    chefAddress: (chefAddress ?? '').trim(),
    hsn: restaurantHsn,
    gstRate: restaurantGstRate,
    itemsTotal: roundMoney(itemsTotal),
    packagingFee: roundMoney(packagingFee),
    deliveryFee: roundMoney(deliveryFee),
    tipAmount: tip,
    taxableValue: taxable,
    cgst: cgst,
    sgst: sgst,
    grandTotal: roundMoney(foodGross + tip),
  );
}

String maskAadhaar(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return '';
  return 'XXXX-XXXX-${digits.substring(digits.length - 4)}';
}

bool isFullAadhaar(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  return digits.length == 12 && !(raw ?? '').toUpperCase().contains('X');
}
