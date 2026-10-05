// Occasion groups on the diner home. Meals already carry cuisine, course,
// diet tags, hampers, society nights, and shelf items. This file only
// decides which tab they belong on and how an order remembers that choice.

const String kOccasionEveryday = 'everyday';
const String kOccasionFestive = 'festive';
const String kOccasionParty = 'party';
const String kOccasionSpecialty = 'specialty';
const String kOccasionSliceAll = 'all';

const String kPlanCadenceWeekly = 'weekly';
const String kPlanCadenceMonthly = 'monthly';

const String kBroadcastRequestType = 'broadcast';

class OccasionSlice {
  const OccasionSlice(this.id, this.label);

  final String id;
  final String label;
}

class OccasionTab {
  const OccasionTab({
    required this.id,
    required this.label,
    required this.hint,
    required this.slices,
  });

  final String id;
  final String label;
  final String hint;
  final List<OccasionSlice> slices;

  OccasionSlice? sliceById(String? id) {
    final wanted = (id ?? '').trim();
    for (final slice in slices) {
      if (slice.id == wanted) return slice;
    }
    return null;
  }
}

const List<OccasionTab> kOccasionTabs = [
  OccasionTab(
    id: kOccasionEveryday,
    label: 'Everyday',
    hint: 'Daily lunch and dinner, diet plates, and seasonal food.',
    slices: [
      OccasionSlice(kOccasionSliceAll, 'All'),
      OccasionSlice('lunch', 'Lunch'),
      OccasionSlice('dinner', 'Dinner'),
      OccasionSlice('diet', 'Diet'),
      OccasionSlice('seasonal', 'Seasonal'),
    ],
  ),
  OccasionTab(
    id: kOccasionFestive,
    label: 'Festivals',
    hint: 'Festival sweets, family thalis, and ceremony food.',
    slices: [
      OccasionSlice(kOccasionSliceAll, 'All'),
      OccasionSlice('diwali', 'Diwali'),
      OccasionSlice('holi', 'Holi'),
      OccasionSlice('eid', 'Eid'),
      OccasionSlice('christmas', 'Christmas'),
      OccasionSlice('gathering', 'Gatherings'),
      OccasionSlice('ceremony', 'Ceremonies'),
    ],
  ),
  OccasionTab(
    id: kOccasionParty,
    label: 'Parties',
    hint: 'Birthday, anniversary, office, and community bundles.',
    slices: [
      OccasionSlice(kOccasionSliceAll, 'All'),
      OccasionSlice('birthday', 'Birthday'),
      OccasionSlice('anniversary', 'Anniversary'),
      OccasionSlice('office', 'Office'),
      OccasionSlice('community', 'Community'),
    ],
  ),
  OccasionTab(
    id: kOccasionSpecialty,
    label: 'Specialty',
    hint: 'Pickles, savories, sweets, and seasonal jars you can subscribe to.',
    slices: [
      OccasionSlice(kOccasionSliceAll, 'All'),
      OccasionSlice('pickle', 'Pickles'),
      OccasionSlice('savory', 'Savories'),
      OccasionSlice('sweet', 'Sweets'),
      OccasionSlice('seasonal', 'Seasonal'),
    ],
  ),
];

String? normalizeOccasionId(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'everyday':
    case 'daily':
      return kOccasionEveryday;
    case 'festive':
    case 'festival':
    case 'festivals':
      return kOccasionFestive;
    case 'party':
    case 'parties':
      return kOccasionParty;
    case 'specialty':
      return kOccasionSpecialty;
    default:
      return null;
  }
}

String normalizePlanCadence(String? raw) {
  return (raw ?? '').trim().toLowerCase() == kPlanCadenceMonthly
      ? kPlanCadenceMonthly
      : kPlanCadenceWeekly;
}

OccasionTab occasionTabById(String? id) {
  final normalized = normalizeOccasionId(id) ?? kOccasionEveryday;
  for (final tab in kOccasionTabs) {
    if (tab.id == normalized) return tab;
  }
  return kOccasionTabs.first;
}

String occasionTabLabel(String? id) {
  final normalized = normalizeOccasionId(id);
  if (normalized == null) return '';
  return occasionTabById(normalized).label;
}

String occasionSliceLabel(String? occasion, String? slice) {
  final tab = occasionTabById(occasion);
  final wanted = (slice ?? '').trim();
  if (wanted.isEmpty || wanted == kOccasionSliceAll) return '';
  return tab.sliceById(wanted)?.label ?? '';
}

String occasionBrowseLabel({required String occasion, required String slice}) {
  final sliceLabel = occasionSliceLabel(occasion, slice);
  if (sliceLabel.isEmpty) return occasionTabById(occasion).label;
  return sliceLabel;
}

