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
  });

  test('home meal catalog select never asks for embedding or order PII', () {
    expect(kHomeMealCatalogSelect.contains('embedding'), isFalse);
    expect(kHomeMealCatalogSelect.contains('customer_phone'), isFalse);
    expect(kHomeMealCatalogSelect.contains('razorpay_'), isFalse);
    expect(kHomeMealCatalogSelectMinimal.contains('embedding'), isFalse);
    expect(kHomeMealCatalogSelect.contains('id'), isTrue);
    expect(kHomeMealCatalogSelect.contains('chef_id'), isTrue);
  });
}
