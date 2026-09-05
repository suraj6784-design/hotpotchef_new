// lib/widgets/customer_ui_components.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/helpers.dart';
import '../utils/app_page.dart';
import '../utils/app_theme.dart';
import '../utils/pricing_calculator.dart';
import '../models/cart_enums.dart';
import '../providers/cart_provider.dart';
import '../services/reorder_service.dart';
import '../screens/auth_screen.dart';

// 1. High-Performance Watermarked Image Widget
class WatermarkedMealImage extends StatelessWidget {
  final String? imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const WatermarkedMealImage({
    super.key,
    required this.imageUrl,
    this.width = double.infinity,
    this.height = 120,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Container(
        width: width,
        height: height,
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            imageUrl != null && imageUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl!,
                    fit: fit,
                    placeholder: (context, url) => Container(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => const Icon(Icons.restaurant, color: Colors.grey),
                  )
                : const Icon(Icons.restaurant, color: Colors.grey),
            Positioned(
              bottom: 6,
              right: 6,
              child: Opacity(
                opacity: 0.6,
                child: Image.asset('assets/app_icon.png', width: 20, height: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 2. Status Badge Helper
Widget buildStatusBadge(String status) {
  Color color = Colors.orange;
  final s = status.toLowerCase();
  if (s.contains('deliver') || s.contains('complet') || s.contains('confirm')) {
    color = Colors.green;
  } else if (s.contains('cancel') || s.contains('reject')) {
    color = Colors.redAccent;
  } else if (s.contains('out') || s.contains('ready')) {
    color = Colors.teal;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      status.toUpperCase(),
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
    ),
  );
}

// 3. Unread Chat Indicator Widget
class UnreadChatIndicator extends StatelessWidget {
  final String mealId;
  final bool hasUnread;

  const UnreadChatIndicator({super.key, required this.mealId, this.hasUnread = false});

  @override
  Widget build(BuildContext context) {
    if (!hasUnread) return const SizedBox.shrink();
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
    );
  }
}

// 4. Delivery Countdown Sticker Widget
class DeliveryCountdownSticker extends StatelessWidget {
  final String? timeSlot;
  final String? status;
  final String? createdAt;
  final String? orderId;

  const DeliveryCountdownSticker({
    super.key,
    this.timeSlot,
    this.status,
    this.createdAt,
    this.orderId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, size: 12, color: Colors.blueAccent),
          const SizedBox(width: 4),
          Text(
            timeSlot ?? 'ASAP',
            style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// 5. Chef Profile Dialog
void showChefProfileDialog(BuildContext context, String chefId, String chefName, String fssai) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
      title: Row(
        children: [
          const CircleAvatar(backgroundColor: AppTheme.primary, child: Icon(Icons.person, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              chefName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verified Home Chef Partner',
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.verified, size: 16, color: Colors.blueAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'FSSAI: ${fssai.isNotEmpty ? fssai : 'Licence not listed'}',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade300 : AppTheme.textMainLight,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}

// 6. Fully Upgraded Decision-Making Meal Details Modal
Future<bool> confirmReplaceKitchenCart(BuildContext context) async {
  final replace = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surfaceOf(ctx),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Different kitchen',
        style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(ctx)),
      ),
      content: Text(
        'Your cart has dishes from another kitchen. Clear the cart and add this dish instead?',
        style: TextStyle(color: AppTheme.onSurfaceOf(ctx).withValues(alpha: 0.75)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep cart', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Clear & add'),
        ),
      ],
    ),
  );
  return replace == true;
}

/// Adds a dish, asking before mixing kitchens. Never reports success if the add failed.
Future<bool> addMealToCartWithConflict({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> meal,
  int quantity = 1,
  List<CartItemAddOn> addOns = const [],
}) async {
  if (!isMealAvailableForCart(meal)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This dish is no longer available.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    }
    return false;
  }

  try {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final prefs = await Supabase.instance.client
          .from('users')
          .select('dietary_preference, allergies')
          .eq('id', user.id)
          .maybeSingle();
      final reason = dietSkipReason(
        meal,
        preference: prefs?['dietary_preference']?.toString(),
        allergies: prefs?['allergies']?.toString(),
      );
      if (reason != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(reason), backgroundColor: Colors.orangeAccent),
          );
        }
        return false;
      }
    }
  } catch (_) {}

  final cart = ref.read(cartProvider.notifier);
  final existingChef = ref.read(cartProvider).primaryChefId;
  final chefId = meal['chef_id']?.toString() ?? '';
  final added = cart.addToCart(meal, quantity, addOns: addOns, clearIfVendorConflict: false);
  if (added) return true;

  final isConflict = existingChef != null && existingChef.isNotEmpty && chefId.isNotEmpty && existingChef != chefId;
  if (!isConflict || !context.mounted) return false;

  final replace = await confirmReplaceKitchenCart(context);
  if (!replace || !context.mounted) return false;
  return cart.addToCart(meal, quantity, addOns: addOns, clearIfVendorConflict: true);
}

void showMealDetailsDialog(BuildContext context, Map<String, dynamic> meal, WidgetRef ref) {
  Navigator.push(
    context,
    appMaterialRoute(
      Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: MealDetailsBody(meal: meal, ref: ref),
      ),
    ),
  );
}