bool occasionBrowseIsNarrow({required String occasion, required String slice}) {
  return normalizeOccasionId(occasion) != kOccasionEveryday ||
      ((slice).trim().isNotEmpty && slice != kOccasionSliceAll);
}

/// Festivals, Parties, and Specialty can be empty for a pin. Everyday stays
/// on the existing pin-empty path so the home row does not grow a second CTA.
bool occasionEmptyAsksKitchens(String? occasion) {
  switch (normalizeOccasionId(occasion)) {
    case kOccasionFestive:
    case kOccasionParty:
    case kOccasionSpecialty:
      return true;
    default:
      return false;
  }
}

/// Occasion and slice the Ask kitchens screen should open on.
({String occasion, String slice}) resolvedOccasionSelection({
  String? occasion,
  String? slice,
}) {
  final tab = occasionTabById(occasion);
  final sliceId = tab.sliceById(slice)?.id ?? kOccasionSliceAll;
  return (occasion: tab.id, slice: sliceId);
}

/// Same query the home occasion bar sends when it opens Ask kitchens.
String askKitchensLocation({required String occasion, required String slice}) {
  final selected = resolvedOccasionSelection(occasion: occasion, slice: slice);
  return '/bulk-request?occasion=${selected.occasion}&slice=${selected.slice}';
}

/// Festivals and parties are booked for a later day on the existing slot.
bool occasionKeepsFutureSlot(String? occasion) {
  final id = normalizeOccasionId(occasion);
  return id == kOccasionFestive || id == kOccasionParty;
}

String occasionHaystack(Map<String, dynamic> meal) {
  final tags = meal['health_tags'] ?? meal['tags'];
  final tagText = tags is List ? tags.join(' ') : tags?.toString() ?? '';
  return [
    meal['title'],
    meal['name'],
    meal['description'],
    meal['category'],
    meal['cuisine'],
    meal['dish_course'],
    meal['shelf_kind'],
    meal['society_label'],
    tagText,
    meal['time_slot'],
  ].join(' ').toLowerCase();
}

bool _flagTrue(dynamic flag) {
  if (flag == true || flag == 1) return true;
  final text = flag?.toString().trim().toLowerCase() ?? '';
  return text == 'true' || text == '1' || text == 'yes';
}

bool _flagFalse(dynamic flag) {
  if (flag == false || flag == 0) return true;
  final text = flag?.toString().trim().toLowerCase() ?? '';
  return text == 'false' || text == '0' || text == 'no';
}

bool hayHas(String hay, String phrase) {
  final wanted = phrase.trim().toLowerCase();
  if (wanted.isEmpty) return false;
  if (wanted.contains(' ') || wanted.contains('-')) return hay.contains(wanted);
  return RegExp('\\b${RegExp.escape(wanted)}\\b').hasMatch(hay);
}

bool hayHasAny(String hay, List<String> phrases) {
  for (final phrase in phrases) {
    if (hayHas(hay, phrase)) return true;
  }
  return false;
}

int? firstClockHour(String? text) {
  final match = RegExp(
    r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
    caseSensitive: false,
  ).firstMatch(text ?? '');
  if (match == null) return null;
  var hour = int.tryParse(match.group(1)!);
  if (hour == null) return null;
  final ap = match.group(3)!.toLowerCase();
  if (ap == 'pm' && hour != 12) hour += 12;
  if (ap == 'am' && hour == 12) hour = 0;
  return hour;
}

bool _isParty(Map<String, dynamic> meal, String hay) {
  final society = meal['is_society_night'] ?? meal['isSocietyNight'];
  if (!_flagFalse(society) && _flagTrue(society)) return true;
  final category = meal['category']?.toString().toLowerCase() ?? '';
  if (category.contains('society') || category.contains('rwa')) return true;
  return hayHasAny(hay, const [
    'birthday',
    'anniversary',
    'office',
    'community',
    'finger food',
    'society night',
  ]);
}

bool _isFestive(Map<String, dynamic> meal, String hay) {
  final hamper = meal['is_hamper'] ?? meal['isHamper'];
  if (!_flagFalse(hamper) && _flagTrue(hamper)) return true;
  final category = meal['category']?.toString().toLowerCase() ?? '';
  if (category.contains('hamper') || category.contains('festival')) return true;
  if (hayHasAny(hay, const [
    'diwali',
    'holi',
    'gujiya',
    'eid',
    'ramzan',
    'ramadan',
    'christmas',
    'xmas',
    'prasad',
    'sattvic',
    'satvik',
    'fasting',
    'vrat',
    'upvas',
    'housewarming',
    'griha pravesh',
    'grihapravesh',
    'gruh pravesh',
    'naming ceremony',
    'namkaran',
    'naamkaran',
    'family gathering',
    'relatives',
    'bulk',
  ])) {
    return true;
  }
  final thali = hayHas(hay, 'thali');
  return thali &&
      hayHasAny(hay, const ['gathering', 'bulk', 'function', 'family', 'relatives', 'combo']);
}

