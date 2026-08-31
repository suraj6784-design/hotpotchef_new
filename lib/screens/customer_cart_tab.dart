// lib/screens/customer_cart_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import '../utils/app_theme.dart';
import '../models/cart_state.dart';
import '../models/cart_enums.dart';
import '../providers/cart_provider.dart';
import '../widgets/customer_ui_components.dart';
import 'checkout_screen.dart';
import 'customer_hub.dart';

class CustomerCartTab extends ConsumerStatefulWidget {
  final VoidCallback onAddMoreMeals;
  final VoidCallback onOrderPlacedSuccess;
  final VoidCallback onProfileTap;
  final VoidCallback onLogout;

  const CustomerCartTab({
    super.key,
    required this.onAddMoreMeals,
    required this.onOrderPlacedSuccess,
    required this.onProfileTap,
    required this.onLogout,
  });

  @override
  ConsumerState<CustomerCartTab> createState() => _CustomerCartTabState();
}

class _CustomerCartTabState extends ConsumerState<CustomerCartTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // --- Sub-Slot Generator ---

  List<String> _generateSubSlots(String rawChefSlot) {
    String timeRangeStr = rawChefSlot;

    if (rawChefSlot.contains('(') && rawChefSlot.contains(')')) {
      final startIndex = rawChefSlot.indexOf('(');
      final endIndex = rawChefSlot.lastIndexOf(')');
      if (startIndex < endIndex) {
        timeRangeStr = rawChefSlot.substring(startIndex + 1, endIndex).trim();
      }
    }

    if (!timeRangeStr.toLowerCase().contains('to')) {
      return [timeRangeStr];
    }

    try {
      final parts = timeRangeStr.split(RegExp('to', caseSensitive: false));
      if (parts.length < 2) return [timeRangeStr];

      final startStr = parts[0].trim();
      final endStr = parts[1].trim();

      TimeOfDay startTime = _parseTimeOfDay(startStr);
      TimeOfDay endTime = _parseTimeOfDay(endStr);

      List<String> generatedSlots = [];
      int currentMinutes = startTime.hour * 60 + startTime.minute;
      int endMinutes = endTime.hour * 60 + endTime.minute;

      if (endMinutes <= currentMinutes) {
        endMinutes += 24 * 60;
      }

      const intervalMinutes = 60;
      while (currentMinutes + intervalMinutes <= endMinutes) {
        int slotStartHour = (currentMinutes ~/ 60) % 24;
        int slotStartMin = currentMinutes % 60;

        int nextMinutes = currentMinutes + intervalMinutes;
        int slotEndHour = (nextMinutes ~/ 60) % 24;
        int slotEndMin = nextMinutes % 60;

        TimeOfDay t1 = TimeOfDay(hour: slotStartHour, minute: slotStartMin);
        TimeOfDay t2 = TimeOfDay(hour: slotEndHour, minute: slotEndMin);

        generatedSlots.add('${t1.format(context)} to ${t2.format(context)}');
        currentMinutes = nextMinutes;
      }

      return generatedSlots.isNotEmpty ? generatedSlots : [timeRangeStr];
    } catch (_) {
      return [timeRangeStr];
    }
  }

  TimeOfDay _parseTimeOfDay(String timeStr) {
    final cleaned = timeStr.toUpperCase().replaceAll(' ', '');
    bool isPM = cleaned.contains('PM');
    bool isAM = cleaned.contains('AM');

    String rawTime = cleaned.replaceAll('AM', '').replaceAll('PM', '');
    List<String> timeParts = rawTime.split(':');
    int hour = int.tryParse(timeParts[0]) ?? 12;
    int minute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;

    if (isPM && hour < 12) hour += 12;
    if (isAM && hour == 12) hour = 0;

    return TimeOfDay(hour: hour, minute: minute);
  }

  // --- Multi-Vendor Conflict Modal ---

  Future<bool> _verifySingleVendorOrPrompt(CartState cartState) async {
    if (!cartState.hasVendorConflict) return true;

    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Multi-Chef Cart Notice', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Your cart contains dishes from multiple kitchens. Food delivery orders must be placed from a single kitchen at a time. Would you like to clear your cart and proceed with this order?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear & Proceed'),
          ),
        ],
      ),
    );

    if (shouldClear == true) {
      await ref.read(cartProvider.notifier).clearCart();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cartState = ref.watch(cartProvider);
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;

    if (cartState.items.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.asset('assets/app_icon.png', height: 24, width: 24)),
              const SizedBox(width: 8),
              const Text('Your Cart'),
            ],
          ),
          actions: [
            if (isLoggedIn) ...[
              IconButton(icon: const Icon(Icons.person, color: AppTheme.primary), onPressed: widget.onProfileTap),
              IconButton(icon: const Icon(Icons.logout, color: Colors.grey), onPressed: widget.onLogout),
            ],
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                child: Icon(Icons.shopping_basket_outlined, size: 64, color: Colors.orange.shade300),
              ),
              const SizedBox(height: 24),
              const Text('Your plate is empty!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: widget.onAddMoreMeals, child: const Text('Browse Menu')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.asset('assets/app_icon.png', height: 24, width: 24)),
            const SizedBox(width: 8),
            const Text('Your Cart'),
          ],
        ),
        actions: [
          if (isLoggedIn) ...[
            IconButton(icon: const Icon(Icons.person, color: AppTheme.primary), onPressed: widget.onProfileTap),
            IconButton(icon: const Icon(Icons.logout, color: Colors.grey), onPressed: widget.onLogout),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 100),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items in Cart (${cartState.itemCount})',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.textMain)),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                icon: const Icon(Icons.delete_sweep, size: 16),
                label: const Text('Clear Cart'),
                onPressed: () => ref.read(cartProvider.notifier).clearCart(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Multi-vendor Warning Banner if applicable
          if (cartState.hasVendorConflict)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Items from multiple chefs detected. Please order from one kitchen at a time.',
                      style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          ...cartState.items.map((item) {
            final cartItemId = item.id;
            final availableServices = ServiceType.values;
            final currentService = item.serviceType;

            final isOfferActive = item.discountedPrice != null ||
                cartState.isOfferActive(item.rawMealDetails);
            final double basePrice = item.basePrice;
            final int qty = item.quantity;
            final double itemSubtotal = cartState.getEffectiveItemTotal(item);

            final rawSchedule = item.rawMealDetails['time_slot']?.toString() ??
                item.rawMealDetails['chef_schedule']?.toString() ??
                'Select Slot';
                
            // Safely fetch the exact time updated from the provider
            final exactTime = item.rawMealDetails['exact_time']?.toString();
            final displayTimeSlot = (exactTime != null && exactTime.isNotEmpty) ? exactTime : rawSchedule;

            return AppCard(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (item.rawMealDetails['image_url'] != null) ...[
                        WatermarkedMealImage(
                          imageUrl: item.rawMealDetails['image_url'],
                          width: 50,
                          height: 50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title.isNotEmpty ? item.title : 'Meal Item',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMain),
                            ),
                            if (isOfferActive)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: const Text(
                                  '🔥 Special Offer Applied',
                                  style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => ref.read(cartProvider.notifier).removeItem(cartItemId),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Add-on Tags Display
                  if (item.selectedAddOns.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: item.selectedAddOns
                          .map((addon) => Chip(
                                label: Text('${addon.title} (+₹${addon.price.toStringAsFixed(0)})',
                                    style: const TextStyle(fontSize: 10)),
                                backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                  ],

                  Row(
                    children: [
                      Text(
                        '₹${basePrice.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: isOfferActive ? Colors.grey : AppTheme.textMuted,
                          decoration: isOfferActive ? TextDecoration.lineThrough : null,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      if (isOfferActive) ...[
                        const SizedBox(width: 8),
                        Text(
                          '₹${(itemSubtotal / qty).toStringAsFixed(0)} / portion',
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ]
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Service Type Selector Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ServiceType>(
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                        value: currentService,
                        style: const TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w600),
                        items: availableServices.map((svc) {
                          return DropdownMenuItem(
                            value: svc,
                            child: Row(
                              children: [
                                Icon(
                                  svc.isDelivery ? Icons.delivery_dining : Icons.storefront,
                                  size: 16,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(svc.toDisplayString()),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            ref.read(cartProvider.notifier).updateItemServiceType(cartItemId, val.toString());
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Schedule Date & Slot pickers
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: item.scheduledDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 30)),
                            );
                            if (picked != null) {
                              ref.read(cartProvider.notifier).updateItemDate(cartItemId, picked);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 14, color: AppTheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    formatFriendlyDate(item.scheduledDate),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final subSlots = _generateSubSlots(rawSchedule);
                            final pickedSlot = await showDialog<String>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Select Time Slot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                content: SizedBox(
                                  width: double.maxFinite,
                                  height: 220,
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: subSlots.length,
                                    itemBuilder: (c, i) => ListTile(
                                      leading: const Icon(Icons.access_time, color: AppTheme.primary, size: 18),
                                      title: Text(subSlots[i], style: const TextStyle(fontSize: 13)),
                                      onTap: () => Navigator.pop(ctx, subSlots[i]),
                                    ),
                                  ),
                                ),
                              ),
                            );

                            if (pickedSlot != null) {
                              ref.read(cartProvider.notifier).updateItemTimeSlot(cartItemId, pickedSlot);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time, size: 14, color: AppTheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    displayTimeSlot, // Reactive UI binding
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Subtotal and Quantity Stepper
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Subtotal: ₹${itemSubtotal.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMain),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove, color: AppTheme.primary, size: 16),
                              onPressed: () => ref.read(cartProvider.notifier).updateQuantity(cartItemId, -1),
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              padding: EdgeInsets.zero,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text('${item.quantity}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, color: AppTheme.primary, size: 16),
                              onPressed: () => ref.read(cartProvider.notifier).updateQuantity(cartItemId, 1),
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Add More Meals'),
            onPressed: widget.onAddMoreMeals,
          ),
          const SizedBox(height: 32),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () async {
              if (!isLoggedIn) {
                CustomerHubScreen.returnToCartAfterLogin = true;
                showAuthBottomSheet(context, () => setState(() {}));
                return;
              }

              // Validate single-vendor requirement
              final canProceed = await _verifySingleVendorOrPrompt(cartState);
              if (!canProceed || !context.mounted) return;

              final checkoutItems = cartState.items.map((i) => i.toJson()).toList();

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CheckoutScreen(
                    cartItems: checkoutItems,
                    onOrderPlacedSuccess: () {
                      ref.read(cartProvider.notifier).clearCart();
                      widget.onOrderPlacedSuccess();
                    },
                  ),
                ),
              );
            },
            child: Text(
              'Proceed to Checkout (₹${cartState.grandTotal.toStringAsFixed(0)})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}