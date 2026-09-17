import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/diner_locale.dart';

void main() {
  test('diner locale falls back to English', () {
    expect(normalizeDinerLocale('HI'), 'hi');
    expect(normalizeDinerLocale('mr'), 'mr');
    expect(normalizeDinerLocale('gu'), 'en');
    expect(dinerCopy('hi').home, 'होम');
    expect(dinerCopy('mr').cart, 'कार्ट');
    expect(dinerCopy('en').notifications, 'Notifications');
  });
}
