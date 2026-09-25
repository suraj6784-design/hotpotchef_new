// lib/screens/customer_feed_tab.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../utils/app_page.dart';
import '../utils/helpers.dart';
import '../utils/customer_constants.dart';
import '../utils/network.dart';
import '../utils/pinned_address.dart';
import '../utils/pricing_calculator.dart';
import '../utils/meal_nutrition.dart';
import '../providers/cart_provider.dart';
import '../providers/delivery_preference.dart';
import '../providers/kitchen_follows_provider.dart';
import '../widgets/customer_ui_components.dart';
import '../widgets/app_widgets.dart';
import '../widgets/support_replied_banner.dart';
import '../widgets/live_offers_flash_banner.dart';
import '../services/app_analytics.dart';
import '../services/delivery_estimator_service.dart';
import '../services/meal_catalog_repository.dart';
import '../utils/delivery_fee.dart';
import '../utils/service_area.dart';
import '../utils/diner_locale.dart';
import '../utils/fssai_certificate_scan.dart';
import '../screens/checkout_screen.dart';
import '../widgets/diner_storefront.dart';
import 'address_form_screen.dart';

class CustomerFeedTab extends ConsumerStatefulWidget {
  final List<String> favoriteMeals;
  final Function(String) onToggleFavorite;
  final VoidCallback onProfileTap;
  final VoidCallback onLogout;
  final VoidCallback? onGoToCart;
  final VoidCallback? onReorderToOrders;
  final int homeResetToken;

  const CustomerFeedTab({
    super.key,
    required this.favoriteMeals,
    required this.onToggleFavorite,
    required this.onProfileTap,
    required this.onLogout,
    this.onGoToCart,
    this.onReorderToOrders,
    this.homeResetToken = 0,
  });

  @override
  ConsumerState<CustomerFeedTab> createState() => _CustomerFeedTabState();
}

