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
import '../utils/dynamic_ui_engine.dart';
import '../utils/network.dart';
import '../utils/pinned_address.dart';
import '../utils/pricing_calculator.dart';
import '../providers/cart_provider.dart';
import '../providers/delivery_preference.dart';
import '../providers/kitchen_follows_provider.dart';
import '../widgets/customer_ui_components.dart';
import '../widgets/app_widgets.dart';
import '../widgets/daily_streak_banner.dart';
import '../widgets/weekly_plan_banner.dart';
import '../widgets/last_order_banner.dart';
import '../widgets/support_replied_banner.dart';
import '../widgets/live_offers_flash_banner.dart';
import '../widgets/festival_hampers_banner.dart';
import '../widgets/society_nights_banner.dart';
import '../widgets/shelf_items_banner.dart';
import '../widgets/sponsored_placement_banner.dart';
import '../widgets/ai_recommendations_section.dart';
import '../services/delivery_estimator_service.dart';
import 'address_form_screen.dart';

class CustomerFeedTab extends ConsumerStatefulWidget {
  final List<String> favoriteMeals;
  final Function(String) onToggleFavorite;
  final VoidCallback onProfileTap;
  final VoidCallback onLogout;
  final VoidCallback? onGoToCart;
  final VoidCallback? onReorderToOrders;

  const CustomerFeedTab({
    super.key,
    required this.favoriteMeals,
    required this.onToggleFavorite,
    required this.onProfileTap,
    required this.onLogout,
    this.onGoToCart,
    this.onReorderToOrders,
  });

  @override
  ConsumerState<CustomerFeedTab> createState() => _CustomerFeedTabState();
}

