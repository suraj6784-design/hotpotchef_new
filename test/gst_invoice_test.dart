import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/gst_invoice.dart';

void main() {
  test('valid GSTIN is required for a tax invoice', () {
    expect(isValidGstin('27AAPFU0939F1ZV'), isTrue);
    expect(isValidGstin(''), isFalse);
    expect(isValidGstin('ABC'), isFalse);
  });

  test('GST-registered kitchen splits inclusive 5% into CGST and SGST', () {
    final bill = gstInvoiceBreakdown(
      itemsTotal: 190,
      packagingFee: 10,
      deliveryFee: 0,
      chefGstin: '27AAPFU0939F1ZV',
      chefName: 'Asha Kitchen',
    );
    expect(bill.isTaxInvoice, isTrue);
    expect(bill.documentTitle, 'TAX INVOICE');
    expect(bill.taxableValue, 190.48);
    expect(bill.gstTotal, 9.52);
    expect(bill.cgst + bill.sgst, bill.gstTotal);
    expect(bill.grandTotal, 200);
  });

  test('kitchen without GSTIN gets a bill of supply', () {
    final bill = gstInvoiceBreakdown(
      itemsTotal: 200,
      packagingFee: 0,
      deliveryFee: 0,
    );
    expect(bill.isTaxInvoice, isFalse);
    expect(bill.documentTitle, 'BILL OF SUPPLY');
    expect(bill.cgst, 0);
    expect(bill.grandTotal, 200);
  });

  test('Aadhaar is stored as last four only', () {
    expect(maskAadhaar('123412341234'), 'XXXX-XXXX-1234');
    expect(isFullAadhaar('123412341234'), isTrue);
    expect(isFullAadhaar('XXXX-XXXX-1234'), isFalse);
  });
}
