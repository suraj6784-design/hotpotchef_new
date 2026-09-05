// lib/utils/pricing_calculator.dart

import 'dart:math' as math;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../models/pricing_models.dart';

class PricingCalculator {
  PricingCalculator._();

  /// Default fallback percentage for Flash Sales if not specified by backend.
  static const double defaultFlashSaleDiscountPercent = 20.0;

  /// Rounds currency amounts cleanly to two decimal places (e.g. Paise/Cents).
  static double roundCurrency(double value) {
    if (value.isNaN || value.isInfinite) return 0.0;
    return (value * 100).roundToDouble() / 100.0;
  }

  /// Parses numeric values safely from either num, String, or malformed types.
  static double _parseCurrency(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) {
      return value.isFinite ? value.toDouble() : 0.0;
    }
    return double.tryParse(value.toString().trim()) ?? 0.0;
  }

  static String? normalizedPromoCode(dynamic raw) {
    final code = raw?.toString().trim().toUpperCase() ?? '';
    return code.isEmpty ? null : code;
  }

  static String? mealPromoCode(Map<String, dynamic> mealDetails) {
    return normalizedPromoCode(mealDetails['promo_code'] ?? mealDetails['promoCode']);
  }

  static bool promoCodeMatches(Map<String, dynamic> mealDetails, String? appliedPromoCode) {
    final expected = mealPromoCode(mealDetails);
    final got = normalizedPromoCode(appliedPromoCode);
    return expected != null && got != null && expected == got;
  }

  static bool hasPromoExtra(Map<String, dynamic> mealDetails) {
    return _parseCurrency(mealDetails['promo_discount_value']) > 0;
  }

  /// `FESTIVE50` / `HOME20` → 50 / 20 when the chef left discount_value blank.
  static double? numericSuffixFromPromoCode(String? code) {
    final normalized = normalizedPromoCode(code);
    if (normalized == null) return null;
    final match = RegExp(r'(\d{1,3})$').firstMatch(normalized);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!);
    if (value == null || value <= 0) return null;
    return value;
  }

  static double resolvedOfferDiscount(
    Map<String, dynamic> mealDetails, {
    required OfferType offerType,
  }) {
    final explicit = _parseCurrency(mealDetails['discount_value']);
    if (explicit > 0) return explicit;

    final hinted = numericSuffixFromPromoCode(mealPromoCode(mealDetails));
    if (hinted != null) {
      if (offerType == OfferType.flat) return hinted;
      if (hinted <= 90) return hinted;
    }

    if (offerType == OfferType.flashSale) return defaultFlashSaleDiscountPercent;
    return 0;
  }

  /// Code-only meals keep the automatic offer locked until checkout.
  static bool isOfferGated(Map<String, dynamic> mealDetails) {
    return mealPromoCode(mealDetails) != null && !hasPromoExtra(mealDetails);
  }

  static bool isWithinOfferWindow(
    Map<String, dynamic> mealDetails, {
    DateTime? referenceTime,
  }) {
    final now = referenceTime?.toLocal() ?? DateTime.now();
    final startStr = mealDetails['offer_valid_from']?.toString();
    if (startStr != null && startStr.isNotEmpty) {
      final startTime = DateTime.tryParse(startStr)?.toLocal();
      if (startTime != null && now.isBefore(startTime)) return false;
    }
    final endStr = mealDetails['offer_valid_until']?.toString();
    if (endStr != null && endStr.isNotEmpty) {
      final endTime = DateTime.tryParse(endStr)?.toLocal();
      if (endTime != null && now.isAfter(endTime)) return false;
    }
    return true;
  }

  /// Checks if an offer is currently live.
  static bool isOfferActive(
    Map<String, dynamic> mealDetails, {
    DateTime? referenceTime,
    String? appliedPromoCode,
  }) {
    try {
      final offerType = OfferType.fromString(mealDetails['offer_type']?.toString());
      if (offerType == OfferType.none) return false;
      if (!isWithinOfferWindow(mealDetails, referenceTime: referenceTime)) return false;
      if (isOfferGated(mealDetails) && !promoCodeMatches(mealDetails, appliedPromoCode)) {
        return false;
      }
      return true;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Error evaluating offer active status');
      return false;
    }
  }

  /// The pre-discount base unit price of a meal.
  static double basePrice(Map<String, dynamic> mealDetails) {
    final price = _parseCurrency(mealDetails['price']);
    return price < 0 ? 0.0 : roundCurrency(price);
  }

  /// Detailed summary computing gross & net costs, total savings, and line-item unit metrics.
  static ItemPricingSummary calculateItemSummary(
    Map<String, dynamic> mealDetails,
    int quantity, {
    DateTime? referenceTime,
    String? appliedPromoCode,
  }) {
    if (quantity <= 0) {
      return const ItemPricingSummary(
        baseUnitPrice: 0.0,
        effectiveUnitPrice: 0.0,
        grossTotal: 0.0,
        netTotal: 0.0,
        totalDiscount: 0.0,
        isOfferApplied: false,
      );
    }

    final unitPrice = basePrice(mealDetails);
    final grossTotal = roundCurrency(unitPrice * quantity);

    if (!isOfferActive(
      mealDetails,
      referenceTime: referenceTime,
      appliedPromoCode: appliedPromoCode,
    )) {
      return _withStackedPromo(
        mealDetails,
        quantity: quantity,
        unitPrice: unitPrice,
        grossTotal: grossTotal,
        netTotal: grossTotal,
        description: '',
        referenceTime: referenceTime,
        appliedPromoCode: appliedPromoCode,
      );
    }

    final offerType = OfferType.fromString(mealDetails['offer_type']?.toString());
    final discountVal = resolvedOfferDiscount(mealDetails, offerType: offerType);
    final maxDiscountCap = _parseCurrency(mealDetails['max_discount_cap']);
    final hasCap = maxDiscountCap > 0.0;

    double netTotal = grossTotal;
    String description = '';

    try {
      switch (offerType) {
        case OfferType.bogo:
          // Buy 1 Get 1: Every 2nd item is free
          final payableQty = (quantity ~/ 2) + (quantity % 2);
          netTotal = roundCurrency(unitPrice * payableQty);
          final freeQty = quantity - payableQty;
          description = freeQty > 0
              ? 'BOGO: $freeQty item${freeQty > 1 ? 's' : ''} free'
              : 'BOGO: Buy 1 Get 1';
          break;

        case OfferType.percentage:
          final sanitizedPercent = discountVal.clamp(0.0, 100.0);
          double totalDiscount = roundCurrency((unitPrice * (sanitizedPercent / 100.0)) * quantity);
          if (hasCap) {
            totalDiscount = math.min(totalDiscount, maxDiscountCap);
          }
          netTotal = roundCurrency(math.max(0.0, grossTotal - totalDiscount));
          description = '${sanitizedPercent.toStringAsFixed(0)}% OFF';
          break;

        case OfferType.flat:
          final unitDiscount = math.min(unitPrice, math.max(0.0, discountVal));
          double totalDiscount = roundCurrency(unitDiscount * quantity);
          if (hasCap) {
            totalDiscount = math.min(totalDiscount, maxDiscountCap);
          }
          netTotal = roundCurrency(math.max(0.0, grossTotal - totalDiscount));
          description = 'Flat ₹${discountVal.toStringAsFixed(0)} OFF';
          break;

        case OfferType.flashSale:
          final sanitizedPercent = discountVal.clamp(0.0, 100.0);
          double totalDiscount = roundCurrency((unitPrice * (sanitizedPercent / 100.0)) * quantity);
          if (hasCap) {
            totalDiscount = math.min(totalDiscount, maxDiscountCap);
          }
          netTotal = roundCurrency(math.max(0.0, grossTotal - totalDiscount));
          description = 'Flash Sale ${sanitizedPercent.toStringAsFixed(0)}% OFF';
          break;

        case OfferType.none:
        default:
          netTotal = grossTotal;
          break;
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Error calculating pricing summary for offer: $offerType');
      netTotal = grossTotal;
    }

    return _withStackedPromo(
      mealDetails,
      quantity: quantity,
      unitPrice: unitPrice,
      grossTotal: grossTotal,
      netTotal: netTotal,
      description: description,
      referenceTime: referenceTime,
      appliedPromoCode: appliedPromoCode,
    );
  }

  static ItemPricingSummary _withStackedPromo(
    Map<String, dynamic> mealDetails, {
    required int quantity,
    required double unitPrice,
    required double grossTotal,
    required double netTotal,
    required String description,
    DateTime? referenceTime,
    String? appliedPromoCode,
  }) {
    var stackedNet = netTotal;
    var stackedDescription = description;

    if (promoCodeMatches(mealDetails, appliedPromoCode) &&
        hasPromoExtra(mealDetails) &&
        isWithinOfferWindow(mealDetails, referenceTime: referenceTime)) {
      final extraType = OfferType.fromString(mealDetails['promo_discount_type']?.toString());
      final extraVal = _parseCurrency(mealDetails['promo_discount_value']);
      final extraCap = _parseCurrency(mealDetails['promo_max_discount_cap']);
      double extraOff = 0.0;
      String extraLabel = '';

      if (extraType == OfferType.flat) {
        extraOff = math.min(stackedNet, math.max(0.0, extraVal));
        extraLabel = 'Promo ₹${extraVal.toStringAsFixed(0)}';
      } else {
        final pct = extraVal.clamp(0.0, 100.0);
        extraOff = roundCurrency(stackedNet * (pct / 100.0));
        extraLabel = 'Promo ${pct.toStringAsFixed(0)}%';
      }
      if (extraCap > 0) extraOff = math.min(extraOff, extraCap);
      extraOff = roundCurrency(math.max(0.0, extraOff));
      stackedNet = roundCurrency(math.max(0.0, stackedNet - extraOff));
      if (extraOff > 0) {
        stackedDescription = stackedDescription.isEmpty
            ? extraLabel
            : '$stackedDescription + $extraLabel';
      }
    }

    final totalDiscount = roundCurrency(math.max(0.0, grossTotal - stackedNet));
    return ItemPricingSummary(
      baseUnitPrice: unitPrice,
      effectiveUnitPrice: roundCurrency(stackedNet / quantity),
      grossTotal: grossTotal,
      netTotal: stackedNet,
      totalDiscount: totalDiscount,
      isOfferApplied: totalDiscount > 0.0,
      offerDescription: stackedDescription,
    );
  }

  /// Preserved API: Computes final net charge for `quantity` units of a meal.
  static double effectiveItemTotal(
    Map<String, dynamic> mealDetails,
    int quantity, {
    DateTime? referenceTime,
    String? appliedPromoCode,
  }) {
    return calculateItemSummary(
      mealDetails,
      quantity,
      referenceTime: referenceTime,
      appliedPromoCode: appliedPromoCode,
    ).netTotal;
  }

  /// Preserved API: Effective price for a single unit.
  static double effectiveUnitPrice(
    Map<String, dynamic> mealDetails,
    int quantity, {
    DateTime? referenceTime,
    String? appliedPromoCode,
  }) {
    if (quantity <= 0) return 0.0;
    return calculateItemSummary(
      mealDetails,
      quantity,
      referenceTime: referenceTime,
      appliedPromoCode: appliedPromoCode,
    ).effectiveUnitPrice;
  }

  /// Calculates total savings amount for a given meal and quantity.
  static double itemSavingsTotal(
    Map<String, dynamic> mealDetails,
    int quantity, {
    DateTime? referenceTime,
    String? appliedPromoCode,
  }) {
    return calculateItemSummary(
      mealDetails,
      quantity,
      referenceTime: referenceTime,
      appliedPromoCode: appliedPromoCode,
    ).totalDiscount;
  }

  /// List price + offer fields for a cart/order line. Never uses a snapshotted
  /// paid unit as `price`, so offers are not applied twice.
  static Map<String, dynamic> pricingSourceFromLine(Map<String, dynamic> item) {
    final nested = item['rawMealDetails'] ??
        item['mealDetails'] ??
        item['meal_details'] ??
        item['raw_meal_details'];
    final nestedMap = nested is Map ? Map<String, dynamic>.from(nested) : <String, dynamic>{};

    final listPrice = _parseCurrency(
      item['base_price'] ??
          item['basePrice'] ??
          nestedMap['price'] ??
          nestedMap['base_price'] ??
          item['unit_price'] ??
          item['price'],
    );

    return {
      ...nestedMap,
      ...item,
      'price': listPrice,
      'offer_type': item['offer_type'] ?? nestedMap['offer_type'],
      'discount_value': item['discount_value'] ?? nestedMap['discount_value'],
      'max_discount_cap': item['max_discount_cap'] ?? nestedMap['max_discount_cap'],
      'offer_valid_until': item['offer_valid_until'] ?? nestedMap['offer_valid_until'],
      'offer_valid_from': item['offer_valid_from'] ?? nestedMap['offer_valid_from'],
      'promo_code': item['promo_code'] ?? nestedMap['promo_code'],
      'promo_discount_type': item['promo_discount_type'] ?? nestedMap['promo_discount_type'],
      'promo_discount_value': item['promo_discount_value'] ?? nestedMap['promo_discount_value'],
      'promo_max_discount_cap': item['promo_max_discount_cap'] ?? nestedMap['promo_max_discount_cap'],
    };
  }

  /// Paid unit + offer metadata for `place_customer_order` (`price * qty`).
  static Map<String, dynamic> snapshotCheckoutPrices(
    Map<String, dynamic> mealDetails,
    int quantity, {
    DateTime? referenceTime,
    String? appliedPromoCode,
    double addOnsUnit = 0,
  }) {
    final summary = calculateItemSummary(
      mealDetails,
      quantity,
      referenceTime: referenceTime,
      appliedPromoCode: appliedPromoCode,
    );
    final promoMatched = promoCodeMatches(mealDetails, appliedPromoCode);
    final extras = roundCurrency(addOnsUnit < 0 ? 0 : addOnsUnit);
    final paidUnit = roundCurrency(summary.effectiveUnitPrice + extras);
    final extrasTotal = roundCurrency(extras * quantity);
    return {
      'base_price': summary.baseUnitPrice,
      'meal_unit': summary.effectiveUnitPrice,
      'addons_unit': extras,
      'price': paidUnit,
      'discounted_price': (summary.isOfferApplied || extras > 0) ? paidUnit : null,
      'offer_type': mealDetails['offer_type'],
      'discount_value': resolvedOfferDiscount(
        mealDetails,
        offerType: OfferType.fromString(mealDetails['offer_type']?.toString()),
      ),
      'max_discount_cap': mealDetails['max_discount_cap'],
      'offer_valid_until': mealDetails['offer_valid_until'],
      'offer_valid_from': mealDetails['offer_valid_from'],
      'promo_code': mealPromoCode(mealDetails),
      'promo_discount_type': mealDetails['promo_discount_type'],
      'promo_discount_value': mealDetails['promo_discount_value'],
      'applied_promo_code': promoMatched ? normalizedPromoCode(appliedPromoCode) : null,
      'promo_applied': promoMatched && summary.isOfferApplied,
      'line_gross': roundCurrency(summary.grossTotal + extrasTotal),
      'line_net': roundCurrency(summary.netTotal + extrasTotal),
      'offer_applied': summary.isOfferApplied || extras > 0,
      'offer_description': summary.offerDescription,
    };
  }

  static String offerBadgeLabel(Map<String, dynamic> mealDetails, {int quantity = 1}) {
    if (isOfferGated(mealDetails)) return 'PROMO';
    final offerType = OfferType.fromString(mealDetails['offer_type']?.toString());
    final discountVal = resolvedOfferDiscount(mealDetails, offerType: offerType);
    switch (offerType) {
      case OfferType.bogo:
        return 'BOGO';
      case OfferType.percentage:
        final pct = discountVal.clamp(0.0, 100.0);
        return pct > 0 ? '${pct.toStringAsFixed(0)}% OFF' : '% OFF';
      case OfferType.flat:
        return discountVal > 0 ? 'FLAT ₹${discountVal.toStringAsFixed(0)}' : 'FLAT OFF';
      case OfferType.flashSale:
        final pct = resolvedOfferDiscount(mealDetails, offerType: OfferType.flashSale)
            .clamp(0.0, 100.0);
        return 'FLASH ${pct.toStringAsFixed(0)}%';
      case OfferType.none:
        return calculateItemSummary(mealDetails, quantity).offerDescription ?? '';
    }
  }

  static double addOnsTotal(dynamic rawAddOns) {
    if (rawAddOns is! List) return 0.0;
    return roundCurrency(
      rawAddOns.fold<double>(0, (sum, addon) {
        if (addon is! Map) return sum;
        return sum + _parseCurrency(addon['price']);
      }),
    );
  }

  /// Food total for one checkout/order line (offers + add-ons).
  static double lineFoodTotal(
    Map<String, dynamic> item, {
    DateTime? referenceTime,
    String? appliedPromoCode,
  }) {
    final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
    final meal = pricingSourceFromLine(item);
    final addOnUnit = addOnsTotal(item['selectedAddOns'] ?? item['selected_add_ons']);
    return roundCurrency(
      effectiveItemTotal(
            meal,
            qty,
            referenceTime: referenceTime,
            appliedPromoCode: appliedPromoCode,
          ) +
          (addOnUnit * qty),
    );
  }

  static bool cartHasPromoCode(Iterable<Map<String, dynamic>> items) {
    return items.any((item) => mealPromoCode(pricingSourceFromLine(item)) != null);
  }

  static bool cartMatchesPromoCode(
    Iterable<Map<String, dynamic>> items,
    String? appliedPromoCode,
  ) {
    final code = normalizedPromoCode(appliedPromoCode);
    if (code == null) return false;
    return items.any((item) => promoCodeMatches(pricingSourceFromLine(item), code));
  }
}