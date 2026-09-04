// lib/screens/customer_feed_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/helpers.dart';
import '../utils/customer_constants.dart';
import '../utils/dynamic_ui_engine.dart';
import '../utils/network.dart';
import '../providers/cart_provider.dart';
import '../providers/delivery_preference.dart';
import '../widgets/customer_ui_components.dart';
import '../widgets/app_widgets.dart';
import '../widgets/daily_streak_banner.dart';
import '../widgets/ai_recommendations_section.dart';
import '../services/delivery_estimator_service.dart';
import 'address_form_screen.dart';
import 'customer_bulk_request_screen.dart';

class CustomerFeedTab extends ConsumerStatefulWidget {
  final List<String> favoriteMeals;
  final Function(String) onToggleFavorite;
  final VoidCallback onProfileTap;
  final VoidCallback onLogout;

  const CustomerFeedTab({
    super.key,
    required this.favoriteMeals,
    required this.onToggleFavorite,
    required this.onProfileTap,
    required this.onLogout,
  });

  @override
  ConsumerState<CustomerFeedTab> createState() => _CustomerFeedTabState();
}

class _CustomerFeedTabState extends ConsumerState<CustomerFeedTab>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<Map<String, dynamic>>> _mealsStream;
  String _selectedCategory = 'All';
  String _currentAddress = 'Select Delivery Address';
  List<Map<String, dynamic>> _savedAddresses = [];
  bool _showFavoritesOnly = false;

  final TextEditingController _searchController = TextEditingController();
  bool _isAiSearching = false;
  bool _hasActiveSearch = false;
  List<Map<String, dynamic>> _aiSearchResults = [];
  final Map<String, Map<String, dynamic>> _chefKitchenPins = {};
  final Set<String> _chefPinsResolved = {};
  bool _hydratingChefPins = false;
  final Set<String> _closedChefIds = {};
  final Set<String> _chefOpenResolved = {};
  bool _hydratingKitchenHours = false;

  final List<Map<String, dynamic>> _categories = const [
    {'name': 'All', 'icon': Icons.set_meal_outlined},
    {'name': 'Maharashtrian', 'icon': Icons.kebab_dining_outlined},
    {'name': 'Punjabi', 'icon': Icons.ramen_dining_outlined},
    {'name': 'South Indian', 'icon': Icons.tapas_outlined},
    {'name': 'North Indian', 'icon': Icons.dinner_dining_outlined},
    {'name': 'Snacks', 'icon': Icons.fastfood_outlined},
    {'name': 'Desserts', 'icon': Icons.icecream_outlined},
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _mealsStream = Supabase.instance.client
        .from('meals')
        .stream(primaryKey: ['id'])
        .eq('status', 'Available');
    _fetchUserAddresses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _checkIfTimePassed(String? timeSlot) {
    if (timeSlot == null || timeSlot.isEmpty) return false;
    final slotLower = timeSlot.toLowerCase();

    if (slotLower.contains('daily')) return false;

    const weekDays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    bool isDaySpecific = weekDays.any((day) => slotLower.contains(day));
    if (isDaySpecific) return false;

    return isMealExpired(timeSlot);
  }

  Future<void> _performAiSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _hasActiveSearch = false;
        _aiSearchResults.clear();
      });
      return;
    }

    setState(() {
      _isAiSearching = true;
      _hasActiveSearch = true;
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'ai-search',
        body: {'prompt': trimmed},
      ).withTimeout(NetworkTimeouts.payment);

      List<Map<String, dynamic>> rawMeals = [];
      if (response.status == 200 && response.data != null && response.data['success'] == true) {
        rawMeals = List<Map<String, dynamic>>.from(response.data['meals']);
      }

      final localResponse = await Supabase.instance.client
          .from('meals')
          .select()
          .eq('status', 'Available')
          .withTimeout(NetworkTimeouts.standard);
      final localMeals = List<Map<String, dynamic>>.from(localResponse);
      final qClean = trimmed.toLowerCase().replaceAll(' ', '');

      final localMatches = localMeals.where((m) {
        final title = m['title']?.toString().toLowerCase().replaceAll(' ', '') ?? '';
        final desc = m['description']?.toString().toLowerCase().replaceAll(' ', '') ?? '';
        return title.contains(qClean) || desc.contains(qClean);
      }).toList();

      for (var lm in localMatches) {
        if (!rawMeals.any((rm) => rm['id'] == lm['id'])) {
          rawMeals.add(lm);
        }
      }

      final validMeals = rawMeals.where((m) {
        final status = m['status']?.toString().toLowerCase() ?? '';
        final isInventory = (m['customer_name'] == null || m['customer_name'].toString().isEmpty);
        return isInventory && status != 'paused' && status != 'cancelled';
      }).toList();

      if (mounted) {
        setState(() => _aiSearchResults = validMeals);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'AI Search Failure');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(networkErrorMessage(e)), backgroundColor: Colors.red),
        );
        setState(() {
          _hasActiveSearch = false;
          _aiSearchResults.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _isAiSearching = false);
    }
  }

  Future<void> _fetchUserAddresses() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // 🌟 FIX: Query user_addresses table directly instead of legacy users.addresses column
      final response = await Supabase.instance.client
          .from('user_addresses')
          .select()
          .eq('user_id', user.id)
          .withTimeout(NetworkTimeouts.standard);

      List<Map<String, dynamic>> normalized = uniqueSavedAddresses(
        (response as List).map((row) => Map<String, dynamic>.from(row as Map)),
      ).map((row) {
        return {
          ...row,
          'address': formatSavedAddress(row),
          'title': row['landmark'] ?? 'Saved Address',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _savedAddresses = normalized;
          if (_savedAddresses.isNotEmpty && (_currentAddress == 'Select Delivery Address' || _currentAddress.isEmpty)) {
            _currentAddress = _savedAddresses.first['address']?.toString() ?? 'Select Delivery Address';
          }
          final selected = _selectedAddressMap;
          if (selected != null) {
            ref.read(selectedDeliveryAddressProvider.notifier).setAddress(selected);
          }
        });
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch user addresses');
    }
  }

  Map<String, dynamic>? get _selectedAddressMap {
    for (final addr in _savedAddresses) {
      if (addr['address']?.toString() == _currentAddress) return addr;
    }
    return _savedAddresses.isEmpty ? null : _savedAddresses.first;
  }

  bool get _hasDeliveryPin {
    final dest = _selectedAddressMap;
    final lat = addressCoordinate(dest, latitude: true);
    final lng = addressCoordinate(dest, latitude: false);
    return lat != null && lng != null && lat != 0 && lng != 0;
  }

  Map<String, dynamic> _pinnedMeal(Map<String, dynamic> meal) {
    final chefId = meal['chef_id']?.toString();
    return mealWithKitchenPin(
      meal,
      chefPin: chefId == null ? null : _chefKitchenPins[chefId],
    );
  }

  Future<void> _hydrateChefKitchenPins(List<Map<String, dynamic>> meals) async {
    final missing = <String>{};
    for (final meal in meals) {
      if (hasKitchenPin(meal)) continue;
      final chefId = meal['chef_id']?.toString();
      if (chefId == null || chefId.isEmpty || _chefPinsResolved.contains(chefId)) continue;
      missing.add(chefId);
    }
    if (missing.isEmpty || _hydratingChefPins) return;
    _hydratingChefPins = true;
    try {
      final rows = await Supabase.instance.client
          .from('users')
          .select('id, lat, lng, latitude, longitude')
          .inFilter('id', missing.toList());
      var added = false;
      for (final row in rows) {
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        _chefPinsResolved.add(id);
        if (!hasKitchenPin(row)) continue;
        _chefKitchenPins[id] = Map<String, dynamic>.from(row);
        added = true;
      }
      _chefPinsResolved.addAll(missing);
      if (added && mounted) setState(() {});
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to hydrate chef kitchen pins');
    } finally {
      _hydratingChefPins = false;
    }
  }

  Future<void> _hydrateKitchenHours(List<Map<String, dynamic>> meals) async {
    final missing = <String>{};
    for (final meal in meals) {
      final chefId = meal['chef_id']?.toString();
      if (chefId == null || chefId.isEmpty || _chefOpenResolved.contains(chefId)) continue;
      missing.add(chefId);
    }
    if (missing.isEmpty || _hydratingKitchenHours) return;
    _hydratingKitchenHours = true;
    try {
      final rows = await Supabase.instance.client
          .from('chef_profiles')
          .select('user_id, is_open')
          .inFilter('user_id', missing.toList());
      var closedChanged = false;
      for (final row in rows) {
        final id = row['user_id']?.toString();
        if (id == null || id.isEmpty) continue;
        _chefOpenResolved.add(id);
        if (!isChefKitchenOpen(row)) {
          _closedChefIds.add(id);
          closedChanged = true;
        }
      }
      _chefOpenResolved.addAll(missing);
      if (closedChanged && mounted) setState(() {});
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to hydrate kitchen hours');
      _chefOpenResolved.addAll(missing);
    } finally {
      _hydratingKitchenHours = false;
    }
  }

  List<Map<String, dynamic>> _openKitchenMeals(List<Map<String, dynamic>> meals) {
    return meals.where((meal) {
      final chefId = meal['chef_id']?.toString();
      return chefId == null || chefId.isEmpty || !_closedChefIds.contains(chefId);
    }).toList();
  }

  List<Map<String, dynamic>> _mealsForSelectedAddress(List<Map<String, dynamic>> meals) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrateChefKitchenPins(meals);
      _hydrateKitchenHours(meals);
    });
    final pinned = _openKitchenMeals(meals.map(_pinnedMeal).toList());
    if (!_hasDeliveryPin) return pinned;
    final dest = _selectedAddressMap;
    final endLat = addressCoordinate(dest, latitude: true);
    final endLng = addressCoordinate(dest, latitude: false);
    if (endLat == null || endLng == null) return pinned;

    final inRange = <Map<String, dynamic>>[];
    final unknown = <Map<String, dynamic>>[];
    for (final meal in pinned) {
      final startLat = kitchenCoordinate(meal, latitude: true);
      final startLng = kitchenCoordinate(meal, latitude: false);
      if (startLat == null || startLng == null) {
        unknown.add(meal);
        continue;
      }
      final distance = DeliveryEstimatorService.calculateDistanceKm(
        startLat: startLat,
        startLng: startLng,
        endLat: endLat,
        endLng: endLng,
      );
      if (DeliveryEstimatorService.isWithinDeliveryRadius(distance)) {
        inRange.add(meal);
      }
    }
    return [...inRange, ...unknown];
  }

  String? _etaLabelForMeal(Map<String, dynamic> meal) {
    final dest = _selectedAddressMap;
    final pinned = _pinnedMeal(meal);
    final startLat = kitchenCoordinate(pinned, latitude: true);
    final startLng = kitchenCoordinate(pinned, latitude: false);
    final endLat = addressCoordinate(dest, latitude: true);
    final endLng = addressCoordinate(dest, latitude: false);
    if (startLat == null || startLng == null || endLat == null || endLng == null) return null;

    final distance = DeliveryEstimatorService.calculateDistanceKm(
      startLat: startLat,
      startLng: startLng,
      endLat: endLat,
      endLng: endLng,
    );
    if (distance <= 0) return null;
    if (!DeliveryEstimatorService.isWithinDeliveryRadius(distance)) {
      return 'Outside ${DeliveryEstimatorService.maxDeliveryRadiusKm.toInt()} km';
    }
    return '${DeliveryEstimatorService.estimateEtaMinutes(distance)} min';
  }

  void _handleAddToCart(Map<String, dynamic> meal) async {
    final cartNotifier = ref.read(cartProvider.notifier);
    final cartState = ref.read(cartProvider);

    final success = cartNotifier.addToCart(meal, 1, clearIfVendorConflict: false);

    if (!success && cartState.hasVendorConflict) {
      final shouldClear = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Multi-Chef Cart Notice', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text(
            'Your cart contains items from another kitchen. Would you like to clear your cart and add this dish instead?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: brandPrimary, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear & Add'),
            ),
          ],
        ),
      );

      if (shouldClear == true && mounted) {
        cartNotifier.addToCart(meal, 1, clearIfVendorConflict: true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cart updated with new kitchen item!'), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to Cart!'), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                  boxShadow: AppTheme.brandGlow(opacity: 0.28),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            if (!isLoggedIn) {
                              showAuthBottomSheet(context, () {
                                setState(() {});
                                _fetchUserAddresses();
                              });
                              return;
                            }

                            await _fetchUserAddresses();
                            if (!context.mounted) return;

                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (ctx) => Container(
                                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
                                decoration: AppTheme.bottomSheetDecoration(
                                  isDark: Theme.of(context).brightness == Brightness.dark,
                                ),
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text('Select delivery location',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(context))),
                                    const SizedBox(height: 16),
                                    if (_savedAddresses.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 16),
                                        child: Text('No saved addresses yet.', style: TextStyle(color: AppTheme.textMuted)),
                                      ),
                                    Flexible(
                                      child: SingleChildScrollView(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: _savedAddresses.map((addrMap) {
                                            final String addrStr = addrMap['address']?.toString() ?? '';
                                            bool isSelected = _currentAddress == addrStr;
                                            return Container(
                                              margin: const EdgeInsets.only(bottom: 12),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? AppTheme.primary.withValues(alpha: 0.08)
                                                    : AppTheme.surfaceOf(context),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                    color: isSelected ? AppTheme.primary : AppTheme.hairlineOf(context)),
                                              ),
                                              child: ListTile(
                                                dense: true,
                                                leading: Icon(Icons.location_on,
                                                    color: isSelected ? brandPrimary : Colors.grey),
                                                title: Text(
                                                  addrStr,
                                                  style: TextStyle(
                                                    color: isSelected ? AppTheme.primary : AppTheme.onSurfaceOf(context),
                                                    fontSize: 13,
                                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                  ),
                                                ),
                                                onTap: () {
                                                  setState(() => _currentAddress = addrStr);
                                                  ref.read(selectedDeliveryAddressProvider.notifier).setAddress(addrMap);
                                                  Navigator.pop(ctx);
                                                },
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      icon: const Icon(Icons.add_location_alt, color: brandPrimary),
                                      label: const Text('Add New Address',
                                          style: TextStyle(color: brandPrimary, fontWeight: FontWeight.bold)),
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const AddressFormScreen()),
                                        ).then((_) => _fetchUserAddresses());
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.asset('assets/app_icon.png', height: 20, width: 20)),
                                  const SizedBox(width: 8),
                                  const Text('Delivering to',
                                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on, color: Colors.white, size: 18),
                                  const SizedBox(width: 4),
                                  Container(
                                    constraints: const BoxConstraints(maxWidth: 160),
                                    child: Text(
                                      _currentAddress,
                                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 18),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            if (isLoggedIn) ...[
                              Container(
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                                child: IconButton(
                                  icon: Icon(_showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
                                      color: Colors.white, size: 20),
                                  onPressed: () {
                                    setState(() => _showFavoritesOnly = !_showFavoritesOnly);
                                    if (_showFavoritesOnly && widget.favoriteMeals.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('You have no favorite meals saved yet!'),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: widget.onProfileTap,
                                child: const CircleAvatar(
                                    backgroundColor: Colors.white,
                                    radius: 18,
                                    child: Icon(Icons.person, color: brandPrimary, size: 20)),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: widget.onLogout,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                                  child: const Icon(Icons.logout, color: Colors.white, size: 18),
                                ),
                              ),
                            ] else ...[
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: brandPrimary,
                                  elevation: 0,
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                onPressed: () => showAuthBottomSheet(context, () => setState(() {})),
                                child: const Text('Sign In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            ]
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -24,
                left: 20,
                right: 20,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceOf(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.hairlineOf(context)),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (val) => _performAiSearch(val),
                    decoration: InputDecoration(
                      hintText: 'What are you craving today?',
                      hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      suffixIcon: GestureDetector(
                        onTap: () => _performAiSearch(_searchController.text),
                        child: Container(
                          margin: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 48),

          if (_hasDeliveryPin)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Showing kitchens within ${DeliveryEstimatorService.maxDeliveryRadiusKm.toInt()} km of your pin. Offline kitchens are hidden.',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            )
          else if (isLoggedIn)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Drop a map pin on your delivery address to hide kitchens outside ${DeliveryEstimatorService.maxDeliveryRadiusKm.toInt()} km.',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ),

          if (isLoggedIn) const DailyStreakBanner(),
          if (isLoggedIn && !_hasActiveSearch) const AiRecommendationsSection(),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: GradientButton(
              label: 'Broadcast bulk / catering request',
              icon: Icons.campaign_outlined,
              height: 50,
              onPressed: () {
                if (!isLoggedIn) {
                  showAuthBottomSheet(context, () => setState(() {}));
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CustomerBulkRequestScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          if (!_hasActiveSearch) ...[
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = _selectedCategory == cat['name'];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat['name']),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primary : AppTheme.surfaceOf(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.hairlineOf(context)),
                        boxShadow: isSelected ? AppTheme.brandGlow(opacity: 0.28) : const [],
                      ),
                      child: Row(
                        children: [
                          Icon(cat['icon'], color: isSelected ? Colors.white : AppTheme.textMuted, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            cat['name'],
                            style: TextStyle(
                              color: isSelected ? Colors.white : AppTheme.onSurfaceOf(context),
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            const DynamicUIEngine(screenName: 'customer_feed'),
            const SizedBox(height: 12),
          ],

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hasActiveSearch
                          ? 'Search results'
                          : (_showFavoritesOnly ? 'Your favorites' : 'Fresh from the kitchen'),
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.onSurfaceOf(context)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _hasActiveSearch
                          ? '"${_searchController.text}"'
                          : (_showFavoritesOnly ? 'Meals you loved' : 'Support your local home chefs'),
                      style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                if (_hasActiveSearch)
                  TextButton.icon(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _hasActiveSearch = false;
                        _aiSearchResults.clear();
                      });
                    },
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    label: const Text('Clear', style: TextStyle(color: Colors.red)),
                  )
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_isAiSearching)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary),
                    SizedBox(height: 16),
                    Text('Scanning menus...', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            )
          else if (_hasActiveSearch)
            _buildMealGrid(_mealsForSelectedAddress(_showFavoritesOnly
                ? _aiSearchResults.where((m) => widget.favoriteMeals.contains(m['id'].toString())).toList()
                : _aiSearchResults))
          else
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _mealsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const MealListSkeleton(count: 4);
                }
                if (snapshot.hasError) {
                  return EmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: 'Trouble reaching the kitchen',
                    message: 'We couldn\'t load fresh meals right now. Please check your connection and try again.',
                    actionLabel: 'Retry',
                    onAction: () => setState(() {}),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const EmptyState(
                    icon: Icons.restaurant_menu_rounded,
                    title: 'No meals published yet',
                    message: 'Our home chefs are prepping something delicious. Check back soon!',
                  );
                }

                var meals = snapshot.data!.where((m) {
                  final status = m['status']?.toString().toLowerCase() ?? '';
                  final isInventory = (m['customer_name'] == null || m['customer_name'].toString().isEmpty);
                  return isInventory && status != 'paused' && status != 'cancelled';
                }).toList();

                if (_selectedCategory != 'All') {
                  meals = meals
                      .where((m) => m['category']?.toString().toLowerCase() == _selectedCategory.toLowerCase())
                      .toList();
                }

                if (_showFavoritesOnly) {
                  meals = meals.where((m) => widget.favoriteMeals.contains(m['id'].toString())).toList();
                }

                meals = _mealsForSelectedAddress(meals);
                return _buildMealGrid(meals);
              },
            )
        ],
      ),
    );
  }

  Widget _buildMealGrid(List<Map<String, dynamic>> meals) {
    if (meals.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No meals found',
        message: _hasDeliveryPin
            ? 'No kitchens are delivering to this pin right now. Try another address or category.'
            : 'Try a different category or search for something else.',
      );
    }

    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;

    meals.sort((a, b) {
      final aAvailable = !_checkIfTimePassed(a['time_slot']?.toString()) &&
          (int.tryParse(a['quantity'].toString()) ?? 0) > 0 &&
          a['status']?.toString().toLowerCase() != 'sold out';
      final bAvailable = !_checkIfTimePassed(b['time_slot']?.toString()) &&
          (int.tryParse(b['quantity'].toString()) ?? 0) > 0 &&
          b['status']?.toString().toLowerCase() != 'sold out';
      if (aAvailable && !bAvailable) return -1;
      if (!aAvailable && bAvailable) return 1;
      return 0;
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        int columns = constraints.maxWidth > 1000 ? 4 : constraints.maxWidth > 600 ? 3 : 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 342,
          ),
          itemCount: meals.length,
          itemBuilder: (context, index) {
            final meal = meals[index];
            final isFavorite = widget.favoriteMeals.contains(meal['id'].toString());

            final isExpired = _checkIfTimePassed(meal['time_slot']?.toString());
            final availableQty = int.tryParse(meal['quantity'].toString()) ?? 0;
            final isSoldOut = availableQty <= 0 || meal['status']?.toString().toLowerCase() == 'sold out';
            final isAvailable = !isExpired && !isSoldOut;
            String overlayText = isSoldOut ? 'SOLD OUT' : (isExpired ? 'TIME PASSED' : '');

            final cartState = ref.watch(cartProvider);
            final hasOffer = cartState.isOfferActive(meal);
            final etaLabel = _etaLabelForMeal(meal);

            return GestureDetector(
              onTap: () => showMealDetailsDialog(context, meal, ref),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: AppTheme.radiusLg,
                  boxShadow: AppTheme.softShadow,
                ),
                child: Stack(
                  children: [
                    Positioned(
                      bottom: -20,
                      right: -20,
                      child: Opacity(
                        opacity: 0.08,
                        child: Image.asset('assets/app_icon.png', width: 140, height: 140, fit: BoxFit.contain),
                      ),
                    ),
                    Opacity(
                      opacity: isAvailable ? 1.0 : 0.6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.rLg)),
                                child: Container(
                                  height: 130,
                                  width: double.infinity,
                                  color: Colors.grey.shade200,
                                  child: meal['image_url'] != null
                                      ? Hero(
                                          tag: 'meal-image-${meal['id']}',
                                          child: CachedNetworkImage(
                                            imageUrl: meal['image_url'].toString(),
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                            placeholder: (_, _) => const AppShimmer(
                                              child: ShimmerBox(
                                                width: double.infinity,
                                                height: 130,
                                                borderRadius: BorderRadius.zero,
                                              ),
                                            ),
                                            errorWidget: (_, _, _) =>
                                                const Icon(Icons.restaurant, color: Colors.grey, size: 40),
                                          ),
                                        )
                                      : const Icon(Icons.restaurant, color: Colors.grey, size: 40),
                                ),
                              ),
                              // Subtle gradient scrim for legibility of top badges
                              Positioned.fill(
                                bottom: null,
                                child: Container(
                                  height: 56,
                                  decoration: const BoxDecoration(
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rLg)),
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Color(0x55000000), Colors.transparent],
                                    ),
                                  ),
                                ),
                              ),
                              if (!isAvailable)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                                    ),
                                    child: Center(
                                      child: Text(
                                        overlayText,
                                        style: const TextStyle(
                                            color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                                      ),
                                    ),
                                  ),
                                ),
                              if (hasOffer)
                                Positioned(
                                  top: 12,
                                  left: 45,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: Colors.red.shade600, borderRadius: BorderRadius.circular(6)),
                                    child: Text(
                                      meal['offer_type'].toString().toUpperCase(),
                                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: GestureDetector(
                                  onTap: () {
                                    if (!isLoggedIn) {
                                      showAuthBottomSheet(context, () => setState(() {}));
                                      return;
                                    }
                                    widget.onToggleFavorite(meal['id'].toString());
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle),
                                    child: Icon(
                                      isFavorite ? Icons.favorite : Icons.favorite_border,
                                      color: brandPrimary,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 12,
                                left: 12,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(4)),
                                  child: Icon(
                                    Icons.circle,
                                    color: meal['is_veg'] == true ? Colors.green : Colors.red,
                                    size: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  meal['title'] ?? 'Home Meal',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.onSurfaceOf(context)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () {
                                    showChefProfileDialog(
                                      context,
                                      meal['chef_id']?.toString() ?? '',
                                      chefDisplayName(meal),
                                      meal['fssai_number']?.toString() ?? '',
                                    );
                                  },
                                  child: Row(
                                    children: [
                                      const Icon(Icons.person, size: 12, color: textMuted),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          chefDisplayName(meal),
                                          style: const TextStyle(
                                            color: brandPrimary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            decoration: TextDecoration.underline,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      MealRatingBadge(meal: meal),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time, size: 12, color: textMuted),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        meal['time_slot'] ?? 'ASAP',
                                        style: TextStyle(color: isExpired ? Colors.red : textMuted, fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (etaLabel != null) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        etaLabel,
                                        style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.delivery_dining, size: 12, color: textMuted),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        meal['service_type']?.toString() ?? 'Delivery',
                                        style: const TextStyle(color: textMuted, fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '₹${(double.tryParse(meal['price']?.toString() ?? '0') ?? 0).toInt()}',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.onSurfaceOf(context)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (isAvailable)
                                            Text(
                                              '$availableQty left',
                                              style: const TextStyle(
                                                  color: brandPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Share dish',
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(Icons.share_outlined, size: 18, color: AppTheme.onSurfaceOf(context)),
                                      onPressed: () => SharePlus.instance.share(ShareParams(text: mealShareText(meal))),
                                    ),
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: isAvailable ? () => _handleAddToCart(meal) : null,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                          decoration: BoxDecoration(
                                            gradient: isAvailable ? AppTheme.primaryGradient : null,
                                            color: isAvailable ? null : Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(12),
                                            boxShadow: isAvailable ? AppTheme.brandGlow(opacity: 0.25) : null,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(isAvailable ? Icons.add_rounded : Icons.lock_clock,
                                                  size: 15, color: isAvailable ? Colors.white : Colors.grey),
                                              const SizedBox(width: 4),
                                              Text(
                                                isAvailable ? 'Add' : 'Closed',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: isAvailable ? Colors.white : Colors.grey),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ).entrance(index: index);
          },
        );
      },
    );
  }
}