class MealDetailsBody extends StatefulWidget {
  final Map<String, dynamic> meal;
  final WidgetRef ref;

  const MealDetailsBody({super.key, required this.meal, required this.ref});

  @override
  State<MealDetailsBody> createState() => _MealDetailsBodyState();
}

class _MealDetailsBodyState extends State<MealDetailsBody> {
  int _quantity = 1;
  final Set<String> _selectedAddOnIds = {};

  List<CartItemAddOn> get _availableAddOns => ReorderService.parseMealAddOns(
        widget.meal['add_ons'] ?? widget.meal['addons'] ?? widget.meal['selectedAddOns'],
      );

  List<CartItemAddOn> get _chosenAddOns =>
      _availableAddOns.where((addon) => _selectedAddOnIds.contains(addon.id)).toList();

  double get _addOnsUnitTotal =>
      _chosenAddOns.fold<double>(0, (sum, addon) => sum + addon.price);

  double get _lineFoodTotal =>
      PricingCalculator.effectiveItemTotal(widget.meal, _quantity) +
      (_addOnsUnitTotal * _quantity);

  @override
  Widget build(BuildContext context) {
    final meal = widget.meal;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxStock = int.tryParse(meal['quantity']?.toString() ?? '10') ?? 10;
    final offerSummary = PricingCalculator.calculateItemSummary(meal, _quantity);
    final price = offerSummary.effectiveUnitPrice;
    final chefName = chefDisplayName(meal);
    final chefId = meal['chef_id']?.toString() ?? '';
    final fssai = meal['fssai_number']?.toString() ?? '';
    final serviceType = meal['service_type']?.toString() ?? 'Delivery, Pickup';
    final timeSlot = meal['time_slot']?.toString() ?? 'Available Today';

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    Hero(
                      tag: 'meal-image-${meal['id']}',
                      child: WatermarkedMealImage(
                        imageUrl: meal['image_url'],
                        height: 300,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 16,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              meal['title']?.toString() ?? 'Home Meal',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              border: Border.all(color: meal['is_veg'] == true ? Colors.green : Colors.redAccent),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(Icons.circle,
                                color: meal['is_veg'] == true ? Colors.green : Colors.redAccent, size: 10),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (offerSummary.isOfferApplied) ...[
                                Text(
                                  '₹${offerSummary.baseUnitPrice.toInt()}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textMuted,
                                    decoration: TextDecoration.lineThrough,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              Text('₹${price.toInt()}',
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.primary)),
                              if (offerSummary.isOfferApplied &&
                                  (offerSummary.offerDescription ?? '').isNotEmpty)
                                Text(
                                  offerSummary.offerDescription!,
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              if (PricingCalculator.mealPromoCode(meal) != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    PricingCalculator.hasPromoExtra(meal)
                                        ? 'Promo ${PricingCalculator.mealPromoCode(meal)} stacks extra off at checkout'
                                        : 'Enter promo ${PricingCalculator.mealPromoCode(meal)} at checkout to unlock this offer',
                                    style: const TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          MealRatingBadge(meal: meal),
                        ],
                      ),
                      const SizedBox(height: 24),
                      InkWell(
                        onTap: () => showChefProfileDialog(context, chefId, chefName, fssai),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                            boxShadow: isDark ? [] : AppTheme.softShadow,
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                  backgroundColor: AppTheme.primary,
                                  radius: 22,
                                  child: Icon(Icons.storefront, color: Colors.white, size: 22)),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Prepared by $chefName',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
                                        )),
                                    const SizedBox(height: 4),
                                    Text(
                                      fssai.isNotEmpty
                                          ? 'FSSAI $fssai • Tap for info'
                                          : 'FSSAI not listed • Tap for chef details',
                                      style: TextStyle(
                                        color: fssai.isNotEmpty ? Colors.green : AppTheme.textMuted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.blue.shade900.withValues(alpha: 0.3) : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.delivery_dining, size: 18, color: Colors.blueAccent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      serviceType,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.blue.shade200 : Colors.blue.shade800),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.orange.shade900.withValues(alpha: 0.3) : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time, size: 18, color: Colors.orangeAccent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      timeSlot,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.orange.shade200 : Colors.orange.shade800),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_availableAddOns.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text('Customise',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: isDark ? AppTheme.textMainDark : AppTheme.textMain)),
                        const SizedBox(height: 10),
                        ..._availableAddOns.map((addon) {
                          final selected = _selectedAddOnIds.contains(addon.id);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              onTap: () => setState(() {
                                if (selected) {
                                  _selectedAddOnIds.remove(addon.id);
                                } else {
                                  _selectedAddOnIds.add(addon.id);
                                }
                              }),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppTheme.primary.withValues(alpha: 0.1)
                                      : (isDark ? AppTheme.surfaceDark : AppTheme.surfaceMutedLight),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: selected ? AppTheme.primary : AppTheme.hairlineOf(context)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      selected ? Icons.check_circle : Icons.circle_outlined,
                                      color: selected ? AppTheme.primary : AppTheme.textMuted,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        addon.title,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      addon.price > 0 ? '+₹${addon.price.toInt()}' : 'Free',
                                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 24),
                      Text('About this meal',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isDark ? AppTheme.textMainDark : AppTheme.textMain)),
                      const SizedBox(height: 8),
                      Text(
                        meal['description']?.toString() ??
                            'Delicious home-cooked meal prepared with love and high hygiene standards.',
                        style: TextStyle(
                            color: isDark ? Colors.grey.shade400 : AppTheme.textMuted, fontSize: 14, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 24,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
            boxShadow: AppTheme.heavyShadow,
          ),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 20, color: AppTheme.primary),
                      onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                    ),
                    Text('$_quantity',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: isDark ? AppTheme.textMainDark : AppTheme.textMain)),
                    IconButton(
                      icon: const Icon(Icons.add, size: 20, color: AppTheme.primary),
                      onPressed: _quantity < maxStock
                          ? () => setState(() => _quantity++)
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Only $maxStock portions available.'),
                                    backgroundColor: Colors.orangeAccent,
                                    behavior: SnackBarBehavior.floating),
                              );
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: !isMealAvailableForCart(meal)
                      ? null
                      : () async {
                          final added = await addMealToCartWithConflict(
                            context: context,
                            ref: widget.ref,
                            meal: meal,
                            quantity: _quantity,
                            addOns: _chosenAddOns,
                          );
                          if (!added || !context.mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Added $_quantity portion(s) to cart!'),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                  child: Text(
                    isMealAvailableForCart(meal)
                        ? 'Add to Cart • ₹${_lineFoodTotal.toInt()}'
                        : 'Sold out',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 7. Streamlined Auth Flow
void showAuthBottomSheet(
  BuildContext context,
  VoidCallback onSuccess, {
  String? title,
  String? subtitle,
}) {
  showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => AuthScreen(
      asSheet: true,
      sheetTitle: title,
      sheetSubtitle: subtitle,
    ),
  ).then((ok) {
    if (ok == true) onSuccess();
  });
}

// 8. Dynamic Meal Rating Badge
class MealRatingBadge extends StatefulWidget {
  final Map<String, dynamic> meal;
  const MealRatingBadge({super.key, required this.meal});

  @override
  State<MealRatingBadge> createState() => _MealRatingBadgeState();
}

class _MealRatingBadgeState extends State<MealRatingBadge> {
  static final Map<String, Map<String, dynamic>> _ratingCache = {};

  double _rating = 4.8;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _fetchRealRatings();
  }

  Future<void> _fetchRealRatings() async {
    final chefId = widget.meal['chef_id']?.toString() ?? '';
    if (chefId.isEmpty) return;

    if (_ratingCache.containsKey(chefId)) {
      if (mounted) {
        setState(() {
          _rating = _ratingCache[chefId]!['rating'];
          _count = _ratingCache[chefId]!['count'];
        });
      }
      return;
    }

    try {
      final res = await Supabase.instance.client
          .from('reviews')
          .select('rating')
          .eq('chef_id', chefId);

      if (!mounted) return;

      if (res.isNotEmpty) {
        double sum = 0;
        for (var r in res) {
          sum += double.tryParse(r['rating'].toString()) ?? 5.0;
        }
        final calculatedRating = sum / res.length;
        final reviewCount = res.length;

        _ratingCache[chefId] = {'rating': calculatedRating, 'count': reviewCount};

        if (mounted) {
          setState(() {
            _rating = calculatedRating;
            _count = reviewCount;
          });
        }
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch chef ratings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star, color: Colors.amber, size: 16),
        const SizedBox(width: 4),
        Text(
          _rating.toStringAsFixed(1),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
          ),
        ),
        if (_count > 0)
          Text(' ($_count)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade400)),
      ],
    );
  }
}

// 9. Standardized Universal App Card (with tactile press feedback)
class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 16),
    this.backgroundColor,
    this.onTap,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final card = AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Container(
        margin: widget.margin,
        padding: widget.padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: widget.backgroundColor ?? (isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight),
          borderRadius: AppTheme.radiusLg,
          boxShadow: isDark ? const [] : AppTheme.softShadow,
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFEDE6E0),
          ),
        ),
        child: widget.child,
      ),
    );

    if (widget.onTap == null) return card;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }
}