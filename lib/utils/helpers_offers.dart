part of 'helpers.dart';

const int kChefBoostRupees = 99;
const int kChefBoostPaise = 9900;

DateTime boostEndsAtLocalMidnight(DateTime now) {
  final local = now.toLocal();
  return DateTime(local.year, local.month, local.day + 1);
}

bool isMealBoosted(Map<String, dynamic>? meal, {DateTime? now}) {
  if (meal == null) return false;
  final until = DateTime.tryParse(meal['boosted_until']?.toString() ?? '');
  if (until == null) return false;
  return !until.toLocal().isBefore((now ?? DateTime.now()).toLocal());
}

String mealBoostUntilLabel(Map<String, dynamic>? meal, {DateTime? now}) {
  if (!isMealBoosted(meal, now: now)) return '';
  final until = DateTime.tryParse(meal?['boosted_until']?.toString() ?? '');
  if (until == null) return 'Boosted today';
  return 'Boosted until ${formatAppTime(until)}';
}

bool mealHasFlashableOffer(Map<String, dynamic> meal, {DateTime? now}) {
  if (!isCatalogMeal(meal) || !mealHasSellableStock(meal)) return false;
  if (mealFailsCurrentCatalogRequirements(meal)) return false;
  if (!isChefMenuActiveMeal(meal, now: now)) return false;
  if (!mealHasBookableSlotNow(meal, now: now)) return false;
  if (isMealBoosted(meal, now: now)) return true;
  final hasOffer = PricingCalculator.resolvedOfferType(meal) != OfferType.none;
  final hasPromo = PricingCalculator.mealPromoCode(meal) != null;
  if (!hasOffer && !hasPromo) return false;
  // Checkout still gates promo codes; Home lists every live family (BOGO, Flash, %, Flat).
  return PricingCalculator.isWithinOfferWindow(meal, referenceTime: now);
}

/// True when a diner can still book this plate on the current local day.
bool mealHasBookableSlotNow(Map<String, dynamic> meal, {DateTime? now}) {
  final n = (now ?? DateTime.now()).toLocal();
  final slot = meal['time_slot']?.toString();
  final days = chefServingWeekdays(slot);
  if (days != null && days.isNotEmpty && !days.contains(n.weekday)) return false;
  if (isChefMealArchived(meal)) return false;
  if (slot == null || slot.trim().isEmpty || isImmediateDeliverySlot(slot)) return false;
  final labeledDay = parseSlotCalendarDay(slot, now: n);
  final selected = DateTime.tryParse(meal['selected_date']?.toString() ?? '');
  final day = selected ?? labeledDay;
  if (day != null && calendarDay(day).isBefore(calendarDay(n))) return false;
  final remaining = futureChefSubSlots(slot, scheduledDate: calendarDay(n), now: n);
  if (remaining.isNotEmpty) return true;
  final clocks =
      RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false).allMatches(slot).toList();
  if (clocks.isEmpty) return true;
  final end = parseClockOnDate(
    (clocks.length >= 2 ? clocks[1] : clocks.first).group(0)!,
    calendarDay(n),
  );
  if (end == null) return true;
  return n.isBefore(end);
}

List<Map<String, dynamic>> flashableOfferMeals(
  Iterable<Map<String, dynamic>> meals, {
  Set<String> excludedChefIds = const {},
  DateTime? now,
  int limit = 8,
  double? destinationLat,
  double? destinationLng,
  Map<String, Map<String, dynamic>> chefKitchenPins = const {},
  bool excludeFestivalHampers = false,
}) {
  final unique = <String>{};
  final offers = <Map<String, dynamic>>[];
  for (final meal in meals) {
    final chefId = meal['chef_id']?.toString() ?? '';
    if (chefId.isNotEmpty && excludedChefIds.contains(chefId)) continue;
    if (excludeFestivalHampers && isFestivalHamper(meal)) continue;
    if (!mealHasFlashableOffer(meal, now: now)) continue;
    final pinned = mealWithKitchenPin(meal, chefPin: chefKitchenPins[chefId]);
    if (!mealInDeliveryRadius(
      pinned,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
    )) {
      continue;
    }
    final id = meal['id']?.toString() ?? meal['title']?.toString() ?? '';
    if (id.isNotEmpty && !unique.add(id)) continue;
    offers.add(pinned);
  }
  offers.sort((a, b) {
    final aBoosted = isMealBoosted(a, now: now);
    final bBoosted = isMealBoosted(b, now: now);
    if (aBoosted != bBoosted) return aBoosted ? -1 : 1;
    return 0;
  });

  // One carousel card per offer family — tap opens every matching plate.
  const groupOrder = <String>[
    'festive',
    'flashSale',
    'bogo',
    'percentage',
    'flat',
  ];
  final buckets = <String, List<Map<String, dynamic>>>{
    for (final key in groupOrder) key: <Map<String, dynamic>>[],
  };
  final rest = <Map<String, dynamic>>[];

  for (final meal in offers) {
    final key = offerFlashGroupKeyForMeal(meal);
    if (key != null && buckets.containsKey(key)) {
      buckets[key]!.add(meal);
    } else {
      rest.add(meal);
    }
  }

  final collapsed = <Map<String, dynamic>>[];
  for (final key in groupOrder) {
    final group = buckets[key]!;
    if (group.isEmpty) continue;
    collapsed.add(buildOfferFlashGroupCard(key, group));
  }
  collapsed.addAll(rest);

  if (collapsed.length <= limit) return collapsed;
  return collapsed.sublist(0, limit);
}

