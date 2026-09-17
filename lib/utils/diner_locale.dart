import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kDinerLocaleKey = 'diner_ui_locale';
const kDinerLocales = ['en', 'hi', 'mr'];

String normalizeDinerLocale(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  if (kDinerLocales.contains(value)) return value;
  return 'en';
}

String dinerLocaleLabel(String? locale) {
  switch (normalizeDinerLocale(locale)) {
    case 'hi':
      return 'हिन्दी';
    case 'mr':
      return 'मराठी';
    default:
      return 'English';
  }
}

class DinerCopy {
  const DinerCopy({
    required this.home,
    required this.cart,
    required this.orders,
    required this.account,
    required this.notifications,
    required this.language,
    required this.familyMember,
    required this.buyMembership,
    required this.cancelMembership,
  });

  final String home;
  final String cart;
  final String orders;
  final String account;
  final String notifications;
  final String language;
  final String familyMember;
  final String buyMembership;
  final String cancelMembership;
}

DinerCopy dinerCopy(String? locale) {
  switch (normalizeDinerLocale(locale)) {
    case 'hi':
      return const DinerCopy(
        home: 'होम',
        cart: 'कार्ट',
        orders: 'ऑर्डर',
        account: 'अकाउंट',
        notifications: 'सूचनाएँ',
        language: 'भाषा',
        familyMember: 'Family member',
        buyMembership: 'Family member लें',
        cancelMembership: 'मेंबरशिप रद्द करें',
      );
    case 'mr':
      return const DinerCopy(
        home: 'होम',
        cart: 'कार्ट',
        orders: 'ऑर्डर',
        account: 'अकाउंट',
        notifications: 'सूचना',
        language: 'भाषा',
        familyMember: 'Family member',
        buyMembership: 'Family member घ्या',
        cancelMembership: 'मेंबरशिप रद्द करा',
      );
    default:
      return const DinerCopy(
        home: 'Home',
        cart: 'Cart',
        orders: 'Orders',
        account: 'Account',
        notifications: 'Notifications',
        language: 'Language',
        familyMember: 'Family member',
        buyMembership: 'Become a Family member',
        cancelMembership: 'Cancel membership',
      );
  }
}

class DinerLocaleController extends ChangeNotifier {
  DinerLocaleController._();
  static final DinerLocaleController instance = DinerLocaleController._();

  String _code = 'en';
  String get code => _code;
  DinerCopy get copy => dinerCopy(_code);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _code = normalizeDinerLocale(prefs.getString(kDinerLocaleKey));
    notifyListeners();
  }

  Future<void> setCode(String locale) async {
    final next = normalizeDinerLocale(locale);
    if (next == _code) return;
    _code = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kDinerLocaleKey, next);
    notifyListeners();
  }
}
