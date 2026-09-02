// lib/models/cart_state.dart

import 'package:flutter/foundation.dart';
import '../utils/pricing_calculator.dart';
import 'cart_enums.dart';

@immutable
class CartItemModel {
  final String id;
  final String mealId;
  final String chefId;
  final String title;
  final double basePrice;
  final double? discountedPrice;
  final int quantity;
  final DateTime scheduledDate;
  final ServiceType serviceType;
  final String? timeSlot; // Added timeSlot field
  final List<CartItemAddOn> selectedAddOns;
  final String? specialInstructions;
  
  /// Retained as unmodifiable map for backward compatibility with PricingCalculator legacy logic
  final Map<String, dynamic> rawMealDetails;

  const CartItemModel({
    required this.id,
    required this.mealId,
    required this.chefId,
    required this.title,
    required this.basePrice,
    this.discountedPrice,
    required this.quantity,
    required this.scheduledDate,
    required this.serviceType,
    this.timeSlot,
    this.selectedAddOns = const [],
    this.specialInstructions,
    this.rawMealDetails = const {},
  }) : assert(quantity > 0, 'Quantity must be at least 1');

  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    final rawDetailsSource = json['mealDetails'] ?? json['meal_details'] ?? json['rawMealDetails'];
    final rawDetails = rawDetailsSource is Map
        ? Map<String, dynamic>.from(rawDetailsSource)
        : <String, dynamic>{};

    final addOnsRaw = json['selectedAddOns'] ?? json['selected_add_ons'] ?? [];
    final parsedAddOns = (addOnsRaw is List ? addOnsRaw : const [])
        .whereType<Map>()
        .map((e) => CartItemAddOn.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);

    return CartItemModel(
      id: json['id']?.toString() ?? '',
      mealId: json['mealId']?.toString() ?? json['meal_id']?.toString() ?? '',
      chefId: json['chefId']?.toString() ?? json['chef_id']?.toString() ?? '',
      title: json['title']?.toString() ??
          rawDetails['title']?.toString() ??
          rawDetails['name']?.toString() ??
          '',
      basePrice: (json['basePrice'] as num?)?.toDouble() ??
          (rawDetails['price'] as num?)?.toDouble() ??
          0.0,
      discountedPrice: (json['discountedPrice'] as num?)?.toDouble() ??
          (rawDetails['discounted_price'] as num?)?.toDouble(),
      quantity: int.tryParse(json['quantity']?.toString() ?? '1') ?? 1,
      scheduledDate: DateTime.tryParse(json['selectedDate']?.toString() ?? json['scheduled_date']?.toString() ?? '') ??
          DateTime.now(),
      serviceType: ServiceType.fromString(
        json['selectedServiceType']?.toString() ??
            json['selected_service_type']?.toString() ??
            json['service_type']?.toString(),
      ),
      timeSlot: json['timeSlot']?.toString() ?? json['time_slot']?.toString() ?? rawDetails['exact_time']?.toString(),
      selectedAddOns: parsedAddOns,
      specialInstructions: json['specialInstructions']?.toString(),
      rawMealDetails: Map.unmodifiable(rawDetails),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mealId': mealId,
        'chefId': chefId,
        'title': title,
        'basePrice': basePrice,
        'discountedPrice': discountedPrice,
        'quantity': quantity,
        'selectedDate': scheduledDate.toIso8601String(),
        'selectedServiceType': serviceType.toDisplayString(),
        'timeSlot': timeSlot,
        'selectedAddOns': selectedAddOns.map((a) => a.toJson()).toList(growable: false),
        'specialInstructions': specialInstructions,
        'mealDetails': rawMealDetails,
      };

  /// Snake_case + camelCase aliases expected by checkout and `place_customer_order`.
  Map<String, dynamic> toCheckoutPayload() {
    final meal = Map<String, dynamic>.from(rawMealDetails);
    // Guard against a ₹0 checkout total: when `basePrice` wasn't captured
    // (e.g. the meal price arrived as a String), fall back to the price
    // carried in the meal details so downstream pricing never collapses to 0.
    final double resolvedBase = basePrice > 0 ? basePrice : PricingCalculator.basePrice(meal);
    final double resolvedPrice =
        (discountedPrice != null && discountedPrice! > 0) ? discountedPrice! : resolvedBase;
    return {
      ...toJson(),
      'chef_id': chefId,
      'meal_id': mealId,
      'source_meal_id': mealId,
      'name': title,
      'price': resolvedPrice,
      'base_price': resolvedBase,
      'discounted_price': discountedPrice,
      'selected_service_type': serviceType.toDisplayString(),
      'service_type': serviceType.toDisplayString(),
      'serviceType': serviceType.toDisplayString(),
      'scheduled_date': scheduledDate.toIso8601String(),
      'scheduledDate': scheduledDate.toIso8601String(),
      'selected_date': scheduledDate.toIso8601String(),
      'time_slot': timeSlot,
      'rawMealDetails': meal,
      'meal_details': meal,
    };
  }

  CartItemModel copyWith({
    String? id,
    String? mealId,
    String? chefId,
    String? title,
    double? basePrice,
    double? discountedPrice,
    int? quantity,
    DateTime? scheduledDate,
    ServiceType? serviceType,
    String? timeSlot,
    List<CartItemAddOn>? selectedAddOns,
    String? specialInstructions,
    Map<String, dynamic>? rawMealDetails,
  }) {
    return CartItemModel(
      id: id ?? this.id,
      mealId: mealId ?? this.mealId,
      chefId: chefId ?? this.chefId,
      title: title ?? this.title,
      basePrice: basePrice ?? this.basePrice,
      discountedPrice: discountedPrice ?? this.discountedPrice,
      quantity: quantity ?? this.quantity,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      serviceType: serviceType ?? this.serviceType,
      timeSlot: timeSlot ?? this.timeSlot,
      selectedAddOns: selectedAddOns ?? this.selectedAddOns,
      specialInstructions: specialInstructions ?? this.specialInstructions,
      rawMealDetails: rawMealDetails ?? this.rawMealDetails,
    );
  }