/// Carousel group key for a live meal (festive hampers win over offer_type).
String? offerFlashGroupKeyForMeal(Map<String, dynamic> meal) {
  if (isFestivalHamper(meal)) return 'festive';
  final type = OfferType.fromString(meal['offer_type']?.toString());
  switch (type) {
    case OfferType.bogo:
      return 'bogo';
    case OfferType.flashSale:
      return 'flashSale';
    case OfferType.percentage:
      return 'percentage';
    case OfferType.flat:
      return 'flat';
    case OfferType.none:
      return null;
  }
}

Map<String, dynamic> buildOfferFlashGroupCard(String groupKey, List<Map<String, dynamic>> meals) {
  Map<String, dynamic> rep = Map<String, dynamic>.from(meals.first);
  var bestScore = -1.0;
  for (final meal in meals) {
    final hasImage = (meal['image_url']?.toString() ?? '').trim().isNotEmpty;
    final discount = double.tryParse(meal['discount_value']?.toString() ?? '') ?? 0;
    final score = discount * 10 + (hasImage ? 1 : 0);
    if (score > bestScore) {
      bestScore = score;
      rep = Map<String, dynamic>.from(meal);
    }
  }
  rep['_offer_group'] = groupKey;
  rep['_offer_group_count'] = meals.length;
  // Back-compat for older BOGO-only callers.
  if (groupKey == 'bogo') {
    rep['_bogo_group'] = true;
    rep['_bogo_count'] = meals.length;
  }
  return rep;
}

String offerFlashGroupLabel(String? groupKey) {
  switch (groupKey) {
    case 'festive':
      return 'Festive';
    case 'flashSale':
      return 'Flash Sale';
    case 'bogo':
      return 'BOGO';
    case 'percentage':
      return '% Discount';
    case 'flat':
      return 'Flat Discount';
    default:
      return 'Offers';
  }
}

String offerFlashGroupBrowseHint(String? groupKey) {
  switch (groupKey) {
    case 'festive':
      return 'All festive / hamper plates near you';
    case 'flashSale':
      return 'All Flash Sale plates near you';
    case 'bogo':
      return 'All Buy 1 Get 1 plates near you';
    case 'percentage':
      return 'All % discount plates near you';
    case 'flat':
      return 'All flat ₹ discount plates near you';
    default:
      return 'Matching offer plates near you';
  }
}

String? offerFlashGroupKey(Map<String, dynamic> meal) {
  final grouped = meal['_offer_group']?.toString().trim();
  if (grouped != null && grouped.isNotEmpty) return grouped;
  if (meal['_bogo_group'] == true) return 'bogo';
  return null;
}

String offerFlashHeadline(Map<String, dynamic> meal, {DateTime? now}) {
  final group = offerFlashGroupKey(meal);
  if (group == 'percentage') {
    final badge = PricingCalculator.offerBadgeLabel(meal).trim();
    if (RegExp(r'^\d+% OFF$').hasMatch(badge)) return badge;
    return '% Discount';
  }
  if (group == 'flat') {
    final badge = PricingCalculator.offerBadgeLabel(meal).trim();
    if (badge.startsWith('FLAT ₹')) return badge;
    return 'Flat Discount';
  }
  if (group != null) {
    switch (group) {
      case 'festive':
        return 'Festive offers';
      case 'flashSale':
        return 'Flash Sale';
      case 'bogo':
        return 'BOGO';
    }
  }
  if (isMealBoosted(meal, now: now) && PricingCalculator.mealPromoCode(meal) == null) {
    return 'Boosted today';
  }
  final code = PricingCalculator.mealPromoCode(meal);
  if (code != null && PricingCalculator.isOfferGated(meal)) {
    return 'Use $code';
  }
  final badge = PricingCalculator.offerBadgeLabel(meal).trim();
  if (code != null && badge.isNotEmpty) return '$badge · $code';
  if (code != null) return code;
  return badge.isEmpty ? "Today's offer" : badge;
}

String offerFlashSubhead(Map<String, dynamic> meal) {
  final group = offerFlashGroupKey(meal);
  if (group != null) {
    final count = int.tryParse(meal['_offer_group_count']?.toString() ?? meal['_bogo_count']?.toString() ?? '') ?? 0;
    final label = offerFlashHeadline(meal);
    if (count > 1) return '$count plates · tap to see all ${offerFlashGroupLabel(group)} deals';
    return '$label · tap to open';
  }
  final type = OfferType.fromString(meal['offer_type']?.toString());
  if (type != OfferType.none) {
    return '${offerFlashGroupLabel(offerFlashGroupKeyForMeal(meal))} · tap to see all matching plates';
  }
  if (isFestivalHamper(meal)) {
    return 'Festive · tap to see all festive plates';
  }
  final title = meal['title']?.toString().trim() ?? meal['name']?.toString().trim() ?? '';
  return title.isEmpty ? 'Tap to see this kitchen special' : title;
}
