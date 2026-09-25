part of 'helpers.dart';

String mealDietHaystack(Map<String, dynamic> meal) {
  final tags = meal['health_tags'] ?? meal['tags'] ?? meal['ingredients'];
  final tagText = tags is List ? tags.join(' ') : tags?.toString() ?? '';
  return [
    mealDisplayTitle(meal),
    meal['description']?.toString() ?? '',
    meal['category']?.toString() ?? '',
    tagText,
  ].join(' ').toLowerCase();
}

List<String> allergyTokens(String? raw) {
  return (raw ?? '')
      .toLowerCase()
      .split(RegExp(r'[,;/&+]|\band\b'))
      .map((token) => token.trim().replaceFirst(RegExp(r'^(no|without|not)\s+'), ''))
      .where((token) => token.length >= 3 || token == 'egg')
      .toList();
}

bool mealTitleLooksNonVegetarian(Map<String, dynamic>? meal) {
  final hay = mealDietHaystack(meal ?? const {});
  return RegExp(
    r'\b(egg|eggs|chicken|mutton|gosht|keema|fish|prawn|shrimp|meat|pork|bacon|ham|beef|non[- ]?veg)\b',
    caseSensitive: false,
  ).hasMatch(hay);
}

/// Green mark when veg. Accepts bool, 1/0, and "true"/"false" strings.
bool mealIsVegetarian(Map<String, dynamic>? meal) {
  if (meal == null) return true;
  final flag = meal['is_veg'] ?? meal['isVeg'];
  if (flag == true || flag == 1) return true;
  if (flag == false || flag == 0) return false;
  final text = flag?.toString().trim().toLowerCase() ?? '';
  if (text == 'true' || text == '1' || text == 'yes' || text == 'veg') return true;
  if (text == 'false' || text == '0' || text == 'no' || text.contains('non')) {
    return false;
  }
  return !mealTitleLooksNonVegetarian(meal);
}

bool mealMatchesDietaryPreference(Map<String, dynamic> meal, String? preference) {
  final pref = (preference ?? '').trim().toLowerCase();
  if (pref.isEmpty || pref == 'non-vegetarian' || pref == 'non vegetarian') return true;
  if (!mealIsVegetarian(meal)) return false;
  final haystack = mealDietHaystack(meal);
  if (pref == 'vegan') {
    return !_haystackHasAny(haystack, const [
      'dairy',
      'milk',
      'ghee',
      'butter',
      'paneer',
      'cheese',
      'curd',
      'egg',
      'honey',
    ]);
  }
  if (pref == 'jain') {
    return !_haystackHasAny(haystack, const [
      'onion',
      'garlic',
      'potato',
      'aloo',
      'ginger',
      'root',
    ]);
  }
  return true;
}

bool mealAvoidsAllergies(Map<String, dynamic> meal, String? allergies) {
  final tokens = allergyTokens(allergies);
  if (tokens.isEmpty) return true;
  final haystack = mealDietHaystack(meal);
  return !_haystackHasAny(haystack, tokens);
}

bool mealMatchesCustomerDiet(
  Map<String, dynamic> meal, {
  String? preference,
  String? allergies,
}) {
  return mealMatchesDietaryPreference(meal, preference) && mealAvoidsAllergies(meal, allergies);
}

const List<String> kFeedDietFilters = [
  'All',
  'Veg',
  'Vegan',
  'Jain',
  'High-protein',
  'Millet',
  'Diabetic',
];

const List<String> kChefDietTags = [
  'Jain',
  'High-protein',
  'Millet',
  'Diabetic',
];

String feedDietChipFromPreference(String? preference) {
  switch ((preference ?? '').trim().toLowerCase()) {
    case 'vegetarian':
    case 'veg':
      return 'Veg';
    case 'vegan':
      return 'Vegan';
    case 'jain':
      return 'Jain';
    default:
      return 'All';
  }
}

