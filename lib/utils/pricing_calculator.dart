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

  /// Checks if an offer is currently live.
  static bool isOfferActive(
    Map<String, dynamic> mealDetails, {
    DateTime? referenceTime,
  }) {
    try {
      final offerType = OfferType.fromString(mealDetails['offer_type']?.toString());
      if (offerType == OfferType.none) return false;

      final now = referenceTime?.toLocal() ?? DateTime.now();

      // Check optional offer start window
      final startStr = mealDetails['offer_valid_from']?.toString();
      if (startStr != null && startStr.isNotEmpty) {
        final startTime = DateTime.tryParse(startStr)?.toLocal();
        if (startTime != null && now.isBefore(startTime)) return false;
      }

      // Check offer expiry window
      final endStr = mealDetails['offer_valid_until']?.toString();
      if (endStr != null && endStr.isNotEmpty) {
        final endTime = DateTime.tryParse(endStr)?.toLocal();
        if (endTime != null && now.isAfter(endTime)) return false;
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

    if (!isOfferActive(mealDetails, referenceTime: referenceTime)) {
      return ItemPricingSummary(
        baseUnitPrice: unitPrice,
        effectiveUnitPrice: unitPrice,
        grossTotal: grossTotal,
        netTotal: grossTotal,
        totalDiscount: 0.0,
        isOfferApplied: false,
      );
    }

    final offerType = OfferType.fromString(mealDetails['offer_type']?.toString());
    final discountVal = _parseCurrency(mealDetails['discount_value']);
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
          description = 'BOGO: $freeQty item${freeQty > 1 ? 's' : ''} free';
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
          final effectiveDiscount = discountVal > 0 ? discountVal : defaultFlashSaleDiscountPercent;
          final sanitizedPercent = effectiveDiscount.clamp(0.0, 100.0);
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

    final totalDiscount = roundCurrency(math.max(0.0, grossTotal - netTotal));

    return ItemPricingSummary(
      baseUnitPrice: unitPrice,
      effectiveUnitPrice: roundCurrency(netTotal / quantity),
      grossTotal: grossTotal,
      netTotal: netTotal,
      totalDiscount: totalDiscount,
      isOfferApplied: totalDiscount > 0.0,
      offerDescription: description,
    );
  }

  /// Preserved API: Computes final net charge for `quantity` units of a meal.
  static double effectiveItemTotal(
    Map<String, dynamic> mealDetails,
    int quantity, {
    DateTime? referenceTime,
  }) {
    return calculateItemSummary(
      mealDetails,
      quantity,
      referenceTime: referenceTime,
    ).netTotal;
  }

  /// Preserved API: Effective price for a single unit.
  static double effectiveUnitPrice(
    Map<String, dynamic> mealDetails,
    int quantity, {
    DateTime? referenceTime,
  }) {
    if (quantity <= 0) return 0.0;
    return calculateItemSummary(
      mealDetails,
      quantity,
      referenceTime: referenceTime,
    ).effectiveUnitPrice;
  }

  /// Calculates total savings amount for a given meal and quantity.
  static double itemSavingsTotal(
    Map<String, dynamic> mealDetails,
    int quantity, {
    DateTime? referenceTime,
  }) {
    return calculateItemSummary(
      mealDetails,
      quantity,
      referenceTime: referenceTime,
    ).totalDiscount;
  }
}