class _CustomerFeedTabState extends ConsumerState<CustomerFeedTab>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  List<Map<String, dynamic>>? _mealsRestSnapshot;
  bool _loadingMealsRest = false;
  String _selectedCategory = 'All';
  String _selectedDiet = 'All';
  String _selectedSort = kFeedSortEta;
  String _homeMode = 'live';
  String _currentAddress = 'Locating...';
  List<Map<String, dynamic>> _savedAddresses = [];
  /// GPS pin used for guests (and signed-in users without a saved map pin).
  /// Kept across login so the feed radius does not jump after Sign In.
  Map<String, dynamic>? _deviceLocationPin;
  bool _resolvingDeviceLocation = false;
  String _allergies = '';
  bool _showFavoritesOnly = false;
  bool _showFollowingOnly = false;

  final TextEditingController _searchController = TextEditingController();
  bool _isAiSearching = false;
  bool _hasActiveSearch = false;
  List<Map<String, dynamic>> _aiSearchResults = [];
  List<Map<String, dynamic>> _chefSearchResults = [];
  String? _filteredChefId;
  String? _filteredChefName;
  String? _offerBrowseLabel;
  String? _offerBrowseGroupKey;
  final Map<String, Map<String, dynamic>> _chefKitchenPins = {};
  final Set<String> _chefPinsResolved = {};
  bool _hydratingChefPins = false;
  final Map<String, ChefRatingSummary> _chefRatings = {};
  bool _hydratingRatings = false;
  final Set<String> _closedChefIds = {};
  final Set<String> _chefOpenResolved = {};
  final Map<String, Map<String, dynamic>> _chefKitchenProfiles = {};
  final Map<String, Map<String, dynamic>> _chefTrust = {};
  final Set<String> _chefTrustResolved = {};
  bool _hydratingChefTrust = false;
  bool _hydratingKitchenHours = false;
  StreamSubscription<AuthState>? _authSub;
  List<Map<String, dynamic>> _olderMeals = [];
  bool _loadingOlderMeals = false;
  bool _olderMealsExhausted = false;
  bool _addressPickerOpen = false;
  final ScrollController _feedScrollController = ScrollController();

  final List<Map<String, dynamic>> _dietFilters = const [
    {'name': 'All', 'icon': Icons.tune},
    {'name': 'Veg', 'icon': Icons.eco_outlined},
    {'name': 'Vegan', 'icon': Icons.spa_outlined},
    {'name': 'Jain', 'icon': Icons.filter_vintage_outlined},
    {'name': 'High-protein', 'icon': Icons.fitness_center_outlined},
    {'name': 'Millet', 'icon': Icons.grain},
    {'name': 'Diabetic', 'icon': Icons.monitor_heart_outlined},
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshMealsRestSnapshot());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (mounted) unawaited(_bootstrapDeliveryPin());
      });
    });
    _fetchDietaryPrefs();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      unawaited(_refreshMealsRestSnapshot());
      if (data.session == null) {
        setState(_resetGuestFeedState);
        _captureDeviceLocation();
      } else {
        // Keep the active GPS pin so kitchens stay in the same radius after Sign In.
        _fetchUserAddresses(preserveActivePin: true);
        _fetchDietaryPrefs();
      }
    });
  }

  @override
  void didUpdateWidget(covariant CustomerFeedTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.homeResetToken != oldWidget.homeResetToken) {
      _clearHomeSearch();
      unawaited(_refreshMealsRestSnapshot());
    }
  }

  Future<List<Map<String, dynamic>>> _fetchMealsCatalog({String? chefId}) {
    return MealCatalogRepository().availableMeals(chefId: chefId);
  }

  Future<List<Map<String, dynamic>>> _fetchHomeMealCatalog() => _fetchMealsCatalog();

  void _scrollFeedHome() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _feedScrollController;
      if (!controller.hasClients) return;
      try {
        final position = controller.position;
        if (!position.hasPixels || !position.hasContentDimensions) return;
        if (position.pixels <= position.minScrollExtent) return;
        controller.jumpTo(position.minScrollExtent);
      } catch (_) {}
    });
  }

  Future<void> _refreshMealsRestSnapshot() async {
    if (_loadingMealsRest) return;
    _loadingMealsRest = true;
    try {
      final rows = await _fetchHomeMealCatalog();
      if (!mounted) return;
      setState(() {
        _mealsRestSnapshot = rows;
        _loadingMealsRest = false;
      });
      unawaited(AppAnalytics.logCatalogLoad(
        success: true,
        count: rows.length,
        signedIn: Supabase.instance.client.auth.currentUser != null,
      ));
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Home meals REST fallback failed');
      unawaited(AppAnalytics.logCatalogLoad(
        success: false,
        count: 0,
        signedIn: Supabase.instance.client.auth.currentUser != null,
      ));
      if (mounted) setState(() => _loadingMealsRest = false);
    }
  }

  void _retryMealsFeed() {
    _loadingMealsRest = false;
    unawaited(_refreshMealsRestSnapshot());
    setState(() {});
  }

  Future<void> _bootstrapDeliveryPin() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await _fetchUserAddresses(preserveActivePin: false);
      if (_hasDeliveryPin && _deviceLocationPin?['is_launch_city'] != true) return;
    }
    await _captureDeviceLocation();
    if (!_hasDeliveryPin || _deviceLocationPin?['is_launch_city'] == true) {
      if (_deviceLocationPin?['is_device_location'] == true) return;
      if (!_hasDeliveryPin) {
        _applyDeliveryPin(launchCityDefaultPin(), preferOverSaved: false);
      }
    }
  }

  void _resetGuestFeedState() {
    _showFavoritesOnly = false;
    _showFollowingOnly = false;
    _allergies = '';
    _selectedDiet = 'All';
    _selectedCategory = 'All';
    _savedAddresses = [];
    _deviceLocationPin = null;
    _currentAddress = 'Locating...';
    ref.read(selectedDeliveryAddressProvider.notifier).setAddress(null);
  }

  bool get _isUsingDevicePin {
    final pin = _deviceLocationPin;
    if (pin == null) return false;
    return _currentAddress == (pin['address']?.toString() ?? '');
  }

  Future<void> _captureDeviceLocation({bool notifyOnFailure = false}) async {
    if (_resolvingDeviceLocation) return;
    _resolvingDeviceLocation = true;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _applyDeviceLocationFallback(
          message: notifyOnFailure ? 'Turn on location to see kitchens near you.' : null,
          silent: !notifyOnFailure,
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      // Do not auto-prompt on Home boot — the permission sheet can leave Android
      // with a zero-size Flutter surface (white screen) on diner.
      if (permission == LocationPermission.denied) {
        if (!notifyOnFailure) {
          _applyDeviceLocationFallback(silent: true);
          return;
        }
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _applyDeviceLocationFallback(
          message: notifyOnFailure
              ? 'Allow location access so guest browsing matches kitchens after Sign In.'
              : null,
          silent: !notifyOnFailure,
        );
        return;
      }

      Position position;
      try {
        if (notifyOnFailure) {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
          ).timeout(const Duration(seconds: 12));
        } else {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null && last.latitude != 0 && last.longitude != 0) {
            position = last;
          } else {
            position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
            ).timeout(const Duration(seconds: 8));
          }
        }
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        if (last == null || (last.latitude == 0 && last.longitude == 0)) {
          _applyDeviceLocationFallback(
            message: 'Turn on location or drop a pin to see kitchens near you.',
            silent: !notifyOnFailure,
          );
          return;
        }
        position = last;
      }

      String label = 'Near you';
      String city = '';
      String state = '';
      String pincode = '';
      String street = '';
      try {
        final parts = await reverseGeocodeLatLng(position.latitude, position.longitude);
        city = parts.city;
        state = parts.state;
        pincode = parts.pincode;
        street = parts.street;
        final localityLabel = formatLocalityPinLabel(
          street: parts.street,
          city: parts.city,
          pincode: parts.pincode,
          formatted: parts.formatted,
        );
        if (localityLabel.isNotEmpty) {
          label = localityLabel;
        } else if (city.isNotEmpty && pincode.isNotEmpty) {
          label = '$city - $pincode';
        } else if (city.isNotEmpty) {
          label = city;
        }
      } catch (_) {
        // Keep "Near you" if reverse geocode fails; coords still filter meals.
      }

      final pin = <String, dynamic>{
        'id': 'device-location',
        'title': 'Current location',
        'landmark': 'Current location',
        'address': label,
        'street': street,
        'city': city,
        'state': state,
        'pincode': pincode,
        'postal_code': pincode,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'lat': position.latitude,
        'lng': position.longitude,
        'is_device_location': true,
      };

      if (!mounted) return;
      _applyDeliveryPin(pin, preferOverSaved: false);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Guest delivery location capture failed');
      _applyDeviceLocationFallback(
        message: notifyOnFailure ? 'Could not read your location. Try again.' : null,
        silent: !notifyOnFailure,
      );
    } finally {
      _resolvingDeviceLocation = false;
    }
  }

  void _applyDeliveryPin(Map<String, dynamic> pin, {required bool preferOverSaved}) {
    if (!mounted) return;
    setState(() {
      _deviceLocationPin = pin;
      final keepSavedSelection = !preferOverSaved &&
          _savedAddresses.any((addr) => addr['address']?.toString() == _currentAddress);
      if (!keepSavedSelection) {
        _currentAddress = pin['address']?.toString() ?? 'Near you';
        ref.read(selectedDeliveryAddressProvider.notifier).setAddress(pin);
      }
    });
  }

  void _applyDeviceLocationFallback({String? message, bool silent = false}) {
    if (_deviceLocationPin?['is_device_location'] == true) {
      if (silent) return;
    } else {
      _applyDeliveryPin(launchCityDefaultPin(), preferOverSaved: false);
    }
    if (silent) return;
    final text = message ?? 'Showing ${kLaunchCities.first.label} kitchens. Tap the pin to use current location.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.orange),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _searchController.dispose();
    _feedScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  bool _checkIfTimePassed(Map<String, dynamic> meal) {
    return !isMealAvailableForCart(meal);
  }

  Future<void> _performAiSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _hasActiveSearch = false;
        _aiSearchResults.clear();
        _chefSearchResults.clear();
        _filteredChefId = null;
        _filteredChefName = null;
        _offerBrowseLabel = null;
      _offerBrowseGroupKey = null;
      });
      _scrollFeedHome();
      return;
    }

    setState(() {
      _isAiSearching = true;
      _hasActiveSearch = true;
      _filteredChefId = null;
      _filteredChefName = null;
      _offerBrowseLabel = null;
      _offerBrowseGroupKey = null;
    });

    try {
      final client = Supabase.instance.client;
      List<Map<String, dynamic>> rawMeals = [];
      if (client.auth.currentUser != null) {
        try {
          final response = await client.functions.invoke(
            'ai-search',
            body: {'prompt': trimmed},
          ).withTimeout(NetworkTimeouts.payment);
          if (response.status == 200 &&
              response.data != null &&
              response.data['success'] == true &&
              response.data['meals'] is List) {
            rawMeals = List<Map<String, dynamic>>.from(response.data['meals'] as List);
          }
        } catch (e, stack) {
          FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Home AI search skipped');
        }
      }

      final localMeals = await MealCatalogRepository(client).availableMeals();
      final qClean = trimmed.toLowerCase().replaceAll(' ', '');
      final qLower = trimmed.toLowerCase();

      final localMatches = localMeals.where((m) {
        if (!isMealAvailableForCart(m)) return false;
        final title = m['title']?.toString().toLowerCase().replaceAll(' ', '') ?? '';
        final desc = m['description']?.toString().toLowerCase().replaceAll(' ', '') ?? '';
        if (title.contains(qClean) || desc.contains(qClean)) return true;
        return mealChefLabelMatchesQuery(trimmed, m);
      }).toList();

      for (var lm in localMatches) {
        if (!rawMeals.any((rm) => rm['id'] == lm['id'])) {
          rawMeals.add(lm);
        }
      }

      // Chef / kitchen name search (users + local kitchen labels).
      final chefHits = <String, Map<String, dynamic>>{};
      try {
        final chefRows = await client
            .from('users')
            .select('id, name, full_name, email, fssai_number, role')
            .inFilter('role', kStoredChefRoles)
            .limit(250)
            .withTimeout(NetworkTimeouts.standard);
        for (final row in List<Map<String, dynamic>>.from(chefRows as List)) {
          if (!isChefAccount(row) || !chefNameMatchesQuery(trimmed, row)) continue;
          final id = row['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          chefHits[id] = row;
        }
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chef name search failed');
      }

      try {
        final kitchenRows = await client
            .from('chef_profiles')
            .select('user_id, local_kitchen_name')
            .ilike('local_kitchen_name', '%$trimmed%')
            .limit(24)
            .withTimeout(NetworkTimeouts.standard);
        final kitchenIds = <String>[];
        final kitchenLabels = <String, String>{};
        for (final row in List<Map<String, dynamic>>.from(kitchenRows as List)) {
          final id = row['user_id']?.toString() ?? '';
          if (id.isEmpty) continue;
          kitchenIds.add(id);
          kitchenLabels[id] = row['local_kitchen_name']?.toString() ?? '';
        }
        if (kitchenIds.isNotEmpty) {
          final extraChefs = await client
              .from('users')
              .select('id, name, full_name, email, fssai_number, role')
              .inFilter('id', kitchenIds)
              .inFilter('role', kStoredChefRoles)
              .withTimeout(NetworkTimeouts.standard);
          for (final row in List<Map<String, dynamic>>.from(extraChefs as List)) {
            if (!isChefAccount(row)) continue;
            final id = row['id']?.toString() ?? '';
            if (id.isEmpty) continue;
            final merged = Map<String, dynamic>.from(row);
            merged['local_kitchen_name'] = kitchenLabels[id];
            chefHits[id] = {...?chefHits[id], ...merged};
          }
        }
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Kitchen name search failed');
      }

      // Meal labels can match a diner's name. Only keep rows whose users.role is chef.
      final unverifiedMealChefIds = <String>{};
      for (final meal in localMeals) {
        if (!mealChefLabelMatchesQuery(trimmed, meal)) continue;
        final id = meal['chef_id']?.toString() ?? '';
        if (id.isEmpty || chefHits.containsKey(id)) continue;
        unverifiedMealChefIds.add(id);
      }
      if (unverifiedMealChefIds.isNotEmpty) {
        try {
          final verified = await client
              .from('users')
              .select('id, name, full_name, email, fssai_number, role')
              .inFilter('id', unverifiedMealChefIds.toList())
              .inFilter('role', kStoredChefRoles)
              .withTimeout(NetworkTimeouts.standard);
          for (final row in List<Map<String, dynamic>>.from(verified as List)) {
            if (!isChefAccount(row)) continue;
            final id = row['id']?.toString() ?? '';
            if (id.isEmpty) continue;
            chefHits[id] = row;
          }
        } catch (e, stack) {
          FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Meal chef role verify failed');
        }
      }

      if (chefHits.isNotEmpty) {
        final chefMealMatches = localMeals.where((m) {
          final id = m['chef_id']?.toString() ?? '';
          return id.isNotEmpty && chefHits.containsKey(id);
        }).toList();
        for (final meal in chefMealMatches) {
          if (!rawMeals.any((rm) => rm['id'] == meal['id'])) {
            rawMeals.add(meal);
          }
        }
      }

      final validMeals = rawMeals.where((m) {
        final status = m['status']?.toString().toLowerCase() ?? '';
        final isInventory = (m['customer_name'] == null || m['customer_name'].toString().isEmpty);
        return isInventory && status != 'paused' && status != 'cancelled';
      }).toList();

      final rankedChefs = chefHits.values.where(isChefAccount).toList()
        ..sort((a, b) {
          final an = chefDisplayName(a).toLowerCase();
          final bn = chefDisplayName(b).toLowerCase();
          final aExact = an == qLower || an.startsWith(qLower);
          final bExact = bn == qLower || bn.startsWith(qLower);
          if (aExact != bExact) return aExact ? -1 : 1;
          return an.compareTo(bn);
        });

      if (mounted) {
        setState(() {
          _aiSearchResults = validMeals;
          _chefSearchResults = rankedChefs.take(12).toList();
        });
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
          _chefSearchResults.clear();
          _filteredChefId = null;
          _filteredChefName = null;
          _offerBrowseLabel = null;
      _offerBrowseGroupKey = null;
        });
      }
    } finally {
      if (mounted) setState(() => _isAiSearching = false);
    }
  }

  Future<void> _filterFeedToChef(Map<String, dynamic> chef) async {
    final id = chef['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final name = chefDisplayName(chef);
    final local = (_mealsRestSnapshot ?? [])
        .where((m) => m['chef_id']?.toString() == id)
        .toList();
    setState(() {
      _isAiSearching = local.isEmpty;
      _hasActiveSearch = true;
      _filteredChefId = id;
      _filteredChefName = name;
      _offerBrowseLabel = null;
      _offerBrowseGroupKey = null;
      _searchController.text = name;
      _aiSearchResults = local;
      final others = _chefSearchResults.where((c) => c['id']?.toString() != id).toList();
      _chefSearchResults = [chef, ...others];
    });
    _scrollFeedHome();
    try {
      var meals = (await _fetchMealsCatalog(chefId: id)).where((m) {
        final status = m['status']?.toString().toLowerCase() ?? '';
        final isInventory = (m['customer_name'] == null || m['customer_name'].toString().isEmpty);
        return isInventory && status != 'paused' && status != 'cancelled';
      }).toList();
      if (meals.isEmpty) meals = local;
      if (!mounted) return;
      setState(() => _aiSearchResults = meals);
      _scrollFeedHome();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Filter feed to chef failed');
      if (!mounted) return;
      setState(() => _aiSearchResults = local);
      _scrollFeedHome();
    } finally {
      if (mounted) setState(() => _isAiSearching = false);
    }
  }

  void _clearHomeSearch() {
    _searchController.clear();
    setState(() {
      _hasActiveSearch = false;
      _aiSearchResults.clear();
      _chefSearchResults.clear();
      _filteredChefId = null;
      _filteredChefName = null;
      _offerBrowseLabel = null;
      _offerBrowseGroupKey = null;
    });
    _scrollFeedHome();
    if (_mealsRestSnapshot == null || _mealsRestSnapshot!.isEmpty) {
      unawaited(_refreshMealsRestSnapshot());
    }
  }

  Future<void> _showGroupedOfferMeals(String groupKey) async {
    final label = offerFlashGroupLabel(groupKey);
    setState(() {
      _isAiSearching = true;
      _hasActiveSearch = true;
      _filteredChefId = null;
      _filteredChefName = null;
      _chefSearchResults.clear();
      _offerBrowseLabel = label;
      _offerBrowseGroupKey = groupKey;
      _searchController.clear();
    });
    try {
      final destLat = addressCoordinate(_selectedAddressMap, latitude: true);
      final destLng = addressCoordinate(_selectedAddressMap, latitude: false);
      final meals = <Map<String, dynamic>>[];
      for (final raw in await _fetchMealsCatalog()) {
        if (offerFlashGroupKeyForMeal(raw) != groupKey) continue;
        if (!mealHasFlashableOffer(raw)) continue;
        final chefId = raw['chef_id']?.toString() ?? '';
        if (chefId.isNotEmpty && _closedChefIds.contains(chefId)) continue;
        final pinned = mealWithKitchenPin(raw, chefPin: _chefKitchenPins[chefId]);
        if (!mealInDeliveryRadius(
          pinned,
          destinationLat: destLat,
          destinationLng: destLng,
        )) {
          continue;
        }
        meals.add(pinned);
      }
      meals.sort((a, b) {
        final aBoosted = isMealBoosted(a);
        final bBoosted = isMealBoosted(b);
        if (aBoosted != bBoosted) return aBoosted ? -1 : 1;
        return mealDisplayTitle(a).compareTo(mealDisplayTitle(b));
      });
      if (!mounted) return;
      setState(() => _aiSearchResults = meals);
      _scrollFeedHome();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: '$label offer browse failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(networkErrorMessage(e)), backgroundColor: Colors.red),
      );
      _clearHomeSearch();
    } finally {
      if (mounted) setState(() => _isAiSearching = false);
    }
  }

  void _onHomeOfferTap(Map<String, dynamic> meal) {
    final grouped = offerFlashGroupKey(meal) ?? offerFlashGroupKeyForMeal(meal);
    final count = int.tryParse(meal['_offer_group_count']?.toString() ?? meal['_bogo_count']?.toString() ?? '') ?? 0;
    if (grouped != null && count != 1) {
      _showGroupedOfferMeals(grouped);
      return;
    }
    showMealDetailsDialog(context, meal, ref, onGoToCart: widget.onGoToCart);
  }

  Future<void> _fetchUserAddresses({bool preserveActivePin = false}) async {
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
          final keepDevicePin = preserveActivePin && _isUsingDevicePin && _hasDeliveryPin;
          if (!keepDevicePin &&
              _savedAddresses.isNotEmpty &&
              (_currentAddress == 'Select Delivery Address' ||
                  _currentAddress == 'Locating...' ||
                  _currentAddress.isEmpty ||
                  (!_isUsingDevicePin &&
                      !_savedAddresses.any((a) => a['address']?.toString() == _currentAddress)))) {
            final preferred = preferredCheckoutAddress(_savedAddresses);
            final label = preferred?['address']?.toString() ?? formatSavedAddress(preferred);
            if (label.isNotEmpty) {
              _currentAddress = label;
            }
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
    if (_deviceLocationPin != null &&
        _deviceLocationPin!['address']?.toString() == _currentAddress) {
      return _deviceLocationPin;
    }
    final preferred = preferredCheckoutAddress(_savedAddresses);
    if (preferred != null &&
        addressCoordinate(preferred, latitude: true) != null &&
        addressCoordinate(preferred, latitude: false) != null) {
      return preferred;
    }
    return _deviceLocationPin ?? preferred;
  }

  Future<void> _fetchDietaryPrefs() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final row = await Supabase.instance.client
          .from('users')
          .select('dietary_preference, allergies')
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() {
        _allergies = row['allergies']?.toString() ?? '';
        _selectedDiet = feedDietChipFromPreference(row['dietary_preference']?.toString());
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch dietary preferences');
    }
  }

  bool get _hasDeliveryPin {
    final dest = _selectedAddressMap;
    final lat = addressCoordinate(dest, latitude: true);
    final lng = addressCoordinate(dest, latitude: false);
    return lat != null && lng != null && lat != 0 && lng != 0;
  }

  bool get _outOfServiceArea {
    if (!_hasDeliveryPin) return false;
    final dest = _selectedAddressMap;
    return !isInLaunchServiceArea(
      pincode: dest?['postal_code']?.toString() ?? dest?['pincode']?.toString(),
      lat: addressCoordinate(dest, latitude: true),
      lng: addressCoordinate(dest, latitude: false),
    );
  }

  Future<void> _loadOlderMeals() async {
    if (_loadingOlderMeals || _olderMealsExhausted) return;
    setState(() => _loadingOlderMeals = true);
    try {
      final from = kHomeMealStreamLimit + _olderMeals.length;
      final to = from + kHomeMealPageSize - 1;
      final extra = await MealCatalogRepository().availableMealsPage(from: from, to: to);
      if (!mounted) return;
      setState(() {
        _olderMeals = [..._olderMeals, ...extra];
        _olderMealsExhausted = extra.length < kHomeMealPageSize;
        _loadingOlderMeals = false;
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Home older meals page failed');
      if (mounted) setState(() => _loadingOlderMeals = false);
    }
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
          .select(
            'user_id, is_open, is_live, default_prep_minutes, kitchen_photos, local_kitchen_name, instagram_url, youtube_url, facebook_url',
          )
          .inFilter('user_id', missing.toList());
      var closedChanged = false;
      for (final row in rows) {
        final id = row['user_id']?.toString();
        if (id == null || id.isEmpty) continue;
        final profile = Map<String, dynamic>.from(row);
        _chefOpenResolved.add(id);
        _chefKitchenProfiles[id] = profile;
        if (!isChefKitchenAcceptingOrders(profile)) {
          _closedChefIds.add(id);
          closedChanged = true;
        }
      }
      _chefOpenResolved.addAll(missing);
      if (closedChanged && mounted) setState(() {});
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to hydrate kitchen profiles');
      _chefOpenResolved.addAll(missing);
    } finally {
      _hydratingKitchenHours = false;
    }
  }

  Future<void> _hydrateChefTrust(List<Map<String, dynamic>> meals) async {
    final missing = <String>{};
    for (final meal in meals) {
      final chefId = meal['chef_id']?.toString();
      if (chefId == null || chefId.isEmpty || _chefTrustResolved.contains(chefId)) continue;
      missing.add(chefId);
    }
    if (missing.isEmpty || _hydratingChefTrust) return;
    _hydratingChefTrust = true;
    try {
      final rows = await Supabase.instance.client
          .rpc('chef_fssai_public', params: {'p_ids': missing.toList()})
          .withTimeout(NetworkTimeouts.standard);
      final list = rows is List ? rows : const [];
      for (final raw in list) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        _chefTrustResolved.add(id);
        _chefTrust[id] = row;
      }
      _chefTrustResolved.addAll(missing);
      if (mounted) setState(() {});
    } catch (e, stack) {
      final denied = e.toString().contains('42501') ||
          e.toString().toLowerCase().contains('permission denied');
      if (!denied) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to hydrate chef FSSAI chips');
      }
      _chefTrustResolved.addAll(missing);
    } finally {
      _hydratingChefTrust = false;
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
      _hydrateChefTrust(meals);
    });
    final pinned = _openKitchenMeals(
      meals
          .where((meal) =>
              mealAvoidsAllergies(meal, _allergies) &&
              !mealFailsCurrentCatalogRequirements(meal))
          .map(_pinnedMeal)
          .toList(),
    );
    if (!_hasDeliveryPin) return [];
    final dest = _selectedAddressMap;
    final endLat = addressCoordinate(dest, latitude: true);
    final endLng = addressCoordinate(dest, latitude: false);
    if (endLat == null || endLng == null) return [];

    final dinerPin = dest?['postal_code']?.toString() ?? dest?['pincode']?.toString();
    final inRange = <Map<String, dynamic>>[];
    for (final meal in pinned) {
      final startLat = kitchenCoordinate(meal, latitude: true);
      final startLng = kitchenCoordinate(meal, latitude: false);
      if (kitchenServesDinerPin(
        kitchenLat: startLat,
        kitchenLng: startLng,
        dinerLat: endLat,
        dinerLng: endLng,
        dinerPincode: dinerPin,
        kitchenPincode: meal['pincode']?.toString() ?? meal['postal_code']?.toString(),
      )) {
        inRange.add(meal);
      }
    }
    return inRange;
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
    if (!DeliveryEstimatorService.isWithinDeliveryRadius(distance) &&
        !kitchenServesDinerPin(
          kitchenLat: startLat,
          kitchenLng: startLng,
          dinerLat: endLat,
          dinerLng: endLng,
        )) {
      return 'Outside ${DeliveryEstimatorService.maxDeliveryRadiusKm.toInt()} km';
    }
    return '${DeliveryEstimatorService.estimateEtaMinutes(
      distance,
      prepMinutes: kitchenPrepMinutes(
        _chefKitchenProfiles[meal['chef_id']?.toString()],
        meal,
      ),
    )} min';
  }

  void _handleAddToCart(Map<String, dynamic> meal) async {
    final added = await addMealToCartWithConflict(context: context, ref: ref, meal: meal);
    if (!added || !mounted) return;
    showAddedToCartSnack(
      context,
      onViewCart: widget.onGoToCart,
    );
  }

  Future<void> _payThisPlate(Map<String, dynamic> meal) async {
    if (Supabase.instance.client.auth.currentUser == null) {
      showAuthBottomSheet(context, () {
        if (mounted) unawaited(_payThisPlate(meal));
      });
      return;
    }
    final added = await addMealToCartWithConflict(context: context, ref: ref, meal: meal);
    if (!added || !mounted) return;
    final mealId = meal['id']?.toString() ?? '';
    final checkoutItems = ref
        .read(cartProvider)
        .items
        .where((item) => item.mealId == mealId || item.chefId == (meal['chef_id']?.toString() ?? ''))
        .map((item) => item.toCheckoutPayload())
        .toList();
    if (checkoutItems.isEmpty) {
      widget.onGoToCart?.call();
      return;
    }
    await Navigator.push(
      context,
      appMaterialRoute(
        CheckoutScreen(
          cartItems: checkoutItems,
          preferredAddress: ref.read(selectedDeliveryAddressProvider),
          preferredAddressId: ref.read(selectedDeliveryAddressProvider)?['id'],
          onOrderPlacedSuccess: () {
            ref.read(cartProvider.notifier).clearCart();
            widget.onReorderToOrders?.call();
          },
        ),
      ),
    );
  }

  Future<void> _showGuestLocationSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: AppTheme.bottomSheetDecoration(
          isDark: Theme.of(context).brightness == Brightness.dark,
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Delivering near you',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.onSurfaceOf(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _hasDeliveryPin
                  ? 'We use your current location so guest browsing matches kitchens after Sign In.'
                  : 'Allow location so only nearby kitchens appear — the same list stays after Sign In.',
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.35),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _hasDeliveryPin ? Icons.my_location : Icons.location_searching,
                color: brandPrimary,
              ),
              title: Text(
                _hasDeliveryPin
                    ? (_deviceLocationPin?['is_launch_city'] == true
                        ? 'Select location'
                        : (_deviceLocationPin?['address']?.toString() ?? _currentAddress))
                    : 'Location not set',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.onSurfaceOf(context)),
              ),
              subtitle: Text(
                _resolvingDeviceLocation
                    ? 'Updating…'
                    : (_deviceLocationPin?['is_launch_city'] == true
                        ? 'Tap to use pin and locality'
                        : 'Current location'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _resolvingDeviceLocation
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      setState(() => _currentAddress = 'Locating...');
                      await _captureDeviceLocation(notifyOnFailure: true);
                    },
              icon: const Icon(Icons.refresh),
              label: const Text('Use current location'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandPrimary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                showAuthBottomSheet(context, () {
                  setState(() {});
                  _fetchUserAddresses(preserveActivePin: true);
                });
              },
              child: const Text('Sign In to save addresses'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;
    final followedKitchens = ref.watch(kitchenFollowsProvider);
    final cartCount = ref.watch(cartProvider).itemCount;
    final showFavorites = feedFavoritesFilterActive(
      signedIn: isLoggedIn,
      favoritesOnly: _showFavoritesOnly,
    );
    final showFollowing = feedFollowingFilterActive(
      signedIn: isLoggedIn,
      followingOnly: _showFollowingOnly,
    );

    return SingleChildScrollView(
      controller: _feedScrollController,
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                color: AppTheme.canvasOf(context),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        const AppLogo(size: 28),
                        const SizedBox(width: 8),
                        Text(
                          'HotPotChef',
                          style: AppTheme.sectionTitleOf(context).copyWith(
                            color: AppTheme.primary,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Semantics(
                            button: true,
                            label: 'Delivering to $_currentAddress. Tap to change delivery location.',
                            child: GestureDetector(
                          onTap: () async {
                            if (_addressPickerOpen) return;
                            _addressPickerOpen = true;
                            try {
                            if (!isLoggedIn) {
                              await _showGuestLocationSheet(context);
                              return;
                            }

                            await _fetchUserAddresses(preserveActivePin: true);
                            if (!context.mounted) return;

                            await showModalBottomSheet(
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
                                    if (_deviceLocationPin != null)
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        decoration: BoxDecoration(
                                          color: _isUsingDevicePin
                                              ? AppTheme.primary.withValues(alpha: 0.08)
                                              : AppTheme.surfaceOf(context),
                                          borderRadius: AppTheme.radiusMd,
                                          border: Border.all(
                                            color: _isUsingDevicePin ? AppTheme.primary : AppTheme.hairlineOf(context),
                                          ),
                                        ),
                                        child: ListTile(
                                          dense: true,
                                          leading: Icon(
                                            Icons.my_location,
                                                    color: _isUsingDevicePin ? brandPrimary : AppTheme.textMuted,
                                          ),
                                          title: Text(
                                            _deviceLocationPin!['address']?.toString() ?? 'Current location',
                                            style: TextStyle(
                                              color: _isUsingDevicePin ? AppTheme.linkOf(context) : AppTheme.onSurfaceOf(context),
                                              fontSize: 13,
                                              fontWeight: _isUsingDevicePin ? FontWeight.bold : FontWeight.normal,
                                            ),
                                          ),
                                          subtitle: const Text('Current location', style: TextStyle(fontSize: 12)),
                                          onTap: () {
                                            final label = _deviceLocationPin!['address']?.toString() ?? 'Near you';
                                            setState(() => _currentAddress = label);
                                            ref
                                                .read(selectedDeliveryAddressProvider.notifier)
                                                .setAddress(_deviceLocationPin);
                                            Navigator.pop(ctx);
                                          },
                                        ),
                                      ),
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
                                                borderRadius: AppTheme.radiusMd,
                                                border: Border.all(
                                                    color: isSelected ? AppTheme.primary : AppTheme.hairlineOf(context)),
                                              ),
                                              child: ListTile(
                                                dense: true,
                                                leading: Icon(Icons.location_on,
                                                    color: isSelected ? brandPrimary : AppTheme.textMuted),
                                                title: Text(
                                                  addrStr,
                                                  style: TextStyle(
                                                    color: isSelected ? AppTheme.linkOf(context) : AppTheme.onSurfaceOf(context),
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
                                    IconButton(
                                      tooltip: 'Add new address',
                                      icon: const Icon(Icons.add_location_alt, color: brandPrimary),
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        Navigator.push(
                                          context,
                                          appMaterialRoute(const AddressFormScreen()),
                                        ).then((_) => _fetchUserAddresses(preserveActivePin: true));
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                            } finally {
                              _addressPickerOpen = false;
                            }
                          },
                          child: Row(
                            children: [
                              Icon(Icons.location_on, color: AppTheme.primary, size: 16),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  _currentAddress,
                                  style: AppTheme.captionOf(context).copyWith(fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.keyboard_arrow_down, color: AppTheme.textMutedOf(context), size: 16),
                            ],
                          ),
                        ),
                        ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            if (isLoggedIn) ...[
                              _homeHeaderToggle(
                                tooltip: 'Following',
                                icon: Icons.storefront_outlined,
                                selectedIcon: Icons.storefront,
                                selected: _showFollowingOnly,
                                onSelected: (selected) {
                                  setState(() {
                                    _showFollowingOnly = selected;
                                    if (selected) _showFavoritesOnly = false;
                                  });
                                  if (selected && followedKitchens.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Follow a kitchen from the chef card to see it here.'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                              ),
                              _homeHeaderToggle(
                                tooltip: 'Favorites',
                                icon: Icons.favorite_border,
                                selectedIcon: Icons.favorite,
                                selected: _showFavoritesOnly,
                                onSelected: (selected) {
                                  setState(() {
                                    _showFavoritesOnly = selected;
                                    if (selected) _showFollowingOnly = false;
                                  });
                                  if (selected && widget.favoriteMeals.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Save a meal with the heart icon to see it here.'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ] else ...[
                              Semantics(
                                button: true,
                                label: 'Sign In',
                                child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: brandPrimary,
                                  elevation: 0,
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusXl),
                                ),
                                onPressed: () => showAuthBottomSheet(context, () {
                                  setState(() {});
                                  _fetchUserAddresses(preserveActivePin: true);
                                }),
                                child: const Text('Sign In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                              ),
                            ],
                            _homeCartButton(cartCount),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.surfaceOf(context),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.hairlineOf(context)),
                boxShadow: AppTheme.softShadow,
              ),
              child: TextField(
                controller: _searchController,
                onSubmitted: (val) => _performAiSearch(val),
                decoration: InputDecoration(
                  hintText: 'Search for thali, biryani, hotpot…',
                  hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _homeModeChip('Pre-order', 'preorder', Icons.calendar_month_outlined, AppTheme.primary),
                _homeModeChip('Live Order', 'live', Icons.local_fire_department_outlined, AppTheme.live),
              ],
            ),
          ),

          if (!_hasActiveSearch)
            LiveOffersFlashBanner(
              meals: _mealsRestSnapshot ?? const [],
              excludedChefIds: _closedChefIds,
              destinationLat: addressCoordinate(_selectedAddressMap, latitude: true),
              destinationLng: addressCoordinate(_selectedAddressMap, latitude: false),
              chefKitchenPins: _chefKitchenPins,
              onOfferTap: _onHomeOfferTap,
            ),

          if (isLoggedIn) const SupportRepliedBanner(),

          if (_currentAddress == 'Select Delivery Address')
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Material(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: AppTheme.radiusMd,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Drop a pin or turn on location. We do not guess a city for you.',
                    style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),

          if (_outOfServiceArea)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Material(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: AppTheme.radiusMd,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'HotPotChef is live in ${launchCitiesLabel()} first. Change your pin to a local drop to see nearby kitchens.',
                    style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),

          if (!_hasActiveSearch) ...[
            const SizedBox(height: 4),
            _filterChipRow(
              chips: _dietFilters,
              selected: _selectedDiet,
              onSelected: (name) => setState(() => _selectedDiet = name),
            ),
            const SizedBox(height: 8),
          ],

          if (_hasActiveSearch || showFollowing || showFavorites)
            Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(
                      _hasActiveSearch
                          ? (_filteredChefId != null
                              ? 'Dishes from ${_filteredChefName ?? 'this chef'}'
                              : (_offerBrowseLabel != null
                                  ? '$_offerBrowseLabel offers'
                                  : 'Search results'))
                          : (showFollowing ? 'Kitchens you follow' : 'Your favorites'),
                      style: AppTheme.homeSectionLabelOf(context).copyWith(fontSize: 16),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _hasActiveSearch
                          ? (_filteredChefId != null
                              ? 'Only Available meals from this kitchen'
                              : (_offerBrowseGroupKey != null
                                  ? offerFlashGroupBrowseHint(_offerBrowseGroupKey)
                                  : (_chefSearchResults.isEmpty
                                      ? '"${_searchController.text}"'
                                      : '${_chefSearchResults.length} chef${_chefSearchResults.length == 1 ? '' : 's'} · "${_searchController.text}"')))
                          : (showFollowing
                              ? 'Live dishes from kitchens you follow'
                              : 'Meals you loved'),
                      style: AppTheme.metaOf(context),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  ),
                ),
                if (_hasActiveSearch)
                  IconButton(
                    tooltip: 'Clear search',
                    onPressed: _clearHomeSearch,
                    icon: const Icon(Icons.close, size: 20, color: Colors.red),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (_isAiSearching)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary),
                    SizedBox(height: 16),
                    Text('Searching dishes and chefs...', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            )
          else if (_hasActiveSearch) ...[
            if (_chefSearchResults.isNotEmpty) _buildChefSearchStrip(_chefSearchResults),
            _buildMealGrid(
              () {
                var meals = showFavorites
                    ? _aiSearchResults.where((m) => widget.favoriteMeals.contains(m['id'].toString())).toList()
                    : List<Map<String, dynamic>>.from(_aiSearchResults);
                final chefId = _filteredChefId;
                if (chefId != null && chefId.isNotEmpty) {
                  meals = meals.where((m) => m['chef_id']?.toString() == chefId).toList();
                  return _applyFeedChips(meals);
                }
                return _applyFeedChips(_mealsForSelectedAddress(_filterFollowedMeals(
                  meals,
                  followedKitchens,
                  showFollowing,
                )));
              }(),
              isLoggedIn: isLoggedIn,
              showFavorites: showFavorites,
              showFollowing: showFollowing,
              hasFollows: followedKitchens.isNotEmpty,
            ),
          ]
          else
            Builder(
              builder: (context) {
                final mealsSource = _mealsRestSnapshot;
                if (_loadingMealsRest && mealsSource == null) {
                  return const MealListSkeleton(count: 4);
                }
                if (mealsSource == null) {
                  return EmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: 'Trouble reaching the kitchen',
                    message: 'We couldn\'t load fresh meals right now. Please check your connection and try again.',
                    actionLabel: 'Retry',
                    onAction: _retryMealsFeed,
                  );
                }
                if (mealsSource.isEmpty) {
                  return const EmptyState(
                    icon: Icons.restaurant_menu_rounded,
                    title: 'No meals published yet',
                    message: 'Our home chefs are prepping something delicious. Check back soon!',
                  );
                }

                var meals = mealsSource.where((m) {
                  final status = m['status']?.toString().toLowerCase() ?? '';
                  final isInventory = (m['customer_name'] == null || m['customer_name'].toString().isEmpty);
                  if (!isInventory || status == 'paused' || status == 'cancelled') return false;
                  return isMealAvailableForCart(m);
                }).toList();
                if (_olderMeals.isNotEmpty) {
                  final seen = meals.map((m) => m['id']?.toString()).toSet();
                  for (final extra in _olderMeals) {
                    final id = extra['id']?.toString();
                    if (id == null || seen.contains(id)) continue;
                    seen.add(id);
                    meals.add(extra);
                  }
                }

                if (meals.isEmpty) {
                  return const EmptyState(
                    icon: Icons.restaurant_menu_rounded,
                    title: 'No plates on your slot right now',
                    message: 'Live kitchens will show here when a bookable window is open. Pull to refresh.',
                  );
                }

                if (showFavorites) {
                  meals = meals.where((m) => widget.favoriteMeals.contains(m['id'].toString())).toList();
                }
                meals = _filterFollowedMeals(meals, followedKitchens, showFollowing);

                meals = _applyFeedChips(_mealsForSelectedAddress(meals));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_hasActiveSearch && !showFavorites && !showFollowing) ...[
                      DinerSectionHeader(
                        title: DinerLocaleController.instance.copy.socialChefs,
                      ),
                      _buildTrendingChefsStrip(meals),
                      DinerSectionHeader(title: 'Popular Dishes'),
                    ],
                    if (!_hasActiveSearch && !showFavorites && !showFollowing)
                      _buildPopularDishList(meals)
                    else
                    _buildMealGrid(
                      meals,
                      isLoggedIn: isLoggedIn,
                      showFavorites: showFavorites,
                      showFollowing: showFollowing,
                      hasFollows: followedKitchens.isNotEmpty,
                    ),
                    if (!_olderMealsExhausted && mealsSource.length >= kHomeMealStreamLimit)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: TextButton(
                          onPressed: _loadingOlderMeals ? null : _loadOlderMeals,
                          child: Text(_loadingOlderMeals ? 'Loading more plates…' : 'Show more plates'),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filterFollowedMeals(
    List<Map<String, dynamic>> meals,
    Set<String> followedKitchens,
    bool showFollowing,
  ) {
    if (!showFollowing) return meals;
    return meals.where((m) => followedKitchens.contains(m['chef_id']?.toString())).toList();
  }

  List<Map<String, dynamic>> _applyFeedChips(List<Map<String, dynamic>> meals) {
    final kitchenBrowse = _filteredChefId != null && _filteredChefId!.isNotEmpty;
    final filtered = meals
        .where((meal) =>
            mealMatchesFeedDiet(meal, _selectedDiet) &&
            mealMatchesCuisine(meal, _selectedCategory) &&
            (kitchenBrowse ||
                mealMatchesHomeMode(
                  meal,
                  mode: _homeMode,
                  chefProfile: _chefKitchenProfiles[meal['chef_id']?.toString()],
                )))
        .toList();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateChefRatings(filtered));
    return sortFeedMeals(
      filtered,
      sort: _selectedSort,
      distanceKm: _distanceKmForMeal,
      rating: (meal) {
        final chefId = meal['chef_id']?.toString() ?? '';
        return _chefRatings[chefId]?.average ?? 0;
      },
      etaMinutes: (meal) {
        final km = _distanceKmForMeal(meal);
        return DeliveryEstimatorService.estimateEtaMinutes(
          km ?? 0,
          prepMinutes: kitchenPrepMinutes(
            _chefKitchenProfiles[meal['chef_id']?.toString()],
            meal,
          ),
        );
      },
    );
  }

  double? _distanceKmForMeal(Map<String, dynamic> meal) {
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
    return distance;
  }

  Future<void> _hydrateChefRatings(List<Map<String, dynamic>> meals) async {
    final missing = <String>{};
    for (final meal in meals) {
      final id = meal['chef_id']?.toString() ?? '';
      if (id.isNotEmpty && !_chefRatings.containsKey(id)) missing.add(id);
    }
    if (missing.isEmpty || _hydratingRatings) return;
    _hydratingRatings = true;
    try {
      final rows = await Supabase.instance.client.rpc(
        'chef_rating_summaries',
        params: {'p_chef_ids': missing.toList()},
      );
      var changed = false;
      if (rows is List) {
        for (final row in rows) {
          if (row is! Map) continue;
          final id = row['chef_id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final avg = double.tryParse(row['average']?.toString() ?? '') ?? 0;
          final count = int.tryParse(row['review_count']?.toString() ?? '') ?? 0;
          _chefRatings[id] = ChefRatingSummary(average: avg, count: count);
          changed = true;
        }
      }
      for (final id in missing) {
        _chefRatings.putIfAbsent(id, () => const ChefRatingSummary());
      }
      if (changed && mounted) setState(() {});
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to hydrate chef ratings');
      for (final id in missing) {
        _chefRatings.putIfAbsent(id, () => const ChefRatingSummary());
      }
    } finally {
      _hydratingRatings = false;
    }
  }

  Widget _buildChefSearchStrip(List<Map<String, dynamic>> chefs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Matching chefs · tap to show only their dishes',
            style: AppTheme.sectionTitleOf(context).copyWith(fontSize: 15),
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: chefs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final chef = chefs[index];
              final id = chef['id']?.toString() ?? '';
              final name = chefDisplayName(chef);
              final local = chef['local_kitchen_name']?.toString().trim() ?? '';
              final fssai = chef['fssai_number']?.toString() ?? '';
              final selected = id.isNotEmpty && id == _filteredChefId;
              return Semantics(
                button: true,
                label: 'Show all dishes from $name',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: AppTheme.radiusMd,
                    onTap: id.isEmpty ? null : () => _filterFeedToChef(chef),
                    child: Container(
                      width: 188,
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primary.withValues(alpha: 0.10)
                            : AppTheme.surfaceOf(context),
                        borderRadius: AppTheme.radiusMd,
                        border: Border.all(
                          color: selected ? AppTheme.primary : AppTheme.hairlineOf(context),
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                selected ? Icons.storefront : Icons.storefront_outlined,
                                size: 16,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Chef profile',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                icon: const Icon(Icons.info_outline, size: 18, color: AppTheme.textMuted),
                                onPressed: id.isEmpty
                                    ? null
                                    : () => showChefProfileDialog(context, id, name, fssai),
                              ),
                            ],
                          ),
                          Text(
                            local.isNotEmpty ? local : (selected ? 'Showing this kitchen only' : 'Tap for all dishes'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: selected ? AppTheme.linkOf(context) : AppTheme.textMuted,
                              height: 1.3,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _homeHeaderToggle({
    required String tooltip,
    required IconData icon,
    required IconData selectedIcon,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: () => onSelected(!selected),
      style: IconButton.styleFrom(
        foregroundColor: selected ? Colors.white : AppTheme.primary,
        backgroundColor: selected ? AppTheme.primary : AppTheme.surfaceOf(context),
        minimumSize: const Size(36, 36),
        maximumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
      ),
      icon: Icon(selected ? selectedIcon : icon, size: 18),
    );
  }

  Widget _homeCartButton(int cartCount) {
    return IconButton(
      tooltip: 'Cart',
      visualDensity: VisualDensity.compact,
      onPressed: widget.onGoToCart,
      style: IconButton.styleFrom(
        foregroundColor: AppTheme.primary,
        backgroundColor: AppTheme.surfaceOf(context),
        minimumSize: const Size(36, 36),
        maximumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
      ),
      icon: Badge(
        isLabelVisible: cartCount > 0,
        label: Text('$cartCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        child: const Icon(Icons.shopping_bag_outlined, size: 18),
      ),
    );
  }

  Widget _filterChipRow({
    required List<Map<String, dynamic>> chips,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: chips.length,
        itemBuilder: (context, index) {
          final chip = chips[index];
          final name = chip['name']?.toString() ?? '';
          final isSelected = selected == name;
          return GestureDetector(
            onTap: () => onSelected(name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: AppTheme.filterChipDecoration(context, selected: isSelected),
              child: Row(
                children: [
                  Icon(chip['icon'] as IconData, color: isSelected ? Colors.white : AppTheme.textMuted, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    name,
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
    );
  }

  Widget _homeModeChip(String label, String mode, IconData icon, Color accent) {
    return DinerCircleModeChip(
      icon: icon,
      label: label,
      selected: _homeMode == mode,
      accent: accent,
      onTap: () {
        setState(() {
          _homeMode = mode;
          if (mode == 'live') _selectedSort = kFeedSortEta;
          if (mode == 'preorder') _selectedSort = kFeedSortNearby;
        });
      },
    );
  }

  List<Map<String, dynamic>> _uniqueChefsFromMeals(List<Map<String, dynamic>> meals) {
    final seen = <String>{};
    final chefs = <Map<String, dynamic>>[];
    for (final meal in meals) {
      final id = meal['chef_id']?.toString() ?? '';
      if (id.isEmpty || !seen.add(id)) continue;
      final profile = _chefKitchenProfiles[id] ?? {};
      chefs.add({
        'id': id,
        'chef_id': id,
        'chef_name': chefDisplayName({...profile, ...meal}),
        'local_kitchen_name': profile['local_kitchen_name'] ?? meal['local_kitchen_name'],
        'fssai_number': profile['fssai_number'] ?? meal['fssai_number'],
        'image_url': meal['image_url'],
        'kitchen_photos': profile['kitchen_photos'],
        'instagram_url': profile['instagram_url'],
        'youtube_url': profile['youtube_url'],
        'facebook_url': profile['facebook_url'],
      });
      if (chefs.length >= 8) break;
    }
    return chefs;
  }

  Widget _buildTrendingChefsStrip(List<Map<String, dynamic>> meals) {
    final chefs = _uniqueChefsFromMeals(meals)
      ..sort((a, b) {
        final aSocial = ChefSocialLinks.fromMap(a).hasAny;
        final bSocial = ChefSocialLinks.fromMap(b).hasAny;
        if (aSocial == bSocial) return 0;
        return aSocial ? -1 : 1;
      });
    if (chefs.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        itemCount: chefs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chef = chefs[index];
          final id = chef['id']?.toString() ?? '';
          final name = chefDisplayName(chef);
          final rating = _chefRatings[id];
          final social = ChefSocialLinks.fromMap(chef);
          final photos = kitchenPhotosFrom(chef['kitchen_photos']);
          final photo = photos.isNotEmpty ? photos.first : chef['image_url']?.toString();
          final meta = social.hasAny
              ? social.platformsLabel
              : (rating == null || !rating.hasReviews
                  ? 'New kitchen'
                  : '${rating.average.toStringAsFixed(1)} (${rating.count})');
          return GestureDetector(
            onTap: id.isEmpty ? null : () => _filterFeedToChef(chef),
            child: Container(
              width: 168,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: AppTheme.cardDecoration(isDark: Theme.of(context).brightness == Brightness.dark),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.photoFallback,
                    backgroundImage: (photo != null && photo.isNotEmpty) ? CachedNetworkImageProvider(photo) : null,
                    child: (photo == null || photo.isEmpty)
                        ? Text(
                            name.isEmpty ? 'C' : name[0].toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.cardTitleOf(context).copyWith(fontSize: 13, height: 1.1),
                        ),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.caption.copyWith(fontSize: 12, height: 1.1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPopularDishList(List<Map<String, dynamic>> meals) {
    if (meals.isEmpty) {
      return _buildMealGrid(meals, isLoggedIn: true, showFavorites: false);
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      itemCount: meals.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final meal = meals[index];
        final offerSummary = PricingCalculator.calculateItemSummary(meal, 1);
        final price = offerSummary.effectiveUnitPrice;
        final showOfferPrice = offerSummary.baseUnitPrice - price > 0.004;
        final chefName = chefDisplayName({...?_chefKitchenProfiles[meal['chef_id']?.toString()], ...meal});
        final image = meal['image_url']?.toString();
        final prep = kitchenPrepMinutes(_chefKitchenProfiles[meal['chef_id']?.toString()], meal);
        final offerBadge = showOfferPrice ? PricingCalculator.offerBadgeLabel(meal) : '';
        return GestureDetector(
          onTap: () => showMealDetailsDialog(context, meal, ref, onGoToCart: widget.onGoToCart),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: AppTheme.cardDecoration(isDark: Theme.of(context).brightness == Brightness.dark),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: image == null || image.isEmpty
                            ? ColoredBox(color: AppTheme.photoFallback, child: Icon(Icons.ramen_dining, color: AppTheme.textMuted))
                            : CachedNetworkImage(imageUrl: image, fit: BoxFit.cover),
                      ),
                    ),
                    if (showOfferPrice && offerBadge.isNotEmpty)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            offerBadge,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meal['title']?.toString() ?? 'Home plate',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.cardTitleOf(context).copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'by $chefName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption,
                      ),
                      if (prep > 0) ...[
                        const SizedBox(height: 2),
                        Text('Prep: $prep mins', style: AppTheme.caption),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        mealPortionsLeftLabel(meal),
                        style: AppTheme.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          color: mealPortionsLeft(meal) <= 0 ? AppTheme.error : AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          if (showOfferPrice)
                            Text(
                              '₹${wholeRupees(offerSummary.baseUnitPrice)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textMuted,
                                decoration: TextDecoration.lineThrough,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          Text(
                            '₹${wholeRupees(price)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppTheme.primary,
                            ),
                          ),
                          if (showOfferPrice && offerBadge.isNotEmpty)
                            Text(
                              offerBadge,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (showOfferPrice)
                            FlashingOfferCountdown(
                              until: PricingCalculator.parseOfferDate(meal['offer_valid_until']),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMealGrid(
    List<Map<String, dynamic>> meals, {
    required bool isLoggedIn,
    required bool showFavorites,
    bool showFollowing = false,
    bool hasFollows = false,
  }) {
    if (meals.isEmpty) {
      final copy = feedEmptyCopy(
        signedIn: isLoggedIn,
        favoritesOnly: showFavorites || _showFavoritesOnly,
        hasFavorites: widget.favoriteMeals.isNotEmpty,
        hasSearch: _hasActiveSearch,
        searchQuery: _searchController.text,
        category: _selectedCategory,
        diet: _selectedDiet,
        hasDeliveryPin: _hasDeliveryPin,
        followingOnly: showFollowing || _showFollowingOnly,
        hasFollows: hasFollows,
        offerBrowseGroupKey: _offerBrowseGroupKey,
        outOfServiceArea: _outOfServiceArea,
        homeMode: _homeMode,
      );
      return EmptyState(
        icon: copy.promptSignIn || showFollowing
            ? Icons.storefront_outlined
            : showFavorites
                ? Icons.favorite_border
                : Icons.search_off_rounded,
        title: copy.title,
        message: copy.message,
        actionLabel: copy.promptSignIn
            ? 'Sign In'
            : copy.clearCategory
                ? 'Show all meals'
                : null,
        onAction: copy.promptSignIn
            ? () => showAuthBottomSheet(context, () => setState(() {}))
            : copy.clearCategory
                ? () => setState(() {
                      _selectedCategory = 'All';
                      _selectedDiet = 'All';
                    })
                : null,
      );
    }

    meals.sort((a, b) {
      final aAvailable = !_checkIfTimePassed(a) &&
          (int.tryParse(a['quantity'].toString()) ?? 0) > 0 &&
          a['status']?.toString().toLowerCase() != 'sold out';
      final bAvailable = !_checkIfTimePassed(b) &&
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
            mainAxisExtent: 436,
          ),
          itemCount: meals.length,
          itemBuilder: (context, index) {
            final meal = meals[index];
            final isFavorite = widget.favoriteMeals.contains(meal['id'].toString());

            final isExpired = _checkIfTimePassed(meal);
            final availableQty = int.tryParse(meal['quantity'].toString()) ?? 0;
            final isSoldOut = availableQty <= 0 || meal['status']?.toString().toLowerCase() == 'sold out';
            final isAvailable = !isExpired && !isSoldOut;
            String overlayText = isSoldOut ? 'Sold out' : (isExpired ? 'Slot passed' : '');

            final cartState = ref.watch(cartProvider);
            final offerSummary = PricingCalculator.calculateItemSummary(meal, 1);
            final hasOffer = cartState.isOfferActive(meal) || PricingCalculator.isOfferGated(meal);
            final showOfferPrice = offerSummary.isOfferApplied;
            final etaLabel = _etaLabelForMeal(meal);

            return GestureDetector(
              onTap: () => showMealDetailsDialog(context, meal, ref, onGoToCart: widget.onGoToCart),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: AppTheme.layeredCardDecoration(context),
                child: Stack(
                  children: [
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
                                  height: 188,
                                  width: double.infinity,
                                  color: AppTheme.photoFallback,
                                  child: meal['image_url'] != null
                                      ? CachedNetworkImage(
                                          imageUrl: meal['image_url'].toString(),
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                          placeholder: (_, _) => const AppShimmer(
                                            child: ShimmerBox(
                                              width: double.infinity,
                                              height: 188,
                                              borderRadius: BorderRadius.zero,
                                            ),
                                          ),
                                          errorWidget: (_, _, _) => const Icon(
                                            Icons.soup_kitchen_outlined,
                                            color: Color(0xFFC4A484),
                                            size: 40,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.soup_kitchen_outlined,
                                          color: Color(0xFFC4A484),
                                          size: 40,
                                        ),
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
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.rLg)),
                                    ),
                                    child: Center(
                                      child: Text(
                                        overlayText,
                                        style: const TextStyle(
                                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
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
                                        color: Colors.red.shade600, borderRadius: BorderRadius.circular(12)),
                                    child: Text(
                                      PricingCalculator.offerBadgeLabel(meal),
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Semantics(
                                  button: true,
                                  label: isFavorite ? 'Remove from favorites' : 'Save to favorites',
                                  child: GestureDetector(
                                  onTap: () {
                                    if (!isLoggedIn) {
                                      showAuthBottomSheet(context, () => setState(() {}));
                                      return;
                                    }
                                    widget.onToggleFavorite(meal['id'].toString());
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                        color: AppTheme.surfaceOf(context).withValues(alpha: 0.9), shape: BoxShape.circle),
                                    child: Icon(
                                      isFavorite ? Icons.favorite : Icons.favorite_border,
                                      color: brandPrimary,
                                      size: 16,
                                    ),
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
                                      color: AppTheme.surfaceOf(context).withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Icon(
                                    Icons.circle,
                                    color: mealIsVegetarian(meal) ? AppTheme.veg : AppTheme.nonVeg,
                                    size: 10,
                                  ),
                                ),
                              ),
                              const Positioned(
                                bottom: 8,
                                right: 8,
                                child: Opacity(
                                  opacity: 0.5,
                                  child: AppLogo(size: 16, onDark: true),
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
                                  style: AppTheme.cardTitleOf(context),
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
                                      const Icon(Icons.storefront_outlined, size: 13, color: textMuted),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          chefDisplayName(meal),
                                          style: TextStyle(
                                            color: AppTheme.onSurfaceOf(context),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (dinerFssaiCardChip(
                                            verificationStatus: (_chefTrust[meal['chef_id']?.toString()] ?? meal)['fssai_verification_status']?.toString(),
                                            validUntil: parseStoredFssaiValidUntil((_chefTrust[meal['chef_id']?.toString()] ?? meal)['fssai_valid_until']),
                                          )
                                          .isNotEmpty) ...[
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primary.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            DinerLocaleController.instance.copy.verified,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                      MealRatingBadge(meal: meal),
                                    ],
                                  ),
                                ),
                                if (mealNutritionFacts(meal).hasValues) ...[
                                  const SizedBox(height: 8),
                                  MealNutritionStrip(meal: meal, compact: true),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: AppTheme.canvasOf(context),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: AppTheme.hairlineOf(context)),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.schedule,
                                              size: 12,
                                              color: isExpired ? Colors.red : AppTheme.primary,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                feedKitchenSlotLabel(meal['time_slot']?.toString()),
                                                style: TextStyle(
                                                  color: isExpired ? Colors.red : AppTheme.onSurfaceOf(context),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (etaLabel != null) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        etaLabel,
                                        style: const TextStyle(
                                          color: AppTheme.link,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (showOfferPrice)
                                            Text(
                                              '₹${wholeRupees(offerSummary.baseUnitPrice)}',
                                              style: const TextStyle(
                                                color: AppTheme.textMuted,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                decoration: TextDecoration.lineThrough,
                                              ),
                                            ),
                                          Text(
                                            '₹${wholeRupees(offerSummary.effectiveUnitPrice)}',
                                            style: AppTheme.priceOf(context),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (showOfferPrice)
                                            FlashingOfferCountdown(
                                              until: PricingCalculator.parseOfferDate(meal['offer_valid_until']),
                                            ),
                                          if (isAvailable)
                                            Text(
                                              '$availableQty left',
                                              style: const TextStyle(
                                                  color: brandPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Share dish',
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(Icons.share_outlined, size: 18, color: AppTheme.onSurfaceOf(context)),
                                      onPressed: () => showMealShareSheet(context, meal),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Material(
                                      color: Colors.transparent,
                                      child: Semantics(
                                        button: true,
                                        enabled: isAvailable,
                                        label: isAvailable
                                            ? '${DinerLocaleController.instance.copy.add} ${meal['title'] ?? 'meal'}'
                                            : 'Kitchen closed',
                                        child: InkWell(
                                        borderRadius: AppTheme.radiusMd,
                                        onTap: isAvailable ? () => _handleAddToCart(meal) : null,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          constraints: const BoxConstraints(minHeight: 44),
                                          decoration: BoxDecoration(
                                            gradient: isAvailable ? AppTheme.primaryGradient : null,
                                            color: isAvailable ? null : Colors.grey.shade200,
                                            borderRadius: AppTheme.radiusMd,
                                            boxShadow: isAvailable ? AppTheme.brandGlow(opacity: 0.25) : null,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(isAvailable ? Icons.add_rounded : Icons.lock_clock,
                                                  size: 15, color: isAvailable ? Colors.white : AppTheme.textMuted),
                                              const SizedBox(width: 4),
                                              Text(
                                                isAvailable ? DinerLocaleController.instance.copy.add : 'Closed',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: isAvailable ? Colors.white : AppTheme.textMuted),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      ),
                                    ),
                                        if (isAvailable)
                                          Semantics(
                                            button: true,
                                            label: DinerLocaleController.instance.copy.payThisPlate,
                                            child: TextButton(
                                              onPressed: () => _payThisPlate(meal),
                                              style: TextButton.styleFrom(
                                                visualDensity: VisualDensity.compact,
                                                minimumSize: const Size(44, 36),
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                              child: Text(
                                                DinerLocaleController.instance.copy.pay,
                                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                              ),
                                            ),
                                          ),
                                      ],
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