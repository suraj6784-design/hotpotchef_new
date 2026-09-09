// lib/screens/customer_hub.dart

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/app_role.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/kitchen_follows_provider.dart';
import '../providers/last_order_provider.dart';
import '../providers/meal_plans_provider.dart';
import '../services/auth_session.dart';
import '../utils/app_haptics.dart';
import '../utils/app_theme.dart';
import '../utils/helpers.dart';
import '../widgets/app_widgets.dart';
import '../widgets/customer_ui_components.dart';
import 'customer_feed_tab.dart';
import 'customer_cart_tab.dart';
import 'customer_orders_tab.dart';

class CustomerHubScreen extends ConsumerStatefulWidget {
  static bool returnToCartAfterLogin = false;
  final int initialTab;

  const CustomerHubScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<CustomerHubScreen> createState() => _CustomerHubScreenState();
}

class _CustomerHubScreenState extends ConsumerState<CustomerHubScreen> {
  int _selectedIndex = 0;
  int _ordersEpoch = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab;
    if (CustomerHubScreen.returnToCartAfterLogin && Supabase.instance.client.auth.currentUser != null) {
      _selectedIndex = 1;
      CustomerHubScreen.returnToCartAfterLogin = false;
    }
    if (Supabase.instance.client.auth.currentUser != null) {
      unawaited(AuthSession.ensureHubRole(context, AppRole.customer));
    }
  }

  Future<void> _handleLogout() async {
    await AuthSession.logout(context, beforeNavigate: () async {
      ref.read(cartProvider.notifier).clearCart();
      ref.invalidate(favoritesProvider);
      ref.invalidate(kitchenFollowsProvider);
      ref.invalidate(lastOrderProvider);
      ref.invalidate(mealPlansProvider);
    });
    if (mounted) setState(() => _selectedIndex = 0);
  }

  void _navigateToProfile() {
    context.push('/customer-profile').then((result) {
      if (result == 'go_to_orders') {
        _onNavigationItemTapped(2);
      } else {
        setState(() {});
      }
    });
  }

  void _onNavigationItemTapped(int index) {
    if (index == 1) {
      dismissAppSnackBars(context);
    }
    setState(() {
      _selectedIndex = index;
      if (index == 2) _ordersEpoch++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final favoriteSet = ref.watch(favoritesProvider);
    final favoritesList = favoriteSet.keys.toList();

    final List<Widget> pages = [
      CustomerFeedTab(
        favoriteMeals: favoritesList,
        onToggleFavorite: (id) => ref.read(favoritesProvider.notifier).toggleFavorite(id),
        onProfileTap: _navigateToProfile,
        onLogout: _handleLogout,
        onGoToCart: () => _onNavigationItemTapped(1),
        onReorderToOrders: () => _onNavigationItemTapped(2),
      ),
      CustomerCartTab(
        onAddMoreMeals: () => _onNavigationItemTapped(0),
        onOrderPlacedSuccess: () => _onNavigationItemTapped(2),
        onProfileTap: _navigateToProfile,
        onLogout: _handleLogout,
      ),
      CustomerOrdersTab(
        refreshEpoch: _ordersEpoch,
        onProfileTap: _navigateToProfile,
        onLogout: _handleLogout,
        onReorderToCart: () => _onNavigationItemTapped(2),
      ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      body: Stack(
        children: [
          HubTabSwitcher(
            index: _selectedIndex,
            children: pages,
          ),

          if (cartState.items.isNotEmpty && _selectedIndex == 0)
            Positioned(
              bottom: 92,
              left: 20,
              right: 20,
              child: GestureDetector(
                onTap: () {
                  AppHaptics.light();
                  dismissAppSnackBars(context);
                  _onNavigationItemTapped(1);
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: AppTheme.brandGlow(opacity: 0.16),
                  ),
                  child: Row(
                    children: [
                      _CartThumbStack(
                        urls: cartState.items
                            .map((item) => item.rawMealDetails['image_url']?.toString() ?? '')
                            .where((url) => url.isNotEmpty)
                            .take(3)
                            .toList(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              cartState.items.map((item) => item.chefId).toSet().length > 1
                                  ? '${cartState.itemCount} plates · ${cartState.items.map((item) => item.chefId).toSet().length} kitchens'
                                  : chefDisplayName(cartState.items.first.rawMealDetails),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '₹${cartState.foodTotal.toStringAsFixed(0)} · ${cartState.itemCount} item${cartState.itemCount == 1 ? '' : 's'}',
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      const Text('Checkout', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                    ],
                  ),
                ).popIn(),
              ),
            ),

          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: HubBottomDock(
              selectedIndex: _selectedIndex,
              onSelect: _onNavigationItemTapped,
              destinations: [
                const HubDockDestination(icon: Icons.cottage_outlined, selectedIcon: Icons.cottage, label: 'Home'),
                HubDockDestination(
                  icon: Icons.shopping_basket_outlined,
                  selectedIcon: Icons.shopping_basket,
                  label: 'Cart',
                  badgeCount: cartState.itemCount,
                ),
                const HubDockDestination(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, label: 'Orders'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartThumbStack extends StatelessWidget {
  const _CartThumbStack({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return const AppLogo(size: 36, onDark: true);
    }
    final show = urls.take(3).toList();
    return SizedBox(
      width: 28.0 + (show.length - 1) * 18,
      height: 36,
      child: Stack(
        children: [
          for (var i = 0; i < show.length; i++)
            Positioned(
              left: i * 18.0,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: show[i],
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const ColoredBox(color: AppTheme.photoFallback),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CartThumbStack extends StatelessWidget {
  const _CartThumbStack({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return const AppLogo(size: 36, onDark: true);
    }
    final show = urls.take(3).toList();
    return SizedBox(
      width: 28.0 + (show.length - 1) * 18,
      height: 36,
      child: Stack(
        children: [
          for (var i = 0; i < show.length; i++)
            Positioned(
              left: i * 18,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: show[i],
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const ColoredBox(color: AppTheme.photoFallback),
                ),
              ),
            ),
        ],
      ),
    );
  }
}