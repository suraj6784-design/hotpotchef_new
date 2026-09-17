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

  /// Replays a stored checkout/order line. Live offer math is [PricingCalculator].
  factory ItemPricingSummary.fromItemMap(Map<String, dynamic> item) {
    final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
    final storedNet = double.tryParse(item['line_net']?.toString() ?? '');
    final storedGross = double.tryParse(item['line_gross']?.toString() ?? '');
    final basePrice = double.tryParse(
          item['base_price']?.toString() ??
          item['basePrice']?.toString() ??
          item['price']?.toString() ??
          '0',
        ) ??
        0.0;
    final discountedPrice = double.tryParse(
          item['discounted_price']?.toString() ??
          item['discountedPrice']?.toString() ??
          '0',
        ) ??
        0.0;

    final effectivePrice = (discountedPrice > 0 && (basePrice <= 0 || discountedPrice <= basePrice + 0.001))
        ? discountedPrice
        : basePrice;
    final gross = storedGross ?? (basePrice * qty);
    final net = storedNet ?? (effectivePrice * qty);

    return ItemPricingSummary(
      baseUnitPrice: basePrice,
      effectiveUnitPrice: qty > 0 ? net / qty : effectivePrice,
      grossTotal: gross,
      netTotal: net,
      totalDiscount: max(0.0, gross - net),
      isOfferApplied: net + 0.001 < gross,
      offerDescription: item['offer_description']?.toString(),
    );
  }
}