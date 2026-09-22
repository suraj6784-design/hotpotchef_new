// lib/screens/customer_cart_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/app_page.dart';
import '../utils/helpers.dart';
import '../utils/delivery_fee.dart';
import '../utils/pricing_calculator.dart';
import '../models/cart_state.dart';
import '../models/cart_enums.dart';
import '../providers/cart_provider.dart';
import '../providers/delivery_preference.dart';
import '../widgets/customer_ui_components.dart';
import '../widgets/app_widgets.dart';
import '../widgets/group_order_modal.dart';
import '../services/reorder_service.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cartProvider.notifier).fetchUserCoins();
    });
  }

  void _maybeShowStockNotice(CartState cartState) {
    final notice = cartState.stockNotice;
    if (notice == null || notice.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
      ref.read(cartProvider.notifier).clearStockNotice();
    });
  }

  // --- Sub-Slot Generator ---

  List<String> _generateSubSlots(String rawChefSlot) => chefHourlySubSlots(rawChefSlot);

  List<String> _futureSlotsForDate(List<String> slots, DateTime date) {
    return slots.where((slot) => !isCartSlotPassed(slot, date)).toList();
  }

  // --- Multi-Vendor Conflict Modal ---

  Future<bool> _verifySingleVendorOrPrompt(CartState cartState) async {
    if (!cartState.hasVendorConflict) return true;

    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceOf(context),
        shape: AppTheme.dialogShape,
        title: const Text('Multi-Chef Cart Notice', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Your cart contains dishes from multiple kitchens. Food delivery orders must be placed from a single kitchen at a time. Would you like to clear your cart and proceed with this order?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
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

  List<CartItemAddOn> _catalogExtras(CartItemModel item) {
    return ReorderService.parseMealAddOns(
      item.rawMealDetails['add_ons'] ?? item.rawMealDetails['addons'],
    );
  }

  Future<void> _editCartExtras(CartItemModel item) async {
    var catalog = _catalogExtras(item);
    if (catalog.isEmpty) {
      try {
        final row = await Supabase.instance.client
            .from('meals')
            .select('add_ons')
            .eq('id', item.mealId)
            .maybeSingle();
        catalog = ReorderService.parseMealAddOns(row?['add_ons']);
      } catch (_) {}
    }
    if (!mounted) return;
    if (catalog.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This plate has no extras from the kitchen yet.')),
      );
      return;
    }

    final selectedIds = catalog
        .where((addon) => item.selectedAddOns.any((picked) => picked.id == addon.id || picked.title == addon.title))
        .map((addon) => addon.id)
        .toSet();

    final picked = await showModalBottomSheet<List<CartItemAddOn>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: AppTheme.bottomSheetDecoration(
                isDark: Theme.of(ctx).brightness == Brightness.dark,
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Add extra',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.onSurfaceOf(ctx),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Optional sides for ${item.title}',
                    style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 16),
                  ...catalog.map((addon) {
                    final selected = selectedIds.contains(addon.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => setSheetState(() {
                          if (selected) {
                            selectedIds.remove(addon.id);
                          } else {
                            selectedIds.add(addon.id);
                          }
                        }),
                        borderRadius: AppTheme.radiusMd,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.primary.withValues(alpha: 0.1)
                                : AppTheme.surfaceOf(ctx),
                            borderRadius: AppTheme.radiusMd,
                            border: Border.all(
                              color: selected ? AppTheme.primary : AppTheme.hairlineOf(ctx),
                            ),
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
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text(
                                addon.price > 0 ? '+₹${addon.price.toInt()}' : 'Free',
                                style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.link),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(
                        ctx,
                        catalog.where((addon) => selectedIds.contains(addon.id)).toList(),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    child: const Text('Save extras'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (picked == null || !mounted) return;
    ref.read(cartProvider.notifier).updateItemAddOns(
          item.id,
          picked,
          catalog: [for (final addon in catalog) addon.toJson()],
        );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cartState = ref.watch(cartProvider);
    _maybeShowStockNotice(cartState);
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;

    if (cartState.items.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.canvasOf(context),
        appBar: HubAppBar(
          title: 'Your Cart',
          onProfile: isLoggedIn ? widget.onProfileTap : null,
        ),
        body: EmptyState(
          icon: Icons.shopping_basket_outlined,
          title: 'Your plate is empty!',
          message: 'Discover fresh, home-cooked meals from local chefs and add your favourites.',
          actionLabel: 'Browse Menu',
          onAction: widget.onAddMoreMeals,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: HubAppBar(
        title: 'Your Cart',
        onProfile: isLoggedIn ? widget.onProfileTap : null,
      ),
      body: ListView(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 100),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items in cart (${cartState.itemCount})',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.onSurfaceOf(context))),
              IconButton(
                tooltip: 'Clear cart',
                color: Colors.red,
                icon: const Icon(Icons.delete_sweep, size: 20),
                onPressed: () => ref.read(cartProvider.notifier).clearCart(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if ((cartState.sharedRoomCode ?? '').isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: AppTheme.radiusMd,
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${groupPlaceKindLabel(cartState.sharedPlaceKind)} · ${cartState.sharedRoomCode}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppTheme.onSurfaceOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if ((cartState.sharedPlaceLabel ?? '').trim().isNotEmpty) cartState.sharedPlaceLabel!.trim(),
                      if ((cartState.sharedTimeSlot ?? '').trim().isNotEmpty) 'Slot ${cartState.sharedTimeSlot!.trim()}',
                      if ((cartState.sharedDropoffNote ?? '').trim().isNotEmpty) 'Drop ${cartState.sharedDropoffNote!.trim()}',
                      'Neighbours add plates — host pays once.',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final text = societyGroupInviteText(
                              roomCode: cartState.sharedRoomCode!,
                              placeKind: cartState.sharedPlaceKind,
                              placeLabel: cartState.sharedPlaceLabel,
                              dropoffNote: cartState.sharedDropoffNote,
                              timeSlot: cartState.sharedTimeSlot,
                            );
                            final opened = await launchUrl(
                              mealWhatsAppShareUri(text),
                              mode: LaunchMode.externalApplication,
                            );
                            if (!opened) {
                              await Clipboard.setData(ClipboardData(text: text));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Invite copied')),
                              );
                            }
                          },
                          icon: const Icon(Icons.chat, size: 16),
                          label: const Text('Invite WhatsApp'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => ref.read(cartProvider.notifier).detachSharedRoom(),
                        child: const Text('Leave'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Multi-vendor Warning Banner if applicable
          if (cartState.hasVendorConflict)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: AppTheme.radiusMd,
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

          ...cartState.items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final cartItemId = item.id;
            final offered = (item.rawMealDetails['service_type']?.toString() ?? '')
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .map(ServiceType.fromString)
                .toSet();
            final availableServices =
                offered.isEmpty ? ServiceType.values.toList() : offered.toList();
            final currentService = availableServices.contains(item.serviceType)
                ? item.serviceType
                : availableServices.first;

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
            final bookedSlot = [
              item.timeSlot,
              exactTime,
            ].whereType<String>().map((s) => s.trim()).firstWhere(
                  (s) => s.isNotEmpty && !isImmediateDeliverySlot(s) && !looksLikeChefServingWindow(s),
                  orElse: () => '',
                );
            final displayTimeSlot = dinerSelectedClockLabel(bookedSlot);
            final slotIssue = cartLineSlotValidationError(
              selectedSlot: bookedSlot.isEmpty ? (item.timeSlot ?? exactTime ?? '') : bookedSlot,
              scheduledDate: item.scheduledDate,
              chefSchedule: rawSchedule,
            );

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
                          borderRadius: AppTheme.radiusSm,
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title.isNotEmpty ? item.title : 'Meal Item',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.onSurfaceOf(context)),
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
                                child: Text(
                                  PricingCalculator.calculateItemSummary(item.rawMealDetails, qty)
                                          .offerDescription ??
                                      'Special Offer Applied',
                                  style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.textMuted),
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
                    const SizedBox(height: 4),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _editCartExtras(item),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: Icon(
                        item.selectedAddOns.isEmpty ? Icons.add_circle_outline : Icons.tune,
                        size: 18,
                      ),
                      label: Text(
                        item.selectedAddOns.isEmpty ? 'Add extra' : 'Change extras',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

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
                      borderRadius: AppTheme.radiusMd,
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ServiceType>(
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                        value: currentService,
                        style: const TextStyle(color: AppTheme.link, fontSize: 13, fontWeight: FontWeight.w600),
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
                            ref.read(cartProvider.notifier).updateItemServiceType(
                                  cartItemId,
                                  val.toDisplayString(),
                                );
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
                            final first = chefSlotPickerFirstDate(rawSchedule);
                            final last = chefSlotPickerLastDate(rawSchedule);
                            final initial = chefSlotPickerInitialDate(rawSchedule, item.scheduledDate);
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: initial.isBefore(first)
                                  ? first
                                  : (initial.isAfter(last) ? last : initial),
                              firstDate: first,
                              lastDate: last.isBefore(first) ? first : last,
                              selectableDayPredicate: (day) => chefSlotAllowsDate(rawSchedule, day),
                            );
                            if (picked != null) {
                              ref.read(cartProvider.notifier).updateItemDate(cartItemId, picked);
                              final stillValid = !isCartSlotPassed(
                                    bookedSlot.isEmpty ? (item.timeSlot ?? '') : bookedSlot,
                                    picked,
                                  ) &&
                                  isCartSlotWithinChefWindow(
                                    bookedSlot.isEmpty ? (item.timeSlot ?? '') : bookedSlot,
                                    rawSchedule,
                                  );
                              if (!stillValid) {
                                final next = futureChefSubSlots(rawSchedule, scheduledDate: picked);
                                if (next.isNotEmpty) {
                                  ref.read(cartProvider.notifier).updateItemTimeSlot(cartItemId, next.first);
                                }
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceOf(context),
                              borderRadius: AppTheme.radiusSm,
                              border: Border.all(color: AppTheme.hairlineOf(context)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 14, color: AppTheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    formatFriendlyDate(item.scheduledDate),
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context)),
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
                            final subSlots =
                                _futureSlotsForDate(_generateSubSlots(rawSchedule), item.scheduledDate);
                            final pickedSlot = await showDialog<String>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppTheme.surfaceOf(context),
                                shape: AppTheme.dialogShape,
                                title: const Text('Select Time Slot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                content: SizedBox(
                                  width: double.maxFinite,
                                  height: 220,
                                  child: subSlots.isEmpty
                                      ? const Center(
                                          child: Padding(
                                            padding: EdgeInsets.all(16),
                                            child: Text(
                                              'No more time slots available today.\nPlease choose a later day.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                                            ),
                                          ),
                                        )
                                      : ListView.builder(
                                          shrinkWrap: true,
                                          itemCount: subSlots.length,
                                          itemBuilder: (c, i) => ListTile(
                                            leading: const Icon(Icons.access_time, color: AppTheme.primary, size: 18),
                                            title: Text(
                                              dinerSelectedClockLabel(subSlots[i]),
                                              style: const TextStyle(fontSize: 13),
                                            ),
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
                              color: AppTheme.surfaceOf(context),
                              borderRadius: AppTheme.radiusSm,
                              border: Border.all(color: AppTheme.hairlineOf(context)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time, size: 14, color: AppTheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    displayTimeSlot, // Reactive UI binding
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: slotIssue != null ? Colors.redAccent : AppTheme.onSurfaceOf(context),
                                    ),
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
                  if (slotIssue != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      slotIssue,
                      style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Subtotal and Quantity Stepper
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Subtotal: ₹${itemSubtotal.toStringAsFixed(0)}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context)),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceOf(context),
                          borderRadius: AppTheme.radiusXl,
                          border: Border.all(color: AppTheme.hairlineOf(context)),
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
                                  style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context))),
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
            ).entrance(index: index);
          }),

          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add more meals'),
                  onPressed: widget.onAddMoreMeals,
                ),
              ),
              if (isLoggedIn) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.apartment_outlined),
                    label: const Text('Society / office'),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => Container(
                          decoration: AppTheme.bottomSheetDecoration(
                            isDark: Theme.of(context).brightness == Brightness.dark,
                          ),
                          child: const GroupOrderModal(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          if (PricingCalculator.applicablePromosFromCart(
                cartState.items.map((item) => item.toCheckoutPayload()),
              ).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildCartPromoCodes(cartState),
            ),

          // Premium checkout bar (inline so it clears the hub's floating dock)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceOf(context),
              borderRadius: AppTheme.radiusLg,
              boxShadow: AppTheme.softShadow,
              border: Border.all(color: AppTheme.hairlineOf(context)),
            ),
            child: Row(
              children: [
                const AppLogo(size: 36),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => _showCartBillBreakup(cartState),
                  borderRadius: AppTheme.radiusSm,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              cartState.deliveryFeeIsEstimate ? 'Est. total' : 'Total payable',
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.info_outline, size: 14, color: AppTheme.textMuted),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatRupees(cartState.grandTotal),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GradientButton(
                    label: isLoggedIn ? 'Checkout' : 'Sign in to order',
                    icon: isLoggedIn ? Icons.arrow_forward_rounded : Icons.login_rounded,
                    onPressed: () => _handleCheckoutPressed(cartState, isLoggedIn),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartPromoCodes(CartState cartState) {
    final promos = PricingCalculator.applicablePromosFromCart(
      cartState.items.map((item) => item.toCheckoutPayload()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chef codes on these meals — apply a live one at checkout.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: promos.map((promo) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: promo.isActive ? AppTheme.surfaceOf(context) : AppTheme.canvasOf(context),
                borderRadius: AppTheme.radiusMd,
                border: Border.all(
                  color: promo.isActive ? AppTheme.primary : AppTheme.hairlineOf(context),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    promo.code,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: promo.isActive ? AppTheme.onSurfaceOf(context) : AppTheme.textMuted,
                    ),
                  ),
                  Text(
                    promo.validityLabel(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: promo.isActive ? AppTheme.success : Colors.redAccent,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  List<Widget> _cartCoinsBreakupRows(
    CartState cartState,
    Widget Function(String label, String value, {Color? color, bool bold}) row,
  ) {
    switch (cartState.coinsBillKind) {
      case CartCoinsBillKind.hidden:
        return const [];
      case CartCoinsBillKind.applied:
        return [
          row(
            'HotPot Coins',
            '-${formatRupees(cartState.coinsDiscountAmount)}',
            color: AppTheme.success,
          ),
        ];
      case CartCoinsBillKind.refused:
        return [
          row(
            'HotPot Coins not accepted on this cart',
            formatRupees(cartState.userCoinBalance),
            color: AppTheme.textMuted,
          ),
        ];
      case CartCoinsBillKind.available:
        return [
          row(
            'Wallet (apply at checkout)',
            '${formatRupees(cartState.userCoinBalance)} available',
            color: AppTheme.textMuted,
          ),
        ];
    }
  }

  Future<void> _showCartBillBreakup(CartState _) async {
    await ref.read(cartProvider.notifier).fetchUserCoins();
    if (!mounted) return;
    final cartState = ref.read(cartProvider);
    final foodGross = cartState.originalFoodTotal;
    final foodNet = cartState.foodTotal;
    final promoSavings = foodGross > foodNet + 0.5 ? foodGross - foodNet : 0.0;
    final promo = PricingCalculator.applicablePromosFromCart(
      cartState.items.map((item) => item.toCheckoutPayload()),
    ).where((item) => item.isActive).map((item) => item.code).firstOrNull;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final ink = AppTheme.onSurfaceOf(ctx);
        Widget row(String label, String value, {Color? color, bool bold = false}) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color ?? AppTheme.textMuted,
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: color ?? ink,
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          decoration: AppTheme.bottomSheetDecoration(
            isDark: Theme.of(ctx).brightness == Brightness.dark,
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bill breakup', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: ink)),
              const SizedBox(height: 16),
              row('Items', formatRupees(foodGross)),
              if (promoSavings > 0)
                row(
                  promo == null ? 'Offer on plate price' : 'Promo ($promo) — apply at checkout',
                  '-${formatRupees(promoSavings)}',
                  color: AppTheme.success,
                ),
              row(
                packagingFeeLineLabel(fee: cartState.packagingFee, loyaltyTier: cartState.loyaltyTier),
                formatRupees(cartState.packagingFee),
              ),
              if (cartState.hasDelivery)
                row(
                  deliveryFeeBillLabel(
                    fee: cartState.estimatedDeliveryFee,
                    foodTotal: foodNet,
                    membershipWaivesDelivery: cartState.membershipWaivesDelivery,
                    pinMissing: cartState.deliveryFeeIsEstimate,
                  ),
                  formatRupees(cartState.estimatedDeliveryFee),
                ),
              if (cartState.tipAmount > 0) row('Tip', formatRupees(cartState.tipAmount)),
              ..._cartCoinsBreakupRows(cartState, row),
              Divider(height: 20, color: AppTheme.hairlineOf(ctx)),
              row(
                cartState.deliveryFeeIsEstimate ? 'Est. total' : 'Total payable',
                formatRupees(cartState.grandTotal),
                bold: true,
                color: ink,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleCheckoutPressed(CartState cartState, bool isLoggedIn) async {
    if (!isLoggedIn) {
      CustomerHubScreen.returnToCartAfterLogin = true;
      showAuthBottomSheet(
        context,
        () {
          ref.read(cartProvider.notifier).syncGuestCartToUser();
          if (mounted) setState(() {});
        },
        title: 'Sign in to order',
        subtitle: 'Your cart is still here. Sign in to continue checkout.',
      );
      return;
    }

    if (!canPaySharedCart(
      roomCode: cartState.sharedRoomCode,
      hostId: cartState.sharedHostId,
      userId: Supabase.instance.client.auth.currentUser?.id,
    )) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the group host can pay for this cart.')),
      );
      return;
    }

    // Validate single-vendor requirement
    final canProceed = await _verifySingleVendorOrPrompt(cartState);
    if (!canProceed || !mounted) return;

    final checkoutItems = cartState.items.map((i) => i.toCheckoutPayload()).toList();
    final slotIssue = cartItemsSlotValidationError(checkoutCartPayload(checkoutItems));
    if (slotIssue != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(slotIssue), backgroundColor: Colors.redAccent),
      );
      return;
    }

    await ref.read(cartProvider.notifier).fetchUserCoins();
    if (!mounted) return;

    dismissAppSnackBars(context);
    Navigator.push(
      context,
      appMaterialRoute(
        CheckoutScreen(
          cartItems: checkoutItems,
          preferredAddressId: ref.read(selectedDeliveryAddressProvider)?['id'],
          preferredAddress: ref.read(selectedDeliveryAddressProvider),
          sharedRoomCode: cartState.sharedRoomCode,
          sharedHostId: cartState.sharedHostId,
          sharedPlaceKind: cartState.sharedPlaceKind,
          sharedPlaceLabel: cartState.sharedPlaceLabel,
          sharedDropoffNote: cartState.sharedDropoffNote,
          sharedTimeSlot: cartState.sharedTimeSlot,
          onOrderPlacedSuccess: () {
            ref.read(cartProvider.notifier).clearCart();
            widget.onOrderPlacedSuccess();
          },
        ),
      ),
    );
  }
}