// lib/models/pricing_models.dart

import 'dart:math';

enum OfferType {
  none,
  bogo,
  percentage,
  flat,
  flashSale;

  static OfferType fromString(String? raw) {
    if (raw == null || raw.isEmpty) return OfferType.none;
    final normalized = raw.toLowerCase().trim();

    if (normalized.contains('bogo') || normalized.contains('buy 1 get 1')) {
      return OfferType.bogo;
    }
    if (normalized.contains('percent') || normalized.contains('%')) {
      return OfferType.percentage;
    }
    if (normalized.contains('flat') || normalized.contains('₹') || normalized.contains('flat_discount')) {
      return OfferType.flat;
    }
    if (normalized.contains('flash')) {
      return OfferType.flashSale;
    }
    return OfferType.none;
  }
}

/// Detailed financial breakdown of an item calculation for UI & receipts.
class ItemPricingSummary {
  final double baseUnitPrice;
  final double effectiveUnitPrice;
  final double grossTotal;
  final double netTotal;
  final double totalDiscount;
  final bool isOfferApplied;
  final String? offerDescription;

  const ItemPricingSummary({
    required this.baseUnitPrice,
    required this.effectiveUnitPrice,
    required this.grossTotal,
    required this.netTotal,
    required this.totalDiscount,
    required this.isOfferApplied,
    this.offerDescription,
  });

  factory ItemPricingSummary.fromItemMap(Map<String, dynamic> item) {
    final basePrice = double.tryParse(
          item['base_price']?.toString() ??
          item['basePrice']?.toString() ??
          item['price']?.toString() ?? '0',
        ) ?? 0.0;

    final discountedPrice = double.tryParse(
          item['discounted_price']?.toString() ??
          item['discountedPrice']?.toString() ?? '0',
        ) ?? 0.0;

    final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;

    final rawDetails = item['rawMealDetails'] as Map<String, dynamic>? ?? {};
    final offerType = OfferType.fromString(
      item['offer_type']?.toString() ?? rawDetails['offer_type']?.toString(),
    );

    double effectivePrice = basePrice;
    bool offerActive = false;
    String? description;

    if (discountedPrice > 0 && discountedPrice < basePrice) {
      effectivePrice = discountedPrice;
      offerActive = true;
      description = 'Special Discount Applied';
    } else if (offerType == OfferType.bogo && qty >= 2) {
      final paidItems = (qty ~/ 2) + (qty % 2);
      effectivePrice = basePrice * (paidItems / qty);
      offerActive = true;
      description = 'BOGO Offer Applied';
    }

    final gross = basePrice * qty;
    final net = effectivePrice * qty;

    return ItemPricingSummary(
      baseUnitPrice: basePrice,
      effectiveUnitPrice: effectivePrice,
      grossTotal: gross,
      netTotal: net,
      totalDiscount: max(0.0, gross - net),
      isOfferApplied: offerActive,
      offerDescription: description,
    );
  }
}