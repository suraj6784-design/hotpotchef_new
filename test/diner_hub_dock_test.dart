import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/widgets/diner_storefront.dart';

void main() {
  test('cart tab does not highlight Home on the diner dock', () {
    expect(dinerHubDockIndex(0), 0);
    expect(dinerHubDockIndex(1), -1);
    expect(dinerHubDockIndex(2), 1);
    expect(dinerHubDockIndex(3), 2);
    expect(dinerHubDockIndex(4), 3);
  });
}
