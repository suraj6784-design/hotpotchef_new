// lib/screens/customer_hub.dart

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_role.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/kitchen_follows_provider.dart';
import '../providers/last_order_provider.dart';
import '../providers/meal_plans_provider.dart';
import '../services/auth_session.dart';
import '../utils/app_haptics.dart';
import '../utils/diner_locale.dart';
import '../utils/helpers.dart';
import '../widgets/app_widgets.dart';
import '../widgets/checkout_retry_banner.dart';
import '../widgets/customer_ui_components.dart';
import '../widgets/diner_storefront.dart';
import 'customer_feed_tab.dart';
import 'customer_cart_tab.dart';
import 'customer_orders_tab.dart';
import 'customer_profile_screen.dart';
import 'notifications_inbox_screen.dart';

class CustomerHubScreen extends ConsumerStatefulWidget {
  static bool returnToCartAfterLogin = false;
  final int initialTab;
  final bool skipHubRoleGuard;

  const CustomerHubScreen({
    super.key,
    this.initialTab = 0,
    this.skipHubRoleGuard = false,
  });

  @override
  ConsumerState<CustomerHubScreen> createState() => _CustomerHubScreenState();
}

class _CustomerHubScreenState extends ConsumerState<CustomerHubScreen> {
  int _selectedIndex = 0;
  int _ordersEpoch = 0;
  StreamSubscription<AuthState>? _authSub;

  bool get _signedIn => Supabase.instance.client.auth.currentUser != null;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab;
    if (!_signedIn && (_selectedIndex == 2 || _selectedIndex == 4)) {
      _selectedIndex = 0;
    }
    if (CustomerHubScreen.returnToCartAfterLogin && Supabase.instance.client.auth.currentUser != null) {
      _selectedIndex = 1;
      CustomerHubScreen.returnToCartAfterLogin = false;
    }
    if (!widget.skipHubRoleGuard &&
        Supabase.instance.client.auth.currentUser != null) {
      unawaited(AuthSession.ensureHubRole(context, AppRole.customer));
    }
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.session == null && (_selectedIndex == 2 || _selectedIndex == 4)) {
        setState(() => _selectedIndex = 0);
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _handleLogout() async {
    final signedOut = await AuthSession.confirmSignOut(context, beforeNavigate: () async {
      ref.read(cartProvider.notifier).clearCart();
      ref.invalidate(favoritesProvider);
      ref.invalidate(kitchenFollowsProvider);
      ref.invalidate(lastOrderProvider);
      ref.invalidate(mealPlansProvider);
    });
    if (signedOut && mounted) setState(() => _selectedIndex = 0);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _navigateToProfile() {
    _onNavigationItemTapped(3);
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

  int get _dockIndex => dinerHubDockIndex(_selectedIndex, signedIn: _signedIn);

  void _onDockTapped(int dock) {
    final index = dinerHubIndexForDock(dock);
    if (!_signedIn && (index == 2 || index == 4)) {
      showAuthBottomSheet(context, () {
        if (!mounted || Supabase.instance.client.auth.currentUser == null) return;
        _onNavigationItemTapped(index);
      });
      return;
    }
    _onNavigationItemTapped(index);
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final favoriteSet = ref.watch(favoritesProvider);
    final favoritesList = favoriteSet.keys.toList();

    final sessionKey = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
    final List<Widget> pages = [
      CustomerFeedTab(
        key: ValueKey('home-$sessionKey'),
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
        key: ValueKey('orders-$sessionKey'),
        refreshEpoch: _ordersEpoch,
        onProfileTap: _navigateToProfile,
        onLogout: _handleLogout,
        onReorderToCart: () => _onNavigationItemTapped(2),
      ),
      CustomerProfileScreen(
        key: ValueKey('account-$sessionKey'),
        embedded: true,
        onLogout: () async {
          await _handleLogout();
          if (mounted) setState(() => _selectedIndex = 0);
        },
      ),
      NotificationsInboxScreen(
        key: ValueKey('alerts-$sessionKey'),
        embedded: true,
      ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      body: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(bottom: hubDockBodyGap(context)),
              child: HubTabSwitcher(
                index: _selectedIndex,
                children: pages,
              ),
            ),
          ),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(bottom: false, child: CheckoutRetryBanner()),
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
                    color: AppTheme.primary,
                    borderRadius: AppTheme.radiusLg,
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
                              style: AppTheme.caption.copyWith(color: Colors.white70),
                            ),
                            Text(
                              '₹${cartState.foodTotal.toStringAsFixed(0)} · ${cartState.itemCount} item${cartState.itemCount == 1 ? '' : 's'}',
                              style: AppTheme.homeCardTitleOf(context).copyWith(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        DinerLocaleController.instance.copy.viewCart,
                        style: AppTheme.cardTitleOf(context).copyWith(color: Colors.white),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward, color: Colors.white, size: 22),
                    ],
                  ),
                ),
              ),
            ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ListenableBuilder(
              listenable: DinerLocaleController.instance,
              builder: (context, _) {
                final copy = DinerLocaleController.instance.copy;
                return HubBottomDock(
                  selectedIndex: _dockIndex,
                  onSelect: _onDockTapped,
                  destinations: [
                    HubDockDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: copy.home),
                    HubDockDestination(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, label: copy.orders),
                    HubDockDestination(icon: Icons.person_outline, selectedIcon: Icons.person, label: copy.account),
                    HubDockDestination(icon: Icons.notifications_outlined, selectedIcon: Icons.notifications, label: copy.notifications),
                  ],
                );
              },
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