({int start, int end})? _slotServingRangeMinutes(String? slot) {
  final text = (slot ?? '').trim();
  if (text.isEmpty || isImmediateDeliverySlot(text)) return null;
  final range = _chefScheduleTimeRange(text);
  final clocks = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false).allMatches(range).toList();
  if (clocks.isEmpty) return null;
  int toMins(RegExpMatch m) {
    var h = int.parse(m.group(1)!);
    final ampm = m.group(3)!.toUpperCase();
    if (ampm == 'PM' && h != 12) h += 12;
    if (ampm == 'AM' && h == 12) h = 0;
    return h * 60 + int.parse(m.group(2)!);
  }

  final start = toMins(clocks.first);
  var end = clocks.length >= 2 ? toMins(clocks[1]) : start + 60;
  if (end <= start) end += 24 * 60;
  return (start: start, end: end);
}

bool _homeSlotAllowsDay(String slot, DateTime day, DateTime now) {
  final d = calendarDay(day);
  if (d.isBefore(calendarDay(now))) return false;
  final pinned = parseSlotCalendarDay(slot, now: now);
  if (pinned != null) return calendarDay(pinned) == d;
  final days = chefServingWeekdays(slot);
  if (days != null && days.isNotEmpty) return days.contains(d.weekday);
  return true;
}

bool _kitchenIsClosed(Map<String, dynamic>? chefProfile) {
  if (chefProfile == null) return false;
  final open = chefProfile['is_open'];
  if (open == false) return true;
  return open?.toString().trim().toLowerCase() == 'false';
}

/// Live Order: chef is accepting this plate at [now] (inside today's window).
bool mealSlotIsAcceptingNow(
  Map<String, dynamic> meal, {
  DateTime? now,
  Map<String, dynamic>? chefProfile,
}) {
  if (_kitchenIsClosed(chefProfile)) return false;
  final n = (now ?? DateTime.now()).toLocal();
  final slot = meal['time_slot']?.toString().trim() ?? '';
  if (isImmediateDeliverySlot(slot)) {
    return chefProfile?['is_live'] == true || chefProfile?['is_open'] == true || chefProfile == null;
  }
  if (!_homeSlotAllowsDay(slot, n, n)) return false;
  final range = _slotServingRangeMinutes(slot);
  if (range == null) return false;
  var mins = n.hour * 60 + n.minute;
  if (range.end >= 24 * 60 && mins < range.start) mins += 24 * 60;
  return mins >= range.start && mins < range.end;
}

/// Pre-order: at least one bookable clock slot still ahead of [now].
bool mealHasPreOrderSlot(Map<String, dynamic> meal, {DateTime? now}) {
  final n = (now ?? DateTime.now()).toLocal();
  final slot = meal['time_slot']?.toString().trim() ?? '';
  if (slot.isEmpty || isImmediateDeliverySlot(slot)) return false;
  if (isChefMealArchived(meal)) return false;
  final today = calendarDay(n);
  for (var i = 0; i < 15; i++) {
    final day = today.add(Duration(days: i));
    if (!_homeSlotAllowsDay(slot, day, n)) continue;
    final remaining = futureChefSubSlots(slot, scheduledDate: day, now: n);
    if (remaining.isNotEmpty) return true;
    if (i == 0) {
      final range = _slotServingRangeMinutes(slot);
      if (range != null) {
        final start = DateTime(day.year, day.month, day.day).add(Duration(minutes: range.start));
        if (start.isAfter(n)) return true;
      }
    }
  }
  return false;
}

/// Home quick chips: Live / Pre-order. Default Live keeps the accepting catalog.
bool mealMatchesHomeMode(
  Map<String, dynamic> meal, {
  required String mode,
  Map<String, dynamic>? chefProfile,
  DateTime? now,
}) {
  switch (mode.trim().toLowerCase()) {
    case 'preorder':
    case 'pre-order':
      return mealHasPreOrderSlot(meal, now: now);
    case 'live':
      return mealSlotIsAcceptingNow(meal, now: now, chefProfile: chefProfile);
    default:
      return true;
  }
}

