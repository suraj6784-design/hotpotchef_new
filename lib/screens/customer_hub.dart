// lib/screens/customer_hub.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../services/push_notification_service.dart';
import '../utils/app_theme.dart';
import 'customer_feed_tab.dart';
import 'customer_cart_tab.dart';
import 'customer_orders_tab.dart';

class CustomerHubScreen extends ConsumerStatefulWidget {
  static bool returnToCartAfterLogin = false;
  const CustomerHubScreen({super.key});

  @override
  ConsumerState<CustomerHubScreen> createState() => _CustomerHubScreenState();
}

class _CustomerHubScreenState extends ConsumerState<CustomerHubScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    if (CustomerHubScreen.returnToCartAfterLogin && Supabase.instance.client.auth.currentUser != null) {
      _selectedIndex = 1;
      CustomerHubScreen.returnToCartAfterLogin = false;
    }
  }

  Future<void> _handleLogout() async {
    await PushNotificationService.clearTokenOnLogout();
    await Supabase.instance.client.auth.signOut();
    ref.read(cartProvider.notifier).clearCart();
    ref.invalidate(favoritesProvider);
    setState(() => _selectedIndex = 0);

    if (mounted) {
      context.go('/auth');
    }
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
    setState(() => _selectedIndex = index);
  }

  Widget _buildNavIndicator(int index, IconData outlineIcon, IconData solidIcon, String label, {int badgeCount = 0}) {
    bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _onNavigationItemTapped(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(horizontal: isSelected ? 20 : 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              label: Text('$badgeCount'),
              isLabelVisible: badgeCount > 0,
              child: Icon(isSelected ? solidIcon : outlineIcon,
                  color: isSelected ? AppTheme.primary : Colors.grey, size: 22),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
            ]
          ],
        ),
      ),
    );
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
        onProfileTap: _navigateToProfile,
        onLogout: _handleLogout,
      ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: pages,
          ),

          // Floating Cart Bar (Visible only on Home Tab when items exist)
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
                    gradient: const LinearGradient(colors: [AppTheme.textMain, Color(0xFF424242)]),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 6))],
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
                              Text('${cartState.itemCount} Items', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              Text('₹${cartState.foodTotal.toStringAsFixed(0)}',
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: const [
                          Text('View Cart', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom Navigation Dock
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 8))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildNavIndicator(0, Icons.cottage_outlined, Icons.cottage, 'Home'),
                    _buildNavIndicator(1, Icons.shopping_basket_outlined, Icons.shopping_basket, 'Cart',
                        badgeCount: cartState.itemCount),
                    _buildNavIndicator(2, Icons.receipt_long_outlined, Icons.receipt_long, 'Orders'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}