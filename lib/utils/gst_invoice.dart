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
    required this.coinsApplied,
    required this.taxableValue,
    required this.cgst,
    required this.sgst,
    required this.grandTotal,
    this.membershipFee = 0,
    this.membershipGst = 0,
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
  final double coinsApplied;
  final double taxableValue;
  final double cgst;
  final double sgst;
  final double grandTotal;
  final double membershipFee;
  final double membershipGst;

  double get gstTotal => roundMoney(cgst + sgst);

  String get documentTitle => isTaxInvoice ? 'TAX INVOICE' : 'BILL OF SUPPLY';

  String get legalNote {
    final kitchen = isTaxInvoice
        ? 'GST @ ${(gstRate * 100).toStringAsFixed(0)}% is included in food and packaging (HSN $hsn). Delivery is a HotPotChef service, not kitchen supply.'
        : 'The kitchen has not provided a GSTIN, so this is a bill of supply and not a GST tax invoice. Delivery is charged by HotPotChef, not the kitchen.';
    if (membershipFee <= 0) return kitchen;
    return '$kitchen Family member includes GST @ 18% (₹${membershipGst.toStringAsFixed(0)}).';
  }
}

GstInvoiceBreakdown gstInvoiceBreakdown({
  required double itemsTotal,
  required double packagingFee,
  required double deliveryFee,
  double tipAmount = 0,
  double coinsApplied = 0,
  double membershipFee = 0,
  String? chefGstin,
  String? chefName,
  String? fssaiNumber,
  String? chefAddress,
}) {
  final gstin = normalizedGstin(chefGstin);
  final chefSupply = roundMoney(itemsTotal + packagingFee);
  final delivery = roundMoney(deliveryFee);
  final tip = roundMoney(tipAmount);
  final coins = roundMoney(coinsApplied);
  final membership = roundMoney(membershipFee);
  final isTax = gstin != null;
  final taxable = isTax ? roundMoney(chefSupply / (1 + restaurantGstRate)) : chefSupply;
  final gst = isTax ? roundMoney(chefSupply - taxable) : 0.0;
  final cgst = roundMoney(gst / 2);
  final sgst = roundMoney(gst - cgst);
  final membershipGst = membership > 0 ? roundMoney(membership - (membership / 1.18)) : 0.0;

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
    deliveryFee: delivery,
    tipAmount: tip,
    coinsApplied: coins,
    membershipFee: membership,
    membershipGst: membershipGst,
    taxableValue: taxable,
    cgst: cgst,
    sgst: sgst,
    grandTotal: roundMoney(chefSupply + delivery + tip + membership - coins),
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
