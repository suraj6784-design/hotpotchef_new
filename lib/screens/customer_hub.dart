// lib/screens/customer_hub.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../services/auth_session.dart';
import '../utils/app_theme.dart';
import '../widgets/app_widgets.dart';
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
  }

  Future<void> _handleLogout() async {
    await AuthSession.logout(context, beforeNavigate: () async {
      ref.read(cartProvider.notifier).clearCart();
      ref.invalidate(favoritesProvider);
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
        onReorderToCart: () => _onNavigationItemTapped(1),
      ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: pages,
          ),

          if (cartState.items.isNotEmpty && _selectedIndex == 0)
            Positioned(
              bottom: 92,
              left: 20,
              right: 20,
              child: GestureDetector(
                onTap: () => _onNavigationItemTapped(1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: AppTheme.brandGlow(opacity: 0.32),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                            child: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${cartState.itemCount} items in bag', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              Text('₹${cartState.foodTotal.toStringAsFixed(0)}',
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ],
                      ),
                      const Row(
                        children: [
                          Text('View cart', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Positioned(
            bottom: 20,
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