// lib/screens/chef_publish_meal_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/app_theme.dart';
import '../utils/network.dart';
import '../utils/helpers.dart';
import '../models/cart_enums.dart';
import '../models/pricing_models.dart';
import '../services/reorder_service.dart';

class _AddOnDraft {
  _AddOnDraft({String? id, String title = '', String price = ''})
      : id = id ?? 'addon_${DateTime.now().microsecondsSinceEpoch}',
        title = TextEditingController(text: title),
        price = TextEditingController(text: price);

  final String id;
  final TextEditingController title;
  final TextEditingController price;

  void dispose() {
    title.dispose();
    price.dispose();
  }
}

class ChefPublishMealScreen extends StatefulWidget {
  final Map<String, dynamic>? existingMeal;

  const ChefPublishMealScreen({super.key, this.existingMeal});

  @override
  State<ChefPublishMealScreen> createState() => _ChefPublishMealScreenState();
}

class _ChefPublishMealScreenState extends State<ChefPublishMealScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _quantityController = TextEditingController();
  final _fssaiController = TextEditingController();
  final _hostingAddressController = TextEditingController();

  // Promotions & Discounts
  OfferType _selectedOfferType = OfferType.none;
  final _discountController = TextEditingController();
  final _maxDiscountCapController = TextEditingController();
  final _promoController = TextEditingController();
  bool _acceptsHotpotCoins = true;

  DateTime? _offerEndDate;
  TimeOfDay? _offerEndTime;

  // Media
  XFile? _selectedImageFile;
  String? _existingImageUrl;

  // Meal Specifications
  bool _isLoading = false;
  bool _isVeg = true;
  String _selectedCategory = 'Maharashtrian';
  String _activeTimeSlot = '';

  double? _pickupLat;
  double? _pickupLng;

  final List<String> _categories = const [
    'Maharashtrian',
    'Punjabi',
    'South Indian',
    'North Indian',
    'Snacks',
    'Desserts',
    'Healthy & Salads'
  ];

  final Set<ServiceType> _selectedServices = {ServiceType.deliveryPlatform};
  final List<_AddOnDraft> _addOns = [];

  @override
  void initState() {
    super.initState();
    if (widget.existingMeal != null) {
      _initializeExistingMeal(widget.existingMeal!);
    } else {
      _autoFillChefDetails();
    }
  }

  void _initializeExistingMeal(Map<String, dynamic> meal) {
    _titleController.text = meal['title']?.toString() ?? '';
    _descriptionController.text = meal['description']?.toString() ?? '';
    _priceController.text = meal['price']?.toString() ?? '';
    _quantityController.text = meal['quantity']?.toString() ?? '';
    _fssaiController.text = meal['fssai_number']?.toString() ?? '';
    _hostingAddressController.text = meal['hosting_address']?.toString() ?? '';

    _isVeg = meal['is_veg'] ?? true;
    _selectedCategory = meal['category']?.toString() ?? 'Maharashtrian';
    if (!_categories.contains(_selectedCategory)) {
      _selectedCategory = _categories.first;
    }
    _activeTimeSlot = meal['time_slot']?.toString() ?? '';
    _existingImageUrl = meal['image_url']?.toString();
    _acceptsHotpotCoins = meal['accepts_hotpot_coins'] ?? true;
    _pickupLat = (meal['pickup_lat'] as num?)?.toDouble();
    _pickupLng = (meal['pickup_lng'] as num?)?.toDouble();

    // Offer fields
    final offerStr = meal['offer_type']?.toString() ?? 'none';
    _selectedOfferType = OfferType.values.firstWhere(
      (e) => e.name.toLowerCase() == offerStr.toLowerCase(),
      orElse: () => OfferType.none,
    );
    _discountController.text = meal['discount_value']?.toString() ?? '';
    _maxDiscountCapController.text = meal['max_discount_cap']?.toString() ?? '';
    _promoController.text = meal['promo_code']?.toString() ?? '';

    // Offer validity timestamp
    final validUntilStr = meal['offer_valid_until']?.toString();
    if (validUntilStr != null && validUntilStr.isNotEmpty) {
      final dt = DateTime.tryParse(validUntilStr)?.toLocal();
      if (dt != null) {
        _offerEndDate = dt;
        _offerEndTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
      }
    }

    // Service types
    final rawServices = meal['service_type']?.toString() ?? '';
    _selectedServices.clear();
    for (final part in rawServices.split(',')) {
      if (part.trim().isEmpty) continue;
      _selectedServices.add(ServiceType.fromString(part.trim()));
    }
    if (_selectedServices.isEmpty) {
      _selectedServices.add(ServiceType.deliveryPlatform);
    }

    final existingAddOns = ReorderService.parseMealAddOns(meal['add_ons'] ?? meal['addons']);
    for (final addon in existingAddOns) {
      _addOns.add(_AddOnDraft(
        id: addon.id.isEmpty ? null : addon.id,
        title: addon.title,
        price: addon.price > 0 ? addon.price.toStringAsFixed(0) : '',
      ));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _fssaiController.dispose();
    _hostingAddressController.dispose();
    _discountController.dispose();
    _maxDiscountCapController.dispose();
    _promoController.dispose();
    for (final addon in _addOns) {
      addon.dispose();
    }
    super.dispose();
  }

  // --- Pre-fill Chef Credentials ---

  Future<void> _autoFillChefDetails() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final chefProfile = await _supabase
          .from('users')
          .select('fssai_number, address, lat, lng')
          .eq('id', user.id)
          .maybeSingle();

      if (chefProfile != null && mounted) {
        setState(() {
          _fssaiController.text = chefProfile['fssai_number']?.toString() ?? '';
          _hostingAddressController.text = chefProfile['address']?.toString() ?? '';
          _pickupLat = (chefProfile['lat'] as num?)?.toDouble();
          _pickupLng = (chefProfile['lng'] as num?)?.toDouble();
        });
      }
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'Chef Autofill Error');
    }
  }

  // --- Optimized Image Picker ---

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 80,
    );

    if (pickedFile != null && mounted) {
      setState(() => _selectedImageFile = pickedFile);
    }
  }

  // --- Meal Publication / Update Logic ---

  Future<void> _publishMeal() async {
    if (!_formKey.currentState!.validate()) return;

    if (_activeTimeSlot.isEmpty) {
      _showSnackBar('Please set an availability schedule for this meal.', isError: true);
      return;
    }

    if (_selectedServices.isEmpty) {
      _showSnackBar('Select at least one delivery or dining method.', isError: true);
      return;
    }

    final price = double.tryParse(_priceController.text.trim()) ?? 0.0;
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 0;

    if (price <= 0 || quantity <= 0) {
      _showSnackBar('Price and quantity must both be greater than zero.', isError: true);
      return;
    }

    final fssai = _fssaiController.text.trim();
    final kitchenAddress = _hostingAddressController.text.trim();
    if (fssai.isEmpty || kitchenAddress.isEmpty || _pickupLat == null || _pickupLng == null) {
      _showSnackBar(
        'Save your FSSAI licence, kitchen address, and map pin in Chef Profile before publishing.',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Authentication session expired');

      var chefName = chefDisplayName({
        'name': user.userMetadata?['name'],
        'full_name': user.userMetadata?['full_name'],
        'email': user.email,
      }, fallback: 'Home Kitchen');
      try {
        final profile = await _supabase
            .from('users')
            .select('name, full_name, email')
            .eq('id', user.id)
            .maybeSingle();
        chefName = chefDisplayName(profile, fallback: chefName);
      } catch (_) {}

      String? imageUrl = _existingImageUrl;

      // Direct file stream upload to avoid memory bottlenecks
      if (_selectedImageFile != null) {
        final ext = _selectedImageFile!.name.split('.').last.toLowerCase();
        final path = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';
        final file = File(_selectedImageFile!.path);

        await _supabase.storage.from('meal_images').upload(
              path,
              file,
              fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
            );

        imageUrl = _supabase.storage.from('meal_images').getPublicUrl(path);
      }

      // AI Tagging edge function invocation (non-blocking fallback)
      List<dynamic> healthTags = widget.existingMeal?['health_tags'] ?? [];
      try {
        final aiResponse = await _supabase.functions.invoke(
          'ai-tag-meal',
          body: {
            'title': _titleController.text.trim(),
            'description': _descriptionController.text.trim(),
          },
        ).withTimeout(NetworkTimeouts.payment);
        if (aiResponse.status == 200 && aiResponse.data != null) {
          healthTags = aiResponse.data['tags'] as List<dynamic>? ?? healthTags;
        }
      } catch (aiErr) {
        debugPrint('AI tagging function skipped: $aiErr');
      }

      // Handle Promotion Timestamp Windows
      String? offerExpiryIso;
      if (_selectedOfferType != OfferType.none && _offerEndDate != null) {
        final time = _offerEndTime ?? const TimeOfDay(hour: 23, minute: 59);
        final localExpiry = DateTime(
          _offerEndDate!.year,
          _offerEndDate!.month,
          _offerEndDate!.day,
          time.hour,
          time.minute,
        );

        if (localExpiry.isBefore(DateTime.now())) {
          throw Exception('The promotion expiration date must be in the future.');
        }

        offerExpiryIso = localExpiry.toUtc().toIso8601String();
      }

      final discountVal = double.tryParse(_discountController.text.trim()) ?? 0.0;
      final maxCapVal = double.tryParse(_maxDiscountCapController.text.trim()) ?? 0.0;

      final mealPayload = {
        'chef_id': user.id,
        'chef_name': chefName,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price': price,
        'quantity': quantity,
        'category': _selectedCategory,
        'is_veg': _isVeg,
        'time_slot': _activeTimeSlot,
        'service_type': _selectedServices.map((s) => s.toDisplayString()).join(', '),
        'fssai_number': _fssaiController.text.trim(),
        'hosting_address': _hostingAddressController.text.trim(),
        'pickup_lat': _pickupLat,
        'pickup_lng': _pickupLng,
        'status': widget.existingMeal != null ? (widget.existingMeal!['status'] ?? 'Available') : 'Available',
        'image_url': imageUrl,
        'health_tags': healthTags,
        'offer_type': _selectedOfferType.name,
        'discount_value': discountVal,
        'max_discount_cap': maxCapVal > 0 ? maxCapVal : null,
        'promo_code': _promoController.text.trim().toUpperCase(),
        'accepts_hotpot_coins': _acceptsHotpotCoins,
        'offer_valid_until': offerExpiryIso,
        'add_ons': _addOns
            .where((addon) => addon.title.text.trim().isNotEmpty)
            .map((addon) => {
                  'id': addon.id,
                  'title': addon.title.text.trim(),
                  'price': double.tryParse(addon.price.text.trim()) ?? 0,
                })
            .toList(),
      };

      if (widget.existingMeal != null && widget.existingMeal!['id'] != null) {
        await _supabase
            .from('meals')
            .update(mealPayload)
            .eq('id', widget.existingMeal!['id']);
      } else {
        await _supabase.from('meals').insert(mealPayload);
      }

      if (mounted) {
        _showSnackBar(
          widget.existingMeal != null
              ? 'Meal updated successfully! 🚀'
              : 'Meal published successfully! 🎉',
          isError: false,
        );
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'Meal Publish/Update Failure');
      _showSnackBar('Operation Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  // --- UI Presentation ---

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingMeal != null;

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        title: Text(
          isEditing ? 'Edit Meal' : 'Publish New Meal',
          style: TextStyle(color: AppTheme.onSurfaceOf(context), fontWeight: FontWeight.bold),
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
            // Meal Image Banner
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 190,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                  image: _selectedImageFile != null
                      ? DecorationImage(
                          image: FileImage(File(_selectedImageFile!.path)),
                          fit: BoxFit.cover,
                        )
                      : (_existingImageUrl != null && _existingImageUrl!.isNotEmpty)
                          ? DecorationImage(
                              image: NetworkImage(_existingImageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: _selectedImageFile == null && (_existingImageUrl == null || _existingImageUrl!.isEmpty)
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.add_photo_alternate_outlined, size: 48, color: AppTheme.primary),
                          SizedBox(height: 8),
                          Text('Add Appealing Meal Photo',
                              style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                          Text('JPEG, PNG under 5MB', style: TextStyle(color: Colors.grey, fontSize: 11)),
                        ],
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 24),

            if (isEditing) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Editing published dish',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Update quantity, time slots, delivery options, price, and offers below, then tap Update Meal.',
                      style: TextStyle(fontSize: 12, height: 1.35, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Basics
            const Text('Meal Identity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMain)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleController,
              validator: (v) => v == null || v.trim().isEmpty ? 'Enter the name of your dish' : null,
              decoration: _inputStyle('Dish Name (e.g. Home-style Puran Poli Thali)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              validator: (v) => v == null || v.trim().length < 10 ? 'Describe ingredients and flavor (min 10 chars)' : null,
              decoration: _inputStyle('Description, portion contents & key ingredients'),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                    validator: (v) => v == null || v.isEmpty ? 'Set price' : null,
                    decoration: _inputStyle('Price (₹)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => v == null || v.isEmpty ? 'Set portions' : null,
                    decoration: _inputStyle('Available Portions'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  'Add-ons (optional)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.onSurfaceOf(context)),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _addOns.add(_AddOnDraft())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add extra'),
                ),
              ],
            ),
            Text(
              'Customers can pick these on the dish page. Leave empty if this meal has no extras.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 8),
            ..._addOns.asMap().entries.map((entry) {
              final index = entry.key;
              final addon = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: addon.title,
                        decoration: _inputStyle('Extra name (e.g. Extra raita)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: addon.price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                        decoration: _inputStyle('₹'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove extra',
                      onPressed: () {
                        setState(() {
                          addon.dispose();
                          _addOns.removeAt(index);
                        });
                      },
                      icon: const Icon(Icons.close, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),

            // Category & Veg Filter
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedCategory,
                        isExpanded: true,
                        items: _categories
                            .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 14))))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedCategory = v!),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isVeg ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _isVeg ? Colors.green.shade200 : Colors.red.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.circle, color: _isVeg ? Colors.green : Colors.red, size: 12),
                        const SizedBox(width: 4),
                        Text(_isVeg ? 'Veg' : 'Non-Veg',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _isVeg ? Colors.green : Colors.red)),
                        Switch(
                          value: _isVeg,
                          activeThumbColor: Colors.green,
                          inactiveThumbColor: Colors.red,
                          onChanged: (v) => setState(() => _isVeg = v),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Logistics & Schedule
            const Text('Time slots', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMain)),
            const SizedBox(height: 4),
            const Text(
              'When this dish can be ordered and served.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _activeTimeSlot.isEmpty ? Icons.schedule_outlined : Icons.schedule,
                        size: 18,
                        color: _activeTimeSlot.isEmpty ? AppTheme.textMuted : AppTheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _activeTimeSlot.isEmpty ? 'No time slot assigned yet' : _activeTimeSlot,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _activeTimeSlot.isEmpty ? AppTheme.textMuted : AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.schedule, size: 16, color: AppTheme.primary),
                      label: Text(
                        _activeTimeSlot.isEmpty ? 'Set cooking & serving slot' : 'Change time slot',
                        style: const TextStyle(color: AppTheme.primary),
                      ),
                      onPressed: _openScheduleBuilder,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const Text('Delivery options', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMain)),
            const SizedBox(height: 4),
            const Text(
              'How customers can receive this dish. Select every option you can offer.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: ServiceType.values.map((option) {
                  return CheckboxListTile(
                    dense: true,
                    activeColor: AppTheme.primary,
                    secondary: Icon(_serviceIcon(option), color: AppTheme.primary, size: 22),
                    title: Text(option.toDisplayString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textMain)),
                    subtitle: Text(option.chefHelpText, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    value: _selectedServices.contains(option),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedServices.add(option);
                        } else {
                          _selectedServices.remove(option);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),

            // Pricing Calculator Offer Section
            const Text('Promotions & Discounts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMain)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<OfferType>(
                    value: _selectedOfferType,
                    decoration: _inputStyle('Select Promotion Rule'),
                    items: const [
                      DropdownMenuItem(value: OfferType.none, child: Text('No Offer (Regular Price)')),
                      DropdownMenuItem(value: OfferType.percentage, child: Text('Percentage Discount (%)')),
                      DropdownMenuItem(value: OfferType.flat, child: Text('Flat Rupee Discount (₹)')),
                      DropdownMenuItem(value: OfferType.bogo, child: Text('BOGO (Buy 1 Get 1 Free)')),
                      DropdownMenuItem(value: OfferType.flashSale, child: Text('Flash Sale')),
                    ],
                    onChanged: (val) => setState(() => _selectedOfferType = val ?? OfferType.none),
                  ),

                  if (_selectedOfferType == OfferType.percentage ||
                      _selectedOfferType == OfferType.flat ||
                      _selectedOfferType == OfferType.flashSale) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _discountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _inputStyle(
                        _selectedOfferType == OfferType.percentage || _selectedOfferType == OfferType.flashSale
                            ? 'Discount Percentage (e.g. 25)'
                            : 'Flat Amount per portion (e.g. 40)',
                      ),
                      validator: (v) {
                        if (_selectedOfferType == OfferType.none) return null;
                        final parsed = double.tryParse(v ?? '');
                        if (parsed == null || parsed <= 0) return 'Enter a valid discount';
                        if ((_selectedOfferType == OfferType.percentage || _selectedOfferType == OfferType.flashSale) &&
                            parsed > 90) {
                          return 'Discount cannot exceed 90%';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _maxDiscountCapController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _inputStyle('Max Discount Cap in ₹ (Optional, e.g. 100)'),
                    ),
                  ],

                  if (_selectedOfferType != OfferType.none) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_month, size: 16),
                            label: Text(
                              _offerEndDate == null
                                  ? 'Offer End Date'
                                  : '${_offerEndDate!.day}/${_offerEndDate!.month}/${_offerEndDate!.year}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now().add(const Duration(days: 1)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 90)),
                              );
                              if (picked != null) setState(() => _offerEndDate = picked);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.access_time, size: 16),
                            label: Text(
                              _offerEndTime == null ? 'Offer End Time' : _offerEndTime!.format(context),
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: const TimeOfDay(hour: 23, minute: 59),
                              );
                              if (picked != null) setState(() => _offerEndTime = picked);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppTheme.primary,
                    title: const Text('Accept HotPot Reward Coins', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Customers can use platform coins to discount this dish', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    value: _acceptsHotpotCoins,
                    onChanged: (val) => setState(() => _acceptsHotpotCoins = val),
                  ),
                ],
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
              onPressed: _isLoading ? null : _publishMeal,
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      isEditing ? 'Update Meal' : 'Publish Meal to Menu',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- Schedule Selector Modal ---

  Future<void> _openScheduleBuilder() async {
    final selectedType = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Availability Pattern', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['Daily', 'Specific Days of Week', 'One-Time Date']
              .map(
                (type) => ListTile(
                  title: Text(type, style: const TextStyle(fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.pop(ctx, type),
                ),
              )
              .toList(),
        ),
      ),
    );

    if (selectedType == null || !mounted) return;

    String datePrefix = selectedType;

    if (selectedType == 'Specific Days of Week') {
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final chosen = <String>{};

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Select Days', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            content: Wrap(
              spacing: 8,
              children: days
                  .map((d) => FilterChip(
                        label: Text(d),
                        selected: chosen.contains(d),
                        onSelected: (sel) => setLocal(() => sel ? chosen.add(d) : chosen.remove(d)),
                      ))
                  .toList(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
            ],
          ),
        ),
      );

      if (confirmed != true || chosen.isEmpty) return;
      datePrefix = chosen.join(', ');
    } else if (selectedType == 'One-Time Date') {
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 30)),
      );
      if (picked == null) return;
      datePrefix = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }

    if (!mounted) return;

    final start = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 12, minute: 0), helpText: 'Start Slot');
    if (start == null || !mounted) return;

    final end = await showTimePicker(context: context, initialTime: TimeOfDay(hour: (start.hour + 2) % 24, minute: start.minute), helpText: 'End Slot');
    if (end == null) return;

    final startMins = start.hour * 60 + start.minute;
    final endMins = end.hour * 60 + end.minute;

    if (endMins <= startMins) {
      _showSnackBar('End time must be later than start time', isError: true);
      return;
    }

    setState(() {
      _activeTimeSlot = '$datePrefix (${start.format(context)} to ${end.format(context)})';
    });
  }

  IconData _serviceIcon(ServiceType type) {
    switch (type) {
      case ServiceType.deliveryPlatform:
        return Icons.delivery_dining_rounded;
      case ServiceType.deliverySelf:
        return Icons.two_wheeler_rounded;
      case ServiceType.pickup:
        return Icons.storefront_rounded;
      case ServiceType.dineIn:
        return Icons.restaurant_rounded;
    }
  }

  InputDecoration _inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: Colors.grey),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
    );
  }
}