class _CustomerFeedTabState extends ConsumerState<CustomerFeedTab>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<Map<String, dynamic>>> _mealsStream;
  String _selectedCategory = 'All';
  String _selectedDiet = 'All';
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
  final Set<String> _closedChefIds = {};
  final Set<String> _chefOpenResolved = {};
  bool _hydratingKitchenHours = false;
  StreamSubscription<AuthState>? _authSub;
  bool _addressPickerOpen = false;

  final List<Map<String, dynamic>> _dietFilters = const [
    {'name': 'All', 'icon': Icons.tune},
    {'name': 'Veg', 'icon': Icons.eco_outlined},
    {'name': 'Vegan', 'icon': Icons.spa_outlined},
    {'name': 'Jain', 'icon': Icons.brightness_low_outlined},
    {'name': 'High-protein', 'icon': Icons.fitness_center_outlined},
    {'name': 'Millet', 'icon': Icons.grass_outlined},
    {'name': 'Diabetic', 'icon': Icons.monitor_heart_outlined},
  ];

  final List<Map<String, dynamic>> _categories = const [
    {'name': 'All', 'icon': Icons.set_meal_outlined},
    {'name': 'Festival Hamper', 'icon': Icons.card_giftcard_outlined},
    {'name': 'Society Night', 'icon': Icons.apartment_outlined},
    {'name': 'Shelf', 'icon': Icons.kitchen_outlined},
    {'name': 'Maharashtrian', 'icon': Icons.kebab_dining_outlined},
    {'name': 'Punjabi', 'icon': Icons.ramen_dining_outlined},
    {'name': 'South Indian', 'icon': Icons.tapas_outlined},
    {'name': 'North Indian', 'icon': Icons.dinner_dining_outlined},
    {'name': 'Healthy', 'icon': Icons.favorite_outline},
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
    _bootstrapDeliveryPin();
    _fetchDietaryPrefs();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
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

  Future<void> _bootstrapDeliveryPin() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await _fetchUserAddresses(preserveActivePin: false);
      if (_hasDeliveryPin) return;
    }
    await _captureDeviceLocation();
  }

  void _resetGuestFeedState() {
    _showFavoritesOnly = false;
    _showFollowingOnly = false;
    _allergies = '';
    _selectedDiet = 'All';
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
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _applyDeviceLocationFallback(
          message: notifyOnFailure
              ? 'Allow location access so guest browsing matches kitchens after Sign In.'
              : null,
        );
        return;
      }

      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 8));
      } catch (_) {
        position = await Geolocator.getLastKnownPosition() ??
            Position(
              latitude: 18.6298,
              longitude: 73.7997,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0,
            );
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
        final formatted = parts.formatted.isNotEmpty
            ? parts.formatted
            : [parts.street, parts.city, parts.state, parts.pincode]
                .where((part) => part.isNotEmpty)
                .join(', ');
        if (formatted.isNotEmpty) {
          label = formatted;
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
        'latitude': position.latitude,
        'longitude': position.longitude,
        'lat': position.latitude,
        'lng': position.longitude,
        'is_device_location': true,
      };

      if (!mounted) return;
      setState(() {
        _deviceLocationPin = pin;
        // Do not steal a saved address the diner already picked.
        final keepSavedSelection = _savedAddresses.any(
          (addr) => addr['address']?.toString() == _currentAddress,
        );
        if (!keepSavedSelection) {
          _currentAddress = label;
          ref.read(selectedDeliveryAddressProvider.notifier).setAddress(pin);
        }
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Guest delivery location capture failed');
      _applyDeviceLocationFallback(
        message: notifyOnFailure ? 'Could not read your location. Try again.' : null,
      );
    } finally {
      _resolvingDeviceLocation = false;
    }
  }

  void _applyDeviceLocationFallback({String? message}) {
    if (!mounted) return;
    setState(() {
      if (_currentAddress == 'Locating...' || _currentAddress.isEmpty) {
        _currentAddress = 'Select Delivery Address';
      }
    });
    if (message != null && message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.orange),
      );
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
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
        _chefSearchResults.clear();
        _filteredChefId = null;
        _filteredChefName = null;
        _offerBrowseLabel = null;
      _offerBrowseGroupKey = null;
      });
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
      final response = await client.functions.invoke(
        'ai-search',
        body: {'prompt': trimmed},
      ).withTimeout(NetworkTimeouts.payment);

      List<Map<String, dynamic>> rawMeals = [];
      if (response.status == 200 && response.data != null && response.data['success'] == true) {
        rawMeals = List<Map<String, dynamic>>.from(response.data['meals']);
      }

      final localResponse = await client
          .from('meals')
          .select()
          .eq('status', 'Available')
          .withTimeout(NetworkTimeouts.standard);
      final localMeals = List<Map<String, dynamic>>.from(localResponse);
      final qClean = trimmed.toLowerCase().replaceAll(' ', '');
      final qLower = trimmed.toLowerCase();

      final localMatches = localMeals.where((m) {
        final title = m['title']?.toString().toLowerCase().replaceAll(' ', '') ?? '';
        final desc = m['description']?.toString().toLowerCase().replaceAll(' ', '') ?? '';
        if (title.contains(qClean) || desc.contains(qClean)) return true;
        return chefNameMatchesQuery(trimmed, m);
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
            .eq('role', 'Chef')
            .limit(250)
            .withTimeout(NetworkTimeouts.standard);
        for (final row in List<Map<String, dynamic>>.from(chefRows as List)) {
          if (!chefNameMatchesQuery(trimmed, row)) continue;
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
              .withTimeout(NetworkTimeouts.standard);
          for (final row in List<Map<String, dynamic>>.from(extraChefs as List)) {
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

      // Also pick chefs already present on local meal rows whose display name matches.
      for (final meal in localMeals) {
        if (!chefNameMatchesQuery(trimmed, meal)) continue;
        final id = meal['chef_id']?.toString() ?? '';
        if (id.isEmpty || chefHits.containsKey(id)) continue;
        chefHits[id] = {
          'id': id,
          'name': chefDisplayName(meal),
          'chef_name': meal['chef_name'],
          'fssai_number': meal['fssai_number'],
        };
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

      final rankedChefs = chefHits.values.toList()
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
    setState(() {
      _isAiSearching = true;
      _hasActiveSearch = true;
      _filteredChefId = id;
      _filteredChefName = name;
      _offerBrowseLabel = null;
      _offerBrowseGroupKey = null;
      _searchController.text = name;
    });
    try {
      final rows = await Supabase.instance.client
          .from('meals')
          .select()
          .eq('status', 'Available')
          .eq('chef_id', id)
          .withTimeout(NetworkTimeouts.standard);
      final meals = List<Map<String, dynamic>>.from(rows as List).where((m) {
        final status = m['status']?.toString().toLowerCase() ?? '';
        final isInventory = (m['customer_name'] == null || m['customer_name'].toString().isEmpty);
        return isInventory && status != 'paused' && status != 'cancelled';
      }).toList();
      if (!mounted) return;
      setState(() {
        _aiSearchResults = meals;
        // Keep the selected chef first in the strip.
        final others = _chefSearchResults.where((c) => c['id']?.toString() != id).toList();
        _chefSearchResults = [chef, ...others];
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Filter feed to chef failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(networkErrorMessage(e)), backgroundColor: Colors.red),
      );
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
      final client = Supabase.instance.client;
      final rows = await client
          .from('meals')
          .select()
          .eq('status', 'Available')
          .withTimeout(NetworkTimeouts.standard);
      final destLat = addressCoordinate(_selectedAddressMap, latitude: true);
      final destLng = addressCoordinate(_selectedAddressMap, latitude: false);
      final meals = <Map<String, dynamic>>[];
      for (final raw in List<Map<String, dynamic>>.from(rows as List)) {
        if (offerFlashGroupKeyForMeal(raw) != groupKey) continue;
        if (!isCatalogMeal(raw) || !mealHasSellableStock(raw)) continue;
        if (!PricingCalculator.isWithinOfferWindow(raw)) continue;
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
    if (grouped != null) {
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
        final profile = Map<String, dynamic>.from(row);
        if (!isChefKitchenOpen(profile)) {
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
    final pinned = _openKitchenMeals(
      meals.where((meal) => mealAvoidsAllergies(meal, _allergies)).map(_pinnedMeal).toList(),
    );
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
    final added = await addMealToCartWithConflict(context: context, ref: ref, meal: meal);
    if (!added || !mounted) return;
    showAddedToCartSnack(
      context,
      onViewCart: widget.onGoToCart,
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
                _hasDeliveryPin ? (_deviceLocationPin?['address']?.toString() ?? _currentAddress) : 'Location not set',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.onSurfaceOf(context)),
              ),
              subtitle: Text(
                _resolvingDeviceLocation ? 'Updating…' : 'Current location',
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
    final showFavorites = feedFavoritesFilterActive(
      signedIn: isLoggedIn,
      favoritesOnly: _showFavoritesOnly,
    );
    final showFollowing = feedFollowingFilterActive(
      signedIn: isLoggedIn,
      followingOnly: _showFollowingOnly,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  boxShadow: AppTheme.brandGlow(opacity: 0.12),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                                            color: _isUsingDevicePin ? brandPrimary : Colors.grey,
                                          ),
                                          title: Text(
                                            _deviceLocationPin!['address']?.toString() ?? 'Current location',
                                            style: TextStyle(
                                              color: _isUsingDevicePin ? AppTheme.primary : AppTheme.onSurfaceOf(context),
                                              fontSize: 13,
                                              fontWeight: _isUsingDevicePin ? FontWeight.bold : FontWeight.normal,
                                            ),
                                          ),
                                          subtitle: const Text('Current location', style: TextStyle(fontSize: 11)),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const AppLogo(size: 22, onDark: true),
                                  const SizedBox(width: 8),
                                  const Text('Delivering to',
                                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on, color: Colors.white, size: 18),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _currentAddress,
                                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
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
                        ),
                        ),
                        const SizedBox(width: 12),
                        Row(
                          children: [
                            if (isLoggedIn) ...[
                              GestureDetector(
                                onTap: widget.onProfileTap,
                                child: Semantics(
                                  button: true,
                                  label: 'Open profile',
                                  child: const CircleAvatar(
                                    backgroundColor: Colors.white,
                                    radius: 18,
                                    child: Icon(Icons.person, color: brandPrimary, size: 20),
                                  ),
                                ),
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
                    borderRadius: AppTheme.radiusLg,
                    border: Border.all(color: AppTheme.hairlineOf(context)),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (val) => _performAiSearch(val),
                    decoration: InputDecoration(
                      hintText: 'Search dishes or home chefs',
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
                          decoration: const BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: AppTheme.radiusSm,
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

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              kitchensNearCopy(
                hasPin: _hasDeliveryPin,
                usingDevicePin: _isUsingDevicePin,
                isLoggedIn: isLoggedIn,
                radiusKm: DeliveryEstimatorService.maxDeliveryRadiusKm.toInt(),
                placeLabel: _currentAddress,
              ),
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ),

          if (isLoggedIn) ...[
            LastOrderReorderBanner(onAddedToCart: widget.onReorderToOrders ?? widget.onGoToCart),
            const SupportRepliedBanner(),
          ],

          if (!_hasActiveSearch) ...[
            if (isLoggedIn) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('Following'),
                      selected: _showFollowingOnly,
                      avatar: Icon(
                        _showFollowingOnly ? Icons.storefront : Icons.storefront_outlined,
                        size: 16,
                        color: _showFollowingOnly ? Colors.white : AppTheme.primary,
                      ),
                      selectedColor: AppTheme.primary,
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: _showFollowingOnly ? Colors.white : AppTheme.onSurfaceOf(context),
                      ),
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
                    FilterChip(
                      label: const Text('Favorites'),
                      selected: _showFavoritesOnly,
                      avatar: Icon(
                        _showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
                        size: 16,
                        color: _showFavoritesOnly ? Colors.white : AppTheme.primary,
                      ),
                      selectedColor: AppTheme.primary,
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: _showFavoritesOnly ? Colors.white : AppTheme.onSurfaceOf(context),
                      ),
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
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                childrenPadding: const EdgeInsets.only(bottom: 4),
                initiallyExpanded: false,
                title: Text(
                  'Diet & cuisine',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onSurfaceOf(context),
                  ),
                ),
                children: [
                  _filterChipRow(
                    chips: _dietFilters,
                    selected: _selectedDiet,
                    onSelected: (name) => setState(() => _selectedDiet = name),
                  ),
                  const SizedBox(height: 8),
                  _filterChipRow(
                    chips: _categories,
                    selected: _selectedCategory,
                    onSelected: (name) => setState(() => _selectedCategory = name),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],

          if (!_hasActiveSearch) ..._homeTopHighlights(isLoggedIn: isLoggedIn),

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
                          ? (_filteredChefId != null
                              ? 'Dishes from ${_filteredChefName ?? 'this chef'}'
                              : (_offerBrowseLabel != null
                                  ? '$_offerBrowseLabel offers'
                                  : 'Search results'))
                          : (showFollowing
                              ? 'Kitchens you follow'
                              : (showFavorites ? 'Your favorites' : 'Near you tonight')),
                      style: AppTheme.sectionTitleOf(context),
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
                              : (showFavorites ? 'Meals you loved' : 'Cooked to your slot')),
                      style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                if (_hasActiveSearch)
                  TextButton.icon(
                    onPressed: _clearHomeSearch,
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    label: const Text('Clear', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
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
              _applyFeedChips(_mealsForSelectedAddress(_filterFollowedMeals(
                () {
                  var meals = showFavorites
                      ? _aiSearchResults.where((m) => widget.favoriteMeals.contains(m['id'].toString())).toList()
                      : List<Map<String, dynamic>>.from(_aiSearchResults);
                  final chefId = _filteredChefId;
                  if (chefId != null && chefId.isNotEmpty) {
                    meals = meals.where((m) => m['chef_id']?.toString() == chefId).toList();
                  }
                  return meals;
                }(),
                followedKitchens,
                showFollowing,
              ))),
              isLoggedIn: isLoggedIn,
              showFavorites: showFavorites,
              showFollowing: showFollowing,
              hasFollows: followedKitchens.isNotEmpty,
            ),
          ]
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

                if (showFavorites) {
                  meals = meals.where((m) => widget.favoriteMeals.contains(m['id'].toString())).toList();
                }
                meals = _filterFollowedMeals(meals, followedKitchens, showFollowing);

                meals = _applyFeedChips(_mealsForSelectedAddress(meals));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMealGrid(
                      meals,
                      isLoggedIn: isLoggedIn,
                      showFavorites: showFavorites,
                      showFollowing: showFollowing,
                      hasFollows: followedKitchens.isNotEmpty,
                    ),
                    ..._homeDiscoveryExtras(isLoggedIn: isLoggedIn),
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
    return meals
        .where((meal) => mealMatchesFeedDiet(meal, _selectedDiet) && mealMatchesCuisine(meal, _selectedCategory))
        .toList();
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
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
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
                              fontSize: 11,
                              color: selected ? AppTheme.primary : AppTheme.textMuted,
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

  List<Widget> _homeTopHighlights({required bool isLoggedIn}) {
    return [
      LiveOffersFlashBanner(
        excludedChefIds: _closedChefIds,
        destinationLat: addressCoordinate(_selectedAddressMap, latitude: true),
        destinationLng: addressCoordinate(_selectedAddressMap, latitude: false),
        chefKitchenPins: _chefKitchenPins,
        onOfferTap: _onHomeOfferTap,
      ),
      SponsoredPlacementBanner(
        destinationLat: addressCoordinate(_selectedAddressMap, latitude: true),
        destinationLng: addressCoordinate(_selectedAddressMap, latitude: false),
        cityHint: _selectedAddressMap?['city']?.toString(),
      ),
      ShelfItemsBanner(
        excludedChefIds: _closedChefIds,
        destinationLat: addressCoordinate(_selectedAddressMap, latitude: true),
        destinationLng: addressCoordinate(_selectedAddressMap, latitude: false),
        chefKitchenPins: _chefKitchenPins,
        onItemTap: (meal) => showMealDetailsDialog(context, meal, ref, onGoToCart: widget.onGoToCart),
      ),
      if (isLoggedIn) const DailyStreakBanner(compact: true),
      const SizedBox(height: 4),
    ];
  }

  List<Widget> _homeDiscoveryExtras({required bool isLoggedIn}) {
    return [
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Text(
          'More for you',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.onSurfaceOf(context),
          ),
        ),
      ),
      FestivalHampersBanner(
        excludedChefIds: _closedChefIds,
        destinationLat: addressCoordinate(_selectedAddressMap, latitude: true),
        destinationLng: addressCoordinate(_selectedAddressMap, latitude: false),
        chefKitchenPins: _chefKitchenPins,
        onHamperTap: (meal) => showMealDetailsDialog(context, meal, ref, onGoToCart: widget.onGoToCart),
      ),
      SocietyNightsBanner(
        excludedChefIds: _closedChefIds,
        destinationLat: addressCoordinate(_selectedAddressMap, latitude: true),
        destinationLng: addressCoordinate(_selectedAddressMap, latitude: false),
        destinationAddress: _selectedAddressMap,
        chefKitchenPins: _chefKitchenPins,
        onNightTap: (meal) => showMealDetailsDialog(context, meal, ref, onGoToCart: widget.onGoToCart),
      ),
      if (isLoggedIn) const WeeklyPlanDueBanner(),
      if (isLoggedIn) const AiRecommendationsSection(),
      const DynamicUIEngine(screenName: 'customer_feed'),
    ];
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
            mainAxisExtent: 412,
          ),
          itemCount: meals.length,
          itemBuilder: (context, index) {
            final meal = meals[index];
            final isFavorite = widget.favoriteMeals.contains(meal['id'].toString());

            final isExpired = _checkIfTimePassed(meal['time_slot']?.toString());
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
                decoration: BoxDecoration(
                  color: AppTheme.surfaceOf(context),
                  borderRadius: AppTheme.radiusLg,
                  boxShadow: AppTheme.softShadow,
                ),
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
                                                height: 188,
                                                borderRadius: BorderRadius.zero,
                                              ),
                                            ),
                                            errorWidget: (_, _, _) => const Icon(
                                              Icons.soup_kitchen_outlined,
                                              color: Color(0xFFC4A484),
                                              size: 40,
                                            ),
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
                                        color: Colors.red.shade600, borderRadius: BorderRadius.circular(6)),
                                    child: Text(
                                      PricingCalculator.offerBadgeLabel(meal),
                                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
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
                                      borderRadius: BorderRadius.circular(4)),
                                  child: Icon(
                                    Icons.circle,
                                    color: meal['is_veg'] == true ? AppTheme.veg : AppTheme.nonVeg,
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
                                      MealRatingBadge(meal: meal),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: AppTheme.canvasOf(context),
                                          borderRadius: BorderRadius.circular(8),
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
                                                  fontSize: 11,
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
                                          color: AppTheme.primary,
                                          fontSize: 11,
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
                                              '₹${offerSummary.baseUnitPrice.toInt()}',
                                              style: const TextStyle(
                                                color: AppTheme.textMuted,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                decoration: TextDecoration.lineThrough,
                                              ),
                                            ),
                                          Text(
                                            '₹${offerSummary.effectiveUnitPrice.toInt()}',
                                            style: AppTheme.priceOf(context),
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
                                      onPressed: () => showMealShareSheet(context, meal),
                                    ),
                                    Material(
                                      color: Colors.transparent,
                                      child: Semantics(
                                        button: true,
                                        enabled: isAvailable,
                                        label: isAvailable
                                            ? 'Add ${meal['title'] ?? 'meal'} to cart'
                                            : 'Kitchen closed',
                                        child: InkWell(
                                        borderRadius: AppTheme.radiusMd,
                                        onTap: isAvailable ? () => _handleAddToCart(meal) : null,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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