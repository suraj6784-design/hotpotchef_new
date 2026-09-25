// lib/screens/customer_bulk_request_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../models/cart_enums.dart';
import '../providers/cart_provider.dart';
import '../services/meal_catalog_repository.dart';
import '../utils/helpers.dart';
import '../utils/network.dart';
import '../widgets/app_widgets.dart';
import 'map_picker_screen.dart';

class CustomerBulkRequestScreen extends ConsumerStatefulWidget {
  const CustomerBulkRequestScreen({super.key});

  @override
  ConsumerState<CustomerBulkRequestScreen> createState() => _CustomerBulkRequestScreenState();
}

class _CustomerBulkRequestScreenState extends ConsumerState<CustomerBulkRequestScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _qtyController = TextEditingController(text: '10');
  final _addressController = TextEditingController();
  final _chefSearchController = TextEditingController();

  String _selectedServiceType = 'Delivery Partner';
  DateTime _targetDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _targetTime = const TimeOfDay(hour: 13, minute: 0);
  bool _isLoading = false;
  bool _chefsLoading = false;
  bool _mealsLoading = false;
  String? _selectedMealId;
  List<Map<String, dynamic>> _chefMeals = const [];
  String? _chefsError;
  List<_BulkChefOption> _chefs = const [];
  final Set<String> _selectedChefIds = <String>{};

  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _loadChefs();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _qtyController.dispose();
    _addressController.dispose();
    _chefSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadChefs() async {
    setState(() {
      _chefsLoading = true;
      _chefsError = null;
    });
    try {
      final kitchens = await _supabase
          .from('chef_profiles')
          .select('user_id, local_kitchen_name, is_open')
          .limit(250)
          .withTimeout(NetworkTimeouts.standard);
      final kitchenRows = List<Map<String, dynamic>>.from(kitchens as List);
      final kitchenNames = <String, String>{};
      final kitchenOpen = <String, bool>{};
      for (final row in kitchenRows) {
        final id = row['user_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        kitchenNames[id] = row['local_kitchen_name']?.toString().trim() ?? '';
        kitchenOpen[id] = row['is_open'] != false;
      }

      var userRows = <Map<String, dynamic>>[];
      try {
        final users = await _supabase
            .from('users')
            .select('id, name, full_name, city, role')
            .inFilter('role', kStoredChefRoles)
            .limit(250)
            .withTimeout(NetworkTimeouts.standard);
        userRows = List<Map<String, dynamic>>.from(users as List);
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Bulk chef list users query');
        if (kitchenNames.isNotEmpty) {
          final extra = await _supabase
              .from('users')
              .select('id, name, full_name, city, role')
              .inFilter('id', kitchenNames.keys.toList())
              .inFilter('role', kStoredChefRoles)
              .withTimeout(NetworkTimeouts.standard);
          userRows = List<Map<String, dynamic>>.from(extra as List);
        }
      }

      final followed = <String>{};
      try {
        final uid = _supabase.auth.currentUser?.id;
        if (uid != null) {
          final follows = await _supabase
              .from('kitchen_follows')
              .select('chef_id')
              .eq('customer_id', uid)
              .withTimeout(NetworkTimeouts.short);
          for (final row in List<Map<String, dynamic>>.from(follows as List)) {
            final id = row['chef_id']?.toString() ?? '';
            if (id.isNotEmpty) followed.add(id);
          }
        }
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Bulk chef follows query');
      }

      final byId = <String, _BulkChefOption>{};
      for (final row in userRows) {
        if (!isChefAccount(row)) continue;
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final kitchen = kitchenNames[id] ?? '';
        final name = chefDisplayName(
          {...row, if (kitchen.isNotEmpty) 'kitchen_name': kitchen},
          fallback: kitchen.isNotEmpty ? kitchen : 'Home kitchen',
        );
        byId[id] = _BulkChefOption(
          id: id,
          name: name,
          kitchen: kitchen,
          city: row['city']?.toString().trim() ?? '',
          followed: followed.contains(id),
          isOpen: kitchenOpen[id] ?? true,
        );
      }
      final list = byId.values.toList()
        ..sort((a, b) {
          if (a.followed != b.followed) return a.followed ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

      if (!mounted) return;
      setState(() {
        _chefs = list;
        _chefsLoading = false;
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Bulk chef list failed');
      if (!mounted) return;
      setState(() {
        _chefsLoading = false;
        _chefsError = 'Could not load kitchens. Pull to try again.';
      });
    }
  }

  List<_BulkChefOption> get _filteredChefs {
    final q = _chefSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return _chefs;
    return _chefs.where((chef) {
      return chef.name.toLowerCase().contains(q) ||
          chef.kitchen.toLowerCase().contains(q) ||
          chef.city.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _loadChefMeals(String chefId) async {
    setState(() {
      _mealsLoading = true;
      _chefMeals = const [];
      _selectedMealId = null;
    });
    try {
      final rows = await MealCatalogRepository(_supabase).availableMeals(chefId: chefId, limit: 40);
      final meals = rows.where((meal) {
        final status = meal['status']?.toString().toLowerCase() ?? '';
        final qty = int.tryParse(meal['quantity']?.toString() ?? '') ?? 0;
        return qty >= 5 && status != 'paused' && status != 'cancelled';
      }).toList();
      if (!mounted) return;
      setState(() {
        _chefMeals = meals;
        _mealsLoading = false;
        if (meals.length == 1) _selectedMealId = meals.first['id']?.toString();
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Bulk chef meals');
      if (!mounted) return;
      setState(() => _mealsLoading = false);
      _showSnackBar('Could not load this kitchen\'s plates.', isError: true);
    }
  }

  Future<void> _addBulkToCart() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedChefIds.length != 1) {
      _showSnackBar('Choose one kitchen. A bulk plate pays through the cart.', isError: true);
      return;
    }
    Map<String, dynamic>? meal;
    for (final row in _chefMeals) {
      if (row['id']?.toString() == _selectedMealId) meal = row;
    }
    if (meal == null) {
      _showSnackBar('Choose the plate to order.', isError: true);
      return;
    }
    final quantity = int.tryParse(_qtyController.text.trim()) ?? 0;
    if (quantity < 5) {
      _showSnackBar('Bulk pre-orders require a minimum of 5 portions.', isError: true);
      return;
    }
    final stock = int.tryParse(meal['quantity']?.toString() ?? '') ?? 0;
    if (quantity > stock) {
      _showSnackBar('This plate has $stock portions listed.', isError: true);
      return;
    }
    final now = DateTime.now();
    final earliest = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final scheduled = DateTime(_targetDate.year, _targetDate.month, _targetDate.day);
    if (scheduled.isBefore(earliest)) {
      _showSnackBar('Bulk orders need at least one day of lead time.', isError: true);
      return;
    }
    if (_latitude == null || _longitude == null) {
      _showSnackBar('Please pin the drop on the map.', isError: true);
      return;
    }
    if (_supabase.auth.currentUser == null) {
      _showSnackBar('Sign in to pay for a bulk plate.', isError: true);
      return;
    }

    final note = [
      _titleController.text.trim(),
      _descController.text.trim(),
      'Drop: ${_addressController.text.trim()}',
    ].where((part) => part.isNotEmpty).join('\n');

    final added = ref.read(cartProvider.notifier).addToCart(
          meal,
          quantity,
          clearIfVendorConflict: true,
          scheduledDate: scheduled,
          timeSlot: _targetTime.format(context),
          specialInstructions: note,
          serviceType: ServiceType.fromString(_selectedServiceType),
        );
    if (!added || !mounted) {
      _showSnackBar('Could not add this plate. Clear the cart and try again.', isError: true);
      return;
    }
    context.go('/customer-hub?tab=cart');
  }

  void _showSnackBar(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        title: Row(
          children: [
            const AppLogo(size: 24),
            const SizedBox(width: 8),
            Text('Bulk pre-order', style: TextStyle(color: AppTheme.onSurfaceOf(context), fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.primary),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Pick one kitchen and a plate. Quantity and lead time go on the same cart, then you pay. The chef sees it with other orders.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),

            TextFormField(
              controller: _titleController,
              decoration: _inputStyle('Note for the kitchen (optional)'),
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: _descController,
              maxLines: 3,
              decoration: _inputStyle('Dietary notes, spice levels, or packaging preferences'),
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _qtyController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      final val = int.tryParse(v ?? '') ?? 0;
                      if (val < 5) return 'Minimum 5 portions';
                      return null;
                    },
                    decoration: _inputStyle('Total Portions *'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.calendar_month, size: 16, color: AppTheme.primary),
                    label: Text(formatFriendlyDate(_targetDate), style: TextStyle(fontSize: 13, color: AppTheme.onSurfaceOf(context))),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _targetDate,
                        firstDate: DateTime.now().add(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 90)),
                      );
                      if (picked != null) setState(() => _targetDate = picked);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.access_time, size: 16, color: AppTheme.primary),
                    label: Text(_targetTime.format(context), style: TextStyle(fontSize: 13, color: AppTheme.onSurfaceOf(context))),
                    onPressed: () async {
                      final picked = await showTimePicker(context: context, initialTime: _targetTime);
                      if (picked != null) setState(() => _targetTime = picked);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _selectedServiceType,
              dropdownColor: AppTheme.surfaceOf(context),
              style: TextStyle(fontSize: 14, color: AppTheme.onSurfaceOf(context)),
              decoration: _inputStyle('Fulfillment Type'),
              items: ['Delivery Partner', 'Chef-Self', 'Customer Pickup', 'Dine In']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 14))))
                  .toList(),
              onChanged: (val) => setState(() => _selectedServiceType = val!),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _addressController,
              validator: (v) => v == null || v.trim().isEmpty ? 'Delivery or venue address required' : null,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Delivery / Event Address *',
                labelStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surfaceOf(context),
                prefixIcon: const Icon(Icons.location_on, color: AppTheme.primary),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.map, color: AppTheme.primary),
                  tooltip: 'Pin on Map',
                  onPressed: () async {
                    final result = await Navigator.push<Map<String, dynamic>?>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapPickerScreen(initialLat: _latitude, initialLng: _longitude),
                      ),
                    );
                    if (result != null && mounted) {
                      setState(() {
                        _addressController.text = result['address']?.toString() ?? '';
                        _latitude = (result['latitude'] as num?)?.toDouble();
                        _longitude = (result['longitude'] as num?)?.toDouble();
                      });
                    }
                  },
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.hairlineOf(context))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Kitchen',
              style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.onSurfaceOf(context)),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 4),
              TextField(
                controller: _chefSearchController,
                onChanged: (_) => setState(() {}),
                decoration: _inputStyle('Search kitchen or chef').copyWith(
                  prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                ),
              ),
              const SizedBox(height: 8),
              if (_chefsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_chefsError != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_chefsError!, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                    IconButton(
                      tooltip: 'Retry',
                      onPressed: _loadChefs,
                      icon: const Icon(Icons.refresh, color: AppTheme.primary),
                    ),
                  ],
                )
              else if (_filteredChefs.isEmpty)
                const Text(
                  'No kitchens match that search yet.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceOf(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.hairlineOf(context)),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _filteredChefs.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.hairlineOf(context)),
                    itemBuilder: (context, index) {
                      final chef = _filteredChefs[index];
                      final subtitleParts = [
                        if (chef.kitchen.isNotEmpty && chef.kitchen != chef.name) chef.kitchen,
                        if (chef.city.isNotEmpty) chef.city,
                        if (chef.followed) 'Following',
                        if (!chef.isOpen) 'Currently offline',
                      ];
                      return RadioListTile<String>(
                        value: chef.id,
                        groupValue: _selectedChefIds.isEmpty ? null : _selectedChefIds.first,
                        dense: true,
                        activeColor: AppTheme.primary,
                        title: Text(chef.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: subtitleParts.isEmpty
                            ? null
                            : Text(subtitleParts.join(' · '), style: AppTheme.caption),
                        onChanged: (_) {
                          setState(() {
                            _selectedChefIds
                              ..clear()
                              ..add(chef.id);
                          });
                          _loadChefMeals(chef.id);
                        },
                      );
                    },
                  ),
                ),
              if (_mealsLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_selectedChefIds.isNotEmpty && _chefMeals.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'This kitchen has no plate with at least 5 portions listed.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                )
              else if (_chefMeals.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: DropdownButtonFormField<String>(
                    initialValue: _chefMeals.any((meal) => meal['id']?.toString() == _selectedMealId)
                        ? _selectedMealId
                        : null,
                    decoration: _inputStyle('Plate'),
                    items: [
                      for (final meal in _chefMeals)
                        DropdownMenuItem(
                          value: meal['id']?.toString(),
                          child: Text(
                            '${meal['title'] ?? 'Plate'} · ₹${meal['price'] ?? ''} · ${meal['quantity']} left',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) => setState(() => _selectedMealId = id),
                  ),
                ),
            const SizedBox(height: 32),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isLoading ? null : _addBulkToCart,
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Add to cart', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
      filled: true,
      fillColor: AppTheme.surfaceOf(context),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.hairlineOf(context))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
    );
  }
}

class _BulkChefOption {
  const _BulkChefOption({
    required this.id,
    required this.name,
    required this.kitchen,
    required this.city,
    required this.followed,
    required this.isOpen,
  });

  final String id;
  final String name;
  final String kitchen;
  final String city;
  final bool followed;
  final bool isOpen;
}
