import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/delivery_fee.dart';
import 'package:hotpotchef_new/widgets/diner_storefront.dart';

void main() {
  test('cart tab does not highlight Home on the diner dock', () {
    expect(dinerHubDockIndex(0), 0);
    expect(dinerHubDockIndex(1), -1);
    expect(dinerHubDockIndex(2), 1);
    expect(dinerHubDockIndex(3), 2);
    expect(dinerHubDockIndex(4), 3);
    expect(dinerHubIndexForDock(0), 0);
    expect(dinerHubIndexForDock(1), 2);
    expect(dinerHubIndexForDock(2), 3);
    expect(dinerHubIndexForDock(3), 4);
  });

  test('guest diner dock keeps Home, Orders, Account, and Alerts', () {
    expect(dinerHubDockIndex(0, signedIn: false), 0);
    expect(dinerHubDockIndex(1, signedIn: false), -1);
    expect(dinerHubDockIndex(2, signedIn: false), 1);
    expect(dinerHubDockIndex(3, signedIn: false), 2);
    expect(dinerHubDockIndex(4, signedIn: false), 3);
    expect(dinerHubIndexForDock(0, signedIn: false), 0);
    expect(dinerHubIndexForDock(1, signedIn: false), 2);
    expect(dinerHubIndexForDock(3, signedIn: false), 4);
  });

  test('home meal catalog select never asks for embedding or order PII', () {
    expect(kHomeMealCatalogSelect.contains('embedding'), isFalse);
    expect(kHomeMealCatalogSelect.contains('customer_phone'), isFalse);
    expect(kHomeMealCatalogSelect.contains('razorpay_'), isFalse);
    expect(kHomeMealCatalogSelectMinimal.contains('embedding'), isFalse);
    expect(kHomeMealCatalogSelect.contains('id'), isTrue);
    expect(kHomeMealCatalogSelect.contains('chef_id'), isTrue);
    expect(kHomeMealCatalogSelect.contains('hosting_address'), isFalse);
    expect(kHomeMealCatalogSelectMinimal.contains('pickup_lat'), isTrue);
    expect(kHomeMealCatalogSelect.contains('offer_type'), isTrue);
    expect(kHomeMealCatalogSelect.contains('discount_value'), isTrue);
    expect(kHomeMealCatalogSelectMinimal.contains('offer_type'), isTrue);
    expect(kHomeMealCatalogSelectMinimal.contains('discount_value'), isTrue);
  });
}