bool _isSpecialty(Map<String, dynamic> meal, String hay) {
  final shelf = meal['is_shelf_item'] ?? meal['isShelfItem'];
  if (!_flagFalse(shelf) && _flagTrue(shelf)) return true;
  final kind = meal['shelf_kind']?.toString().trim() ?? '';
  if (kind.isNotEmpty) return true;
  final category = meal['category']?.toString().toLowerCase() ?? '';
  if (category.contains('shelf') || category.contains('pantry')) return true;
  return hayHasAny(hay, const [
    'pickle',
    'achar',
    'preserve',
    'murabba',
    'chakli',
    'sev',
    'samosa',
    'pakora',
    'namkeen',
    'farsan',
    'chivda',
    'savory',
    'savoury',
    'laddu',
    'ladoo',
    'peda',
    'halwa',
    'motichoor',
    'barfi',
    'modak',
    'ganesh',
    'ganpati',
    'til',
  ]);
}

String mealOccasionId(Map<String, dynamic> meal) {
  final explicit = normalizeOccasionId(meal['occasion']?.toString());
  if (explicit != null) return explicit;
  final hay = occasionHaystack(meal);
  if (_isParty(meal, hay)) return kOccasionParty;
  if (_isFestive(meal, hay)) return kOccasionFestive;
  if (_isSpecialty(meal, hay)) return kOccasionSpecialty;
  return kOccasionEveryday;
}

bool mealMatchesOccasionSlice(Map<String, dynamic> meal, String occasion, String slice) {
  final wanted = slice.trim();
  if (wanted.isEmpty || wanted == kOccasionSliceAll) return true;
  final hay = occasionHaystack(meal);
  final hour = firstClockHour(meal['time_slot']?.toString());
  switch (normalizeOccasionId(occasion)) {
    case kOccasionEveryday:
      switch (wanted) {
        case 'lunch':
          return hayHasAny(hay, const ['lunch', 'tiffin']) || (hour != null && hour >= 11 && hour < 16);
        case 'dinner':
          return hayHas(hay, 'dinner') || (hour != null && hour >= 17 && hour <= 22);
        case 'diet':
          return hayHasAny(hay, const [
            'diabetic',
            'diabetes',
            'gluten-free',
            'gluten free',
            'vegan',
            'ayurvedic',
            'ayurveda',
            'low-oil',
            'low oil',
            'low-sugar',
            'low sugar',
            'sugar-free',
            'sugar free',
            'healthy',
            'balanced',
          ]);
        case 'seasonal':
          return _flagTrue(meal['is_seasonal']) ||
              hayHasAny(hay, const [
                'seasonal',
                'winter',
                'summer',
                'bhaji',
                'soup',
                'buttermilk',
                'chaas',
                'cooler',
                'light meal',
              ]);
      }
      return false;
    case kOccasionFestive:
      switch (wanted) {
        case 'diwali':
          return hayHas(hay, 'diwali');
        case 'holi':
          return hayHasAny(hay, const ['holi', 'gujiya']);
        case 'eid':
          return hayHasAny(hay, const ['eid', 'ramzan', 'ramadan']);
        case 'christmas':
          return hayHasAny(hay, const ['christmas', 'xmas']);
        case 'gathering':
          return hayHasAny(hay, const ['gathering', 'bulk', 'relatives', 'combo', 'function', 'thali']);
        case 'ceremony':
          return hayHasAny(hay, const [
            'prasad',
            'sattvic',
            'satvik',
            'fasting',
            'vrat',
            'upvas',
            'housewarming',
            'griha pravesh',
            'grihapravesh',
            'naming',
            'namkaran',
            'naamkaran',
          ]);
      }
      return false;
    case kOccasionParty:
      switch (wanted) {
        case 'birthday':
          return hayHasAny(hay, const ['birthday', 'finger food']);
        case 'anniversary':
          return hayHas(hay, 'anniversary');
        case 'office':
          return hayHas(hay, 'office');
        case 'community':
          final society = meal['is_society_night'] ?? meal['isSocietyNight'];
          return (!_flagFalse(society) && _flagTrue(society)) ||
              hayHasAny(hay, const ['community', 'society']);
      }
      return false;
    case kOccasionSpecialty:
      switch (wanted) {
        case 'pickle':
          return hayHasAny(hay, const ['pickle', 'achar', 'preserve', 'murabba']);
        case 'savory':
          return hayHasAny(hay, const [
            'chakli',
            'sev',
            'samosa',
            'pakora',
            'namkeen',
            'farsan',
            'chivda',
            'savory',
            'savoury',
          ]);
        case 'sweet':
          return hayHasAny(hay, const ['laddu', 'ladoo', 'peda', 'halwa', 'motichoor', 'barfi']);
        case 'seasonal':
          return _flagTrue(meal['is_seasonal']) ||
              hayHasAny(hay, const ['til', 'modak', 'ganesh', 'ganpati', 'seasonal']);
      }
      return false;
  }
  return false;
}