bool mealMatchesFeedDiet(Map<String, dynamic> meal, String? diet) {
  final selected = (diet ?? '').trim();
  if (selected.isEmpty || selected == 'All') return true;
  if (selected == 'Veg' || selected == 'Vegetarian') {
    return mealMatchesDietaryPreference(meal, 'Vegetarian');
  }
  if (selected == 'Vegan') return mealMatchesDietaryPreference(meal, 'Vegan');
  if (selected == 'Jain') return mealMatchesDietaryPreference(meal, 'Jain');

  final haystack = mealDietHaystack(meal);
  if (selected == 'High-protein') {
    return _haystackHasAny(haystack, const [
      'high-protein',
      'high protein',
      'protein-rich',
      'protein rich',
      'highprotein',
      'sprout',
      'soya',
      'soy chunk',
      'quinoa',
    ]);
  }
  if (selected == 'Millet') {
    return _haystackHasAny(haystack, const [
      'millet',
      'jowar',
      'bajra',
      'ragi',
      'nachni',
      'foxtail',
      'barnyard',
      'kodo',
    ]);
  }
  if (selected == 'Diabetic') {
    return _haystackHasAny(haystack, const [
      'diabetic',
      'diabetes',
      'sugar-free',
      'sugar free',
      'low gi',
      'low-gi',
      'no sugar',
      'unsweetened',
    ]);
  }
  return true;
}

List<String> cuisineAliases(String cuisine) {
  switch (cuisine.trim().toLowerCase()) {
    case 'north indian':
      return const ['north indian', 'north-indian', 'mughlai', 'tandoor'];
    case 'punjabi':
      return const ['punjabi', 'amritsari'];
    case 'south indian':
      return const ['south indian', 'south-indian', 'dosa', 'idli', 'sambar', 'uttapam', 'chettinad', 'andhra', 'kerala'];
    case 'maharashtrian':
      return const ['maharashtrian', 'maharashtra', 'malvani', 'kolhapuri', 'misal', 'thalipeeth', 'modak', 'sabudana'];
    case 'snacks':
      return const ['snack', 'snacks', 'chaat', 'pakora', 'samosa', 'farsan'];
    case 'desserts':
      return const ['dessert', 'desserts', 'sweet', 'mithai', 'halwa', 'kheer'];
    case 'healthy':
    case 'healthy & salads':
      return const ['healthy', 'salad', 'salads', 'bowl'];
    default:
      final value = cuisine.trim().toLowerCase();
      return value.isEmpty ? const [] : [value];
  }
}

bool mealMatchesCuisine(Map<String, dynamic> meal, String? cuisine) {
  final selected = (cuisine ?? '').trim();
  if (selected.isEmpty || selected == 'All') return true;
  if (selected.toLowerCase() == 'festival hamper') {
    return isFestivalHamper(meal);
  }
  if (selected.toLowerCase() == 'society night') {
    return isSocietyNight(meal);
  }
  if (selected.toLowerCase() == 'shelf' || selected.toLowerCase() == 'pantry') {
    return isShelfItem(meal);
  }
  final category = meal['category']?.toString().trim().toLowerCase() ?? '';
  final haystack = mealDietHaystack(meal);
  for (final alias in cuisineAliases(selected)) {
    if (alias.isEmpty) continue;
    if (category == alias || category.contains(alias) || haystack.contains(alias)) {
      return true;
    }
  }
  return false;
}

/// Favorites filter must turn off after logout — the Home tab stays alive.
bool feedFavoritesFilterActive({
  required bool signedIn,
  required bool favoritesOnly,
}) {
  return signedIn && favoritesOnly;
}

bool feedFollowingFilterActive({
  required bool signedIn,
  required bool followingOnly,
}) {
  return signedIn && followingOnly;
}

bool canFollowKitchen({String? viewerId, required String chefId}) {
  final kitchen = chefId.trim();
  if (kitchen.isEmpty) return false;
  final viewer = viewerId?.trim() ?? '';
  return viewer != kitchen;
}

class FeedEmptyCopy {
  const FeedEmptyCopy({
    required this.title,
    required this.message,
    this.promptSignIn = false,
    this.clearCategory = false,
  });

  final String title;
  final String message;
  final bool promptSignIn;
  final bool clearCategory;
}

