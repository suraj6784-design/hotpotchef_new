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
    required this.add,
    required this.pay,
    required this.payThisPlate,
    required this.track,
    required this.help,
    required this.viewCart,
    required this.forYou,
    required this.adjustBill,
    required this.verified,
    required this.socialChefs,
    required this.socialChefsSub,
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
  final String add;
  final String pay;
  final String payThisPlate;
  final String track;
  final String help;
  final String viewCart;
  final String forYou;
  final String adjustBill;
  final String verified;
  final String socialChefs;
  final String socialChefsSub;
}

DinerCopy dinerCopy(String? locale) {
  switch (normalizeDinerLocale(locale)) {
    case 'hi':
      return const DinerCopy(
        home: 'होम',
        cart: 'कार्ट',
        orders: 'ऑर्डर',
        account: 'प्रोफ़ाइल',
        notifications: 'अलर्ट',
        language: 'भाषा',
        familyMember: 'Family member',
        buyMembership: 'Family member लें',
        cancelMembership: 'मेंबरशिप रद्द करें',
        add: 'जोड़ें',
        pay: 'पे',
        payThisPlate: 'इस प्लेट पर पे',
        track: 'ट्रैक',
        help: 'मदद',
        viewCart: 'कार्ट देखें',
        forYou: 'आपके लिए',
        adjustBill: 'बिल बदलें',
        verified: 'वेरिफाइड',
        socialChefs: 'आपके फेवरिट सोशल शेफ, अब HotPotChef पर',
        socialChefsSub: 'YouTube, Instagram और Facebook वाले रेसिपी शेफ — आपके शहर में, FSSAI के साथ।',
      );
    case 'mr':
      return const DinerCopy(
        home: 'होम',
        cart: 'कार्ट',
        orders: 'ऑर्डर',
        account: 'प्रोफाइल',
        notifications: 'अलर्ट',
        language: 'भाषा',
        familyMember: 'Family member',
        buyMembership: 'Family member घ्या',
        cancelMembership: 'मेंबरशिप रद्द करा',
        add: 'जोडा',
        pay: 'पे',
        payThisPlate: 'या प्लेटवर पे',
        track: 'ट्रॅक',
        help: 'मदत',
        viewCart: 'कार्ट पहा',
        forYou: 'तुमच्यासाठी',
        adjustBill: 'बिल बदला',
        verified: 'व्हेरिफाइड',
        socialChefs: 'तुमचे फेवरिट सोशल शेफ, आता HotPotChef वर',
        socialChefsSub: 'YouTube, Instagram आणि Facebook वरील रेसिपी शेफ — तुमच्या शहरात, FSSAI सोबत.',
      );
    default:
      return const DinerCopy(
        home: 'Home',
        cart: 'Cart',
        orders: 'Orders',
        account: 'Profile',
        notifications: 'Alerts',
        language: 'Language',
        familyMember: 'Family member',
        buyMembership: 'Become a Family member',
        cancelMembership: 'Cancel membership',
        add: 'Add',
        pay: 'Pay',
        payThisPlate: 'Pay on this plate',
        track: 'Track',
        help: 'Help',
        viewCart: 'View cart',
        forYou: 'For you',
        adjustBill: 'Adjust bill',
        verified: 'Verified',
        socialChefs: 'Your favourite social chef, on HotPotChef',
        socialChefsSub: 'Recipe creators from YouTube, Instagram and Facebook — cooking in your city with FSSAI.',
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