bool mealMatchesOccasion(
  Map<String, dynamic> meal,
  String occasion, {
  String slice = kOccasionSliceAll,
}) {
  final group = normalizeOccasionId(occasion);
  if (group == null || mealOccasionId(meal) != group) return false;
  return mealMatchesOccasionSlice(meal, group, slice);
}

Map<String, dynamic> mealWithBrowseOccasion(
  Map<String, dynamic> meal, {
  String? occasion,
}) {
  final id = normalizeOccasionId(occasion) ?? mealOccasionId(meal);
  return {
    ...meal,
    'occasion': id,
  };
}

/// Home tab rule: everyday and specialty follow Live / Pre-order.
/// Festivals and parties also stay listed when a future slot is still bookable.
bool mealListedForOccasion({
  required Map<String, dynamic> meal,
  required String occasion,
  String slice = kOccasionSliceAll,
  required bool matchesHomeMode,
  required bool hasFutureSlot,
  bool ignoreHomeMode = false,
}) {
  if (!mealMatchesOccasion(meal, occasion, slice: slice)) return false;
  if (ignoreHomeMode || matchesHomeMode) return true;
  return occasionKeepsFutureSlot(occasion) && hasFutureSlot;
}

String occasionForCheckoutLine(
  Map<String, dynamic> item,
  Map<String, dynamic> nested,
) {
  final explicit = normalizeOccasionId(item['occasion']?.toString()) ??
      normalizeOccasionId(nested['occasion']?.toString());
  if (explicit != null) return explicit;
  return mealOccasionId({
    ...nested,
    ...item,
  });
}

String? orderOccasionId({
  dynamic column,
  Iterable<Map<String, dynamic>> items = const [],
}) {
  final fromColumn = normalizeOccasionId(column?.toString());
  if (fromColumn != null) return fromColumn;
  for (final item in items) {
    final direct = normalizeOccasionId(item['occasion']?.toString());
    if (direct != null) return direct;
    final nested = item['rawMealDetails'] ?? item['mealDetails'] ?? item['meal_details'];
    if (nested is Map) {
      final inner = normalizeOccasionId(Map<String, dynamic>.from(nested)['occasion']?.toString());
      if (inner != null) return inner;
    }
  }
  return null;
}

String broadcastOccasionLabel(Map<String, dynamic> request) {
  final id = normalizeOccasionId(request['occasion']?.toString());
  if (id != null) {
    final tab = occasionTabById(id).label;
    final slice = occasionSliceLabel(id, request['occasion_slice']?.toString());
    return slice.isEmpty ? tab : '$tab · $slice';
  }
  final description = request['description']?.toString() ?? '';
  final match = RegExp(r'^Occasion:\s*(.+)$', multiLine: true).firstMatch(description);
  final captured = match?.group(1)?.trim() ?? '';
  return captured;
}

/// Insert body for the existing catering broadcast. Empty target_chef_ids
/// means every nearby kitchen, which is the current open-lead rule.
Map<String, dynamic> occasionBroadcastInsert({
  required String customerId,
  required String occasion,
  String slice = kOccasionSliceAll,
  String note = '',
  String details = '',
  required int quantity,
  required String address,
  required DateTime targetLocal,
  required String serviceType,
  double? budget,
  double? latitude,
  double? longitude,
  String? customerName,
  String? customerEmail,
  String? customerPhone,
}) {
  final tab = occasionTabById(occasion);
  final sliceId = tab.sliceById(slice)?.id ?? kOccasionSliceAll;
  final sliceLabel = occasionSliceLabel(tab.id, sliceId);
  final title = note.trim().isEmpty
      ? (sliceLabel.isEmpty ? '${tab.label} request' : '${tab.label}: $sliceLabel')
      : note.trim();
  final qty = quantity < 1 ? 1 : quantity;
  final description = [
    'Occasion: ${sliceLabel.isEmpty ? tab.label : '${tab.label} · $sliceLabel'}',
    if (details.trim().isNotEmpty) details.trim(),
  ].join('\n');
  return {
    'customer_id': customerId,
    if ((customerName ?? '').trim().isNotEmpty) 'customer_name': customerName!.trim(),
    if ((customerEmail ?? '').trim().isNotEmpty) 'customer_email': customerEmail!.trim(),
    if ((customerPhone ?? '').trim().isNotEmpty) 'customer_phone': customerPhone!.trim(),
    'title': title,
    'description': description,
    'quantity': qty,
    'remaining_quantity': qty,
    'budget': budget ?? 0,
    'service_type': serviceType,
    'request_type': kBroadcastRequestType,
    'delivery_address': address,
    'target_date_time': targetLocal.toUtc().toIso8601String(),
    'status': 'Open',
    'occasion': tab.id,
    'occasion_slice': sliceId == kOccasionSliceAll ? null : sliceId,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    'target_chef_ids': <String>[],
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };
}

/// customer_requests.customer_email and customer_phone are both NOT NULL.
/// Email login leaves auth.phone empty even when public.users has a number.
const String kBroadcastMissingContactMessage =
    'Add a phone number and email on your profile before broadcasting to kitchens.';
const String kBroadcastMissingPhoneMessage =
    'Add a phone number on your profile so kitchens can reach you, then try again.';
const String kBroadcastMissingEmailMessage =
    'Add an email on your profile so kitchens can reach you, then try again.';

class BroadcastDinerContact {
  const BroadcastDinerContact({
    this.name = '',
    this.email = '',
    this.phone = '',
    this.blockMessage,
  });

  final String name;
  final String email;
  final String phone;
  final String? blockMessage;

  bool get canInsert => blockMessage == null;
}

String? _broadcastText(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

String? _broadcastEmail(String? raw) {
  final text = _broadcastText(raw);
  if (text == null || !text.contains('@')) return null;
  return text;
}

/// First real phone. Indian mobiles are stored as 10 digits, matching
/// rows that already inserted. Dummy numbers are skipped so the profile
/// phone can fill an empty auth phone.
String? _broadcastPhone(String? raw) {
  final text = _broadcastText(raw);
  if (text == null) return null;
  var digits = text.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('91') && digits.length >= 12) {
    digits = digits.substring(digits.length - 10);
  } else if (digits.length > 10) {
    digits = digits.substring(digits.length - 10);
  }
  final placeholder = digits.isEmpty ||
      digits == '1234567890' ||
      digits == '0123456789' ||
      (digits.length >= 10 && RegExp(r'^(\d)\1+$').hasMatch(digits));
  if (!placeholder && digits.length == 10 && RegExp(r'^[6-9]').hasMatch(digits)) {
    return digits;
  }
  if (placeholder) return null;
  return text;
}

String? _firstPhone(List<String?> values) {
  for (final value in values) {
    final phone = _broadcastPhone(value);
    if (phone != null) return phone;
  }
  return null;
}

String? _firstEmail(List<String?> values) {
  for (final value in values) {
    final email = _broadcastEmail(value);
    if (email != null) return email;
  }
  return null;
}

String _firstName(List<String?> values) {
  for (final value in values) {
    final name = _broadcastText(value);
    if (name != null) return name;
  }
  return '';
}

/// Auth account first, then the diner row in public.users.
/// [blockMessage] is set when the insert would still write a null contact.
BroadcastDinerContact resolveBroadcastDinerContact({
  String? authName,
  String? authEmail,
  String? authPhone,
  String? metadataEmail,
  String? metadataPhone,
  String? profileName,
  String? profileFullName,
  String? profileEmail,
  String? profilePhone,
}) {
  final email = _firstEmail([authEmail, metadataEmail, profileEmail]) ?? '';
  final phone = _firstPhone([authPhone, metadataPhone, profilePhone]) ?? '';
  final name = _firstName([authName, profileName, profileFullName]);
  if (email.isEmpty && phone.isEmpty) {
    return BroadcastDinerContact(name: name, blockMessage: kBroadcastMissingContactMessage);
  }
  if (phone.isEmpty) {
    return BroadcastDinerContact(
      name: name,
      email: email,
      blockMessage: kBroadcastMissingPhoneMessage,
    );
  }
  if (email.isEmpty) {
    return BroadcastDinerContact(
      name: name,
      phone: phone,
      blockMessage: kBroadcastMissingEmailMessage,
    );
  }
  return BroadcastDinerContact(name: name, email: email, phone: phone);
}