FeedEmptyCopy feedEmptyCopy({
  required bool signedIn,
  required bool favoritesOnly,
  required bool hasFavorites,
  required bool hasSearch,
  String searchQuery = '',
  String category = 'All',
  String diet = 'All',
  bool hasDeliveryPin = false,
  bool followingOnly = false,
  bool hasFollows = false,
  String? offerBrowseGroupKey,
  bool outOfServiceArea = false,
  String homeMode = 'live',
}) {
  if (outOfServiceArea) {
    return FeedEmptyCopy(
      title: 'Not in ${launchCitiesLabel()} yet',
      message: 'HotPotChef is live in ${launchCitiesLabel()} first. Change your pin to a local drop to see kitchens.',
    );
  }
  final favorites = feedFavoritesFilterActive(signedIn: signedIn, favoritesOnly: favoritesOnly);
  final following = feedFollowingFilterActive(signedIn: signedIn, followingOnly: followingOnly);
  final categoryFilter = category != 'All';
  final dietFilter = diet != 'All';
  final filterLabel = [
    if (dietFilter) diet,
    if (categoryFilter) category,
  ].join(' ');
  final hasChipFilter = categoryFilter || dietFilter;

  if (!signedIn && followingOnly) {
    return const FeedEmptyCopy(
      title: 'Sign in to follow kitchens',
      message: 'Follow a home chef and we will ping you when their kitchen opens.',
      promptSignIn: true,
    );
  }
  if (following && !hasFollows) {
    return const FeedEmptyCopy(
      title: 'No kitchens followed yet',
      message: 'Tap a chef and follow the kitchen to get a ping when they open.',
    );
  }
  if (following) {
    return FeedEmptyCopy(
      title: hasChipFilter ? 'No $filterLabel meals from kitchens you follow' : 'No meals from kitchens you follow',
      message: 'Those kitchens are offline or sold out right now. We will ping you when they open.',
      clearCategory: hasChipFilter,
    );
  }
  if (!signedIn && favoritesOnly) {
    return const FeedEmptyCopy(
      title: 'Sign in to see favorites',
      message: 'Saved meals show up here after you sign in.',
      promptSignIn: true,
    );
  }
  if (favorites && !hasFavorites) {
    return const FeedEmptyCopy(
      title: 'No favorites yet',
      message: 'Tap the heart on a dish you love and it will land here.',
    );
  }
  if (favorites) {
    return FeedEmptyCopy(
      title: hasChipFilter ? 'No $filterLabel favorites' : 'No favorites on the menu',
      message: hasChipFilter
          ? 'None of your saved meals match $filterLabel right now. Try All or another chip.'
          : 'Your saved meals are not on the menu right now.',
      clearCategory: hasChipFilter,
    );
  }
  if (hasSearch) {
    final offerKey = offerBrowseGroupKey?.trim() ?? '';
    if (offerKey.isNotEmpty) {
      final label = offerFlashGroupLabel(offerKey);
      return FeedEmptyCopy(
        title: 'No $label plates nearby',
        message: offerFlashGroupBrowseHint(offerKey),
      );
    }
    final q = searchQuery.trim();
    return FeedEmptyCopy(
      title: 'No dishes or chefs found',
      message: q.isEmpty
          ? 'Try a different search.'
          : 'Nothing matched "$q". Try another dish name or home chef.',
    );
  }
  final mode = homeMode.trim().toLowerCase();
  if ((mode == 'preorder' || mode == 'pre-order') && !hasSearch && !favorites && !following) {
    return const FeedEmptyCopy(
      title: 'No pre-order slots nearby',
      message: 'Kitchens with a booked clock slot show here. Try Live Order for ASAP plates.',
    );
  }
  if (hasChipFilter) {
    return FeedEmptyCopy(
      title: 'No $filterLabel meals',
      message: hasDeliveryPin
          ? 'No $filterLabel kitchens are delivering to this pin right now. Try another chip or address.'
          : 'No $filterLabel dishes are on the menu right now. Try All or another chip.',
      clearCategory: true,
    );
  }
  return FeedEmptyCopy(
    title: hasDeliveryPin ? 'No meals found' : 'Drop a pin to see kitchens',
    message: hasDeliveryPin
        ? 'No kitchens are delivering to this pin right now. Try another address or category.'
        : 'Turn on location or choose an address. We do not guess a city for you.',
  );
}
