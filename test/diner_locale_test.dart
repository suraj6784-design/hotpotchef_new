import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/diner_locale.dart';

void main() {
  test('diner locale falls back to English', () {
    expect(normalizeDinerLocale('HI'), 'hi');
    expect(normalizeDinerLocale('mr'), 'mr');
    expect(normalizeDinerLocale('gu'), 'en');
    expect(dinerCopy('hi').home, 'होम');
    expect(dinerCopy('mr').cart, 'कार्ट');
    expect(dinerCopy('en').notifications, 'Alerts');
    expect(dinerCopy('hi').payThisPlate, 'इस प्लेट पर पे');
    expect(dinerCopy('mr').help, 'मदत');
    expect(dinerCopy('en').adjustBill, 'Adjust bill');
    expect(dinerCopy('en').forYou, 'For you');
  });
}