  /// Calculates individual unit add-on sum
  double get unitAddOnsTotal =>
      selectedAddOns.fold(0.0, (sum, addon) => sum + addon.price);

  /// Computes unit price (discounted price takes priority if active)
  double get effectiveUnitPrice => (discountedPrice ?? basePrice) + unitAddOnsTotal;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CartItemModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          mealId == other.mealId &&
          chefId == other.chefId &&
          quantity == other.quantity &&
          scheduledDate == other.scheduledDate &&
          serviceType == other.serviceType &&
          timeSlot == other.timeSlot &&
          specialInstructions == other.specialInstructions &&
          listEquals(selectedAddOns, other.selectedAddOns);

  @override
  int get hashCode =>
      id.hashCode ^
      mealId.hashCode ^
      chefId.hashCode ^
      quantity.hashCode ^
      scheduledDate.hashCode ^
      serviceType.hashCode ^
      timeSlot.hashCode ^
      specialInstructions.hashCode ^
      Object.hashAll(selectedAddOns);
}

@immutable
class CartState {
  final List<CartItemModel> items;
  final double dynamicDeliveryFee;
  final double packagingFee;
  final double tipAmount;
  final double userCoinBalance;
  final bool applyCoins;

  const CartState({
    this.items = const [],
    this.dynamicDeliveryFee = 0.0,
    this.packagingFee = 0.0,
    this.tipAmount = 0.0,
    this.userCoinBalance = 0.0,
    this.applyCoins = false,
  });

  CartState copyWith({
    List<CartItemModel>? items,
    double? dynamicDeliveryFee,
    double? packagingFee,
    double? tipAmount,
    double? userCoinBalance,
    bool? applyCoins,
  }) {
    return CartState(
      items: items ?? this.items,
      dynamicDeliveryFee: dynamicDeliveryFee ?? this.dynamicDeliveryFee,
      packagingFee: packagingFee ?? this.packagingFee,
      tipAmount: tipAmount ?? this.tipAmount,
      userCoinBalance: userCoinBalance ?? this.userCoinBalance,
      applyCoins: applyCoins ?? this.applyCoins,
    );
  }

  // --- Multi-Vendor Protection Helpers ---

  /// Returns unique Chef IDs currently present in the cart.
  Set<String> get vendorIds => items.map((i) => i.chefId).toSet();

  /// Identifies if the cart violates single-vendor order requirements.
  bool get hasVendorConflict => vendorIds.length > 1;

  /// Primary active vendor ID (if cart is uniform).
  String? get primaryChefId => items.isEmpty ? null : items.first.chefId;

  // --- Financial Computations ---

  /// Gross food subtotal prior to promotional discounts
  double get originalFoodTotal => items.fold(0.0, (sum, item) {
        final price = PricingCalculator.basePrice(item.rawMealDetails);
        final base = price > 0 ? price : item.basePrice;
        return sum + ((base + item.unitAddOnsTotal) * item.quantity);
      });

  /// Net food total after applying item-level discounts and add-on rates
  double get foodTotal => items.fold(0.0, (sum, item) => sum + getEffectiveItemTotal(item));

  /// Calculates total price for an individual line item
  double getEffectiveItemTotal(CartItemModel item) {
    if (item.rawMealDetails.isNotEmpty) {
      return PricingCalculator.effectiveItemTotal(item.rawMealDetails, item.quantity) +
          (item.unitAddOnsTotal * item.quantity);
    }
    return item.effectiveUnitPrice * item.quantity;
  }

  /// Evaluates reward coin deduction dynamically against order subtotal
  double get coinsDiscountAmount {
    if (!applyCoins || userCoinBalance <= 0) return 0.0;
    // Business rule guardrail: Coins cannot discount more than the food total
    return userCoinBalance > foodTotal ? foodTotal : userCoinBalance;
  }

  /// Final payable amount including items, fees, driver tips, and coin deductions
  double get grandTotal {
    final subtotal = (foodTotal + (hasDelivery ? dynamicDeliveryFee : 0.0) + packagingFee + tipAmount) -
        coinsDiscountAmount;
    return subtotal < 0.0 ? 0.0 : subtotal;
  }

  // --- Status & Query Flags ---

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);
  bool get hasDelivery => items.any((item) => item.serviceType.isDelivery);

  bool isOfferActive(Map<String, dynamic> mealDetails) =>
      PricingCalculator.isOfferActive(mealDetails);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CartState &&
          runtimeType == other.runtimeType &&
          dynamicDeliveryFee == other.dynamicDeliveryFee &&
          packagingFee == other.packagingFee &&
          tipAmount == other.tipAmount &&
          userCoinBalance == other.userCoinBalance &&
          applyCoins == other.applyCoins &&
          listEquals(items, other.items);

  @override
  int get hashCode =>
      dynamicDeliveryFee.hashCode ^
      packagingFee.hashCode ^
      tipAmount.hashCode ^
      userCoinBalance.hashCode ^
      applyCoins.hashCode ^
      Object.hashAll(items);
}