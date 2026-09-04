// lib/screens/chef_profile_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'map_picker_screen.dart';
import '../utils/app_page.dart';
import '../utils/helpers.dart';
import '../utils/pinned_address.dart';
import '../utils/gst_invoice.dart';
import '../utils/network.dart';
import '../widgets/avatar_upload.dart';
import '../widgets/change_password_dialog.dart';

class ChefReviewModel {
  final String id;
  final int rating;
  final String comment;
  final String customerName;
  final String mealTitle;
  final DateTime createdAt;

  const ChefReviewModel({
    required this.id,
    required this.rating,
    required this.comment,
    required this.customerName,
    required this.mealTitle,
    required this.createdAt,
  });

  factory ChefReviewModel.fromJson(Map<String, dynamic> json) {
    final customerData = json['customer'] as Map<String, dynamic>?;
    final mealData = json['meal'] as Map<String, dynamic>?;

    return ChefReviewModel(
      id: json['id']?.toString() ?? '',
      rating: int.tryParse(json['rating']?.toString() ?? '5') ?? 5,
      comment: json['comment']?.toString() ?? '',
      customerName: customerData?['name'] ?? customerData?['full_name'] ?? 'Verified Customer',
      mealTitle: mealData?['title'] ?? 'Menu Item',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class ChefProfileScreen extends StatefulWidget {
  const ChefProfileScreen({super.key});

  @override
  State<ChefProfileScreen> createState() => _ChefProfileScreenState();
}

class _ChefProfileScreenState extends State<ChefProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSettingUpPayout = false;
  bool _payoutEnabled = false;

  // Controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _fssaiController = TextEditingController();
  final _gstinController = TextEditingController();
  final _gatewayAccountController = TextEditingController();

  final _bankAccountController = TextEditingController();
  final _ifscController = TextEditingController();
  final _beneficiaryNameController = TextEditingController();

  final _houseController = TextEditingController();
  final _streetController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();

  String? _avatarUrl;
  double? _latitude;
  double? _longitude;
  List<ChefReviewModel> _reviews = [];

  // Strict Validation RegEx
  static final _ifscRegex = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final _fssaiRegex = RegExp(r'^[1-2][0-9]{13}$');

  @override
  void initState() {
    super.initState();
    _loadProfileAndReviews();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _fssaiController.dispose();
    _gstinController.dispose();
    _gatewayAccountController.dispose();
    _bankAccountController.dispose();
    _ifscController.dispose();
    _beneficiaryNameController.dispose();
    _houseController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  // --- Profile + reviews load independently so a reviews join cannot blank the form ---

  void _applyUserProfile(Map<String, dynamic>? userData, User user) {
    _nameController.text = userData?['name']?.toString() ??
        userData?['full_name']?.toString() ??
        user.userMetadata?['name']?.toString() ??
        '';
    _phoneController.text = userData?['phone']?.toString() ?? user.userMetadata?['phone']?.toString() ?? '';
    _fssaiController.text = userData?['fssai_number']?.toString() ?? '';
    _gstinController.text = userData?['gstin']?.toString() ?? '';
    _gatewayAccountController.text = userData?['gateway_account_id']?.toString() ?? '';

    _beneficiaryNameController.text = userData?['beneficiary_name']?.toString() ?? '';
    _bankAccountController.text = userData?['bank_account_masked']?.toString() ??
        userData?['bank_account_number']?.toString() ??
        '';
    _ifscController.text = userData?['bank_ifsc']?.toString() ?? '';

    _avatarUrl = userData?['avatar_url']?.toString();
    _payoutEnabled = userData?['payout_enabled'] == true || _gatewayAccountController.text.isNotEmpty;

    _latitude = (userData?['lat'] as num?)?.toDouble() ??
        (userData?['latitude'] as num?)?.toDouble();
    _longitude = (userData?['lng'] as num?)?.toDouble() ??
        (userData?['longitude'] as num?)?.toDouble();

    _houseController.text = userData?['house_no']?.toString() ?? '';
    _streetController.text = userData?['street']?.toString() ?? userData?['address']?.toString() ?? '';
    _cityController.text = userData?['city']?.toString() ?? '';
    _stateController.text = userData?['state']?.toString() ?? '';
    _pincodeController.text = userData?['pincode']?.toString() ?? userData?['postal_code']?.toString() ?? '';
    if (_latitude != null &&
        _longitude != null &&
        (_cityController.text.trim().isEmpty ||
            _stateController.text.trim().isEmpty ||
            _pincodeController.text.trim().isEmpty)) {
      unawaited(_fillAddressFromPin());
    }
  }

  Future<void> _loadProfileAndReviews() async {
    setState(() => _isLoading = true);
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final userData = await _supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle()
          .withTimeout(NetworkTimeouts.standard);
      if (mounted) _applyUserProfile(userData, user);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chef Profile Loading Error');
      if (mounted) _applyUserProfile(null, user);
    }

    List<ChefReviewModel> reviews = [];
    try {
      final rawReviews = await _supabase
          .from('reviews')
          .select('*, customer:users!customer_id(name, full_name), meal:meals(title)')
          .eq('chef_id', user.id)
          .order('created_at', ascending: false)
          .limit(20)
          .withTimeout(NetworkTimeouts.standard);
      reviews = (rawReviews as List<dynamic>)
          .map((r) => ChefReviewModel.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chef reviews loading error');
      try {
        final rawReviews = await _supabase
            .from('reviews')
            .select()
            .eq('chef_id', user.id)
            .order('created_at', ascending: false)
            .limit(20)
            .withTimeout(NetworkTimeouts.standard);
        reviews = (rawReviews as List<dynamic>)
            .map((r) => ChefReviewModel.fromJson(Map<String, dynamic>.from(r)))
            .toList();
      } catch (fallbackError, fallbackStack) {
        FirebaseCrashlytics.instance.recordError(
          fallbackError,
          fallbackStack,
          reason: 'Chef reviews fallback loading error',
        );
      }
    }

    if (mounted) {
      setState(() {
        _reviews = reviews;
        _isLoading = false;
      });
    }
  }

  // --- Secure Server-Side Payout Provisioning ---

  Future<void> _setupChefPayout() async {
    final ifsc = _ifscController.text.trim().toUpperCase();
    final accNum = _bankAccountController.text.trim();
    final beneficiary = _beneficiaryNameController.text.trim();

    if (accNum.isEmpty || ifsc.isEmpty || beneficiary.isEmpty) {
      _showSnackBar('Please provide Beneficiary Name, Account Number, and IFSC Code.', isError: true);
      return;
    }

    if (!_ifscRegex.hasMatch(ifsc)) {
      _showSnackBar('Invalid IFSC Code format (e.g. HDFC0001234)', isError: true);
      return;
    }

    setState(() => _isSettingUpPayout = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw 'User session expired';

      final response = await _supabase.functions.invoke(
        'create-chef-account',
        body: {
          'chef_id': user.id,
          'email': user.email,
          'name': _nameController.text.trim().isEmpty ? beneficiary : _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'bank_account': accNum,
          'ifsc_code': ifsc,
          'beneficiary_name': beneficiary,
        },
      ).withTimeout(NetworkTimeouts.payment);

      if (response.status == 200 && response.data != null && response.data['success'] == true) {
        final pending = response.data['pending'] == true;
        setState(() {
          _payoutEnabled = response.data['payout_enabled'] == true;
          if (response.data['account_id'] != null) {
            _gatewayAccountController.text = response.data['account_id'].toString();
          }
        });
        _showSnackBar(
          pending
              ? 'Bank details saved. Chef settlements start after Razorpay Route is activated on this account.'
              : 'Payout account linked for settlements.',
        );
      } else {
        throw Exception(response.data?['error'] ?? 'Settlement routing rejected');
      }
    } catch (e) {
      _showSnackBar('Payout Setup Failed: ${networkErrorMessage(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _isSettingUpPayout = false);
    }
  }

  // --- Geolocation Map Pinning & Reverse Geocoding ---

  Future<void> _openMapPicker() async {
    if (!_isEditing) return;

    final dynamic result = await Navigator.push(
      context,
      appMaterialRoute(
        MapPickerScreen(
          initialLat: _latitude,
          initialLng: _longitude,
        ),
      ),
    );

    if (result != null) {
      if (result is Map) {
        _latitude = (result['latitude'] as num?)?.toDouble();
        _longitude = (result['longitude'] as num?)?.toDouble();
        _applyPinnedParts(PinnedAddressParts.fromMap(result), overwriteStreet: false);
      } else {
        _latitude = result.latitude;
        _longitude = result.longitude;
      }
      await _fillAddressFromPin();
      if (mounted) {
        _showSnackBar('Location pin attached and address details auto-filled!');
      }
    }
  }

  void _applyPinnedParts(PinnedAddressParts parts, {bool overwriteStreet = false}) {
    if (!mounted) return;
    setState(() {
      if (parts.street.isNotEmpty && (overwriteStreet || _streetController.text.trim().isEmpty)) {
        _streetController.text = parts.street;
      }
      if (parts.city.isNotEmpty) _cityController.text = parts.city;
      if (parts.state.isNotEmpty) _stateController.text = parts.state;
      if (parts.pincode.isNotEmpty) _pincodeController.text = parts.pincode;
    });
  }

  Future<void> _fillAddressFromPin() async {
    if (_latitude == null || _longitude == null) return;
    if (_cityController.text.trim().isNotEmpty &&
        _stateController.text.trim().isNotEmpty &&
        _pincodeController.text.trim().isNotEmpty) {
      return;
    }
    try {
      final parts = await reverseGeocodeLatLng(_latitude!, _longitude!);
      _applyPinnedParts(parts);
    } catch (e) {
      debugPrint('Geocoding failed: $e');
    }
  }

  // --- Profile Submission with Validation ---

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (_latitude == null || _longitude == null) {
      _showSnackBar('Please pin your kitchen location on the map.', isError: true);
      return;
    }

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final fssai = _fssaiController.text.trim();
    final house = _houseController.text.trim();
    final street = _streetController.text.trim();
    final city = _cityController.text.trim();
    final state = _stateController.text.trim();
    final pin = _pincodeController.text.trim();

    final formattedAddress = "$house, $street, $city, $state - $pin".trim();

    setState(() => _isSaving = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw 'Session expired';

      final updateData = {
        'id': user.id,
        'name': name,
        'full_name': name,
        'phone': phone,
        'fssai_number': fssai,
        'gstin': _gstinController.text.trim().toUpperCase(),
        'address': formattedAddress,
        'house_no': house,
        'street': street,
        'city': city,
        'state': state,
        'pincode': pin,
        'lat': _latitude,
        'lng': _longitude,
        'latitude': _latitude,
        'longitude': _longitude,
        if (_avatarUrl != null) 'avatar_url': _avatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _supabase.from('users').upsert(updateData);
      await _supabase.auth.updateUser(UserAttributes(data: {'name': name, 'phone': phone}));
      try {
        await _supabase
            .from('meals')
            .update(kitchenPinMealFields(_latitude!, _longitude!))
            .eq('chef_id', user.id);
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chef kitchen pin meal sync failed');
      }

      if (mounted) {
        setState(() => _isEditing = false);
        _showSnackBar('Profile details saved successfully!');
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chef Profile Save Failure');
      _showSnackBar('Failed to update profile: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- Secure Password Update ---

  void _showChangePasswordDialog() {
    showDialog<bool>(
      context: context,
      builder: (ctx) => ChangePasswordDialog(
        onSubmit: ({required currentPassword, required newPassword}) async {
          final user = _supabase.auth.currentUser;
          if (user == null || user.email == null) {
            throw Exception('Not logged in');
          }
          try {
            await _supabase.auth.signInWithPassword(
              email: user.email!,
              password: currentPassword,
            );
            await _supabase.auth.updateUser(UserAttributes(password: newPassword));
          } catch (e, stack) {
            FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chef password change failure');
            rethrow;
          }
        },
      ),
    ).then((ok) {
      if (ok == true) _showSnackBar('Password updated successfully!');
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- UI Layout ---

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final email = user?.email ?? 'No Email';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.background;
    final surface = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final titleColor = isDark ? AppTheme.textMainDark : AppTheme.textMain;
    final muted = isDark ? Colors.grey.shade400 : AppTheme.textMuted;
    final divider = isDark ? Colors.white24 : Colors.black12;
    final verified = isDark ? Colors.greenAccent : Colors.green.shade700;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('Chef Profile & Settings', style: TextStyle(color: titleColor, fontWeight: FontWeight.bold)),
        backgroundColor: surface,
        elevation: 0,
        iconTheme: IconThemeData(color: titleColor),
        actions: [
          TextButton.icon(
            icon: Icon(_isEditing ? Icons.close : Icons.edit, color: AppTheme.primary, size: 18),
            label: Text(_isEditing ? 'Cancel' : 'Edit', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
            onPressed: () => setState(() => _isEditing = !_isEditing),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Profile Identity Header Card
                  Card(
                    color: surface,
                    elevation: isDark ? 0 : 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          AvatarUploadWidget(
                            initialAvatarUrl: _avatarUrl,
                            isEditing: _isEditing,
                            onUploadComplete: (newUrl) => setState(() => _avatarUrl = newUrl),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _nameController.text.isEmpty ? 'Home Kitchen Partner' : _nameController.text,
                                  style: TextStyle(color: titleColor, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(email, style: TextStyle(color: muted, fontSize: 13)),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _fssaiController.text.trim().isEmpty
                                        ? 'FSSAI not on file'
                                        : 'FSSAI listed',
                                    style: TextStyle(color: verified, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Personal Information Section
                  const Text('Kitchen & Business Credentials',
                      style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  _buildValidatedTextField(
                    controller: _nameController,
                    label: 'Kitchen / Display Name *',
                    prefixIcon: Icons.restaurant,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildValidatedTextField(
                    controller: _phoneController,
                    label: 'Primary Phone Number *',
                    prefixIcon: Icons.phone,
                    keyboardType: TextInputType.phone,
                    validator: (v) => v == null || v.trim().length < 10 ? 'Enter valid 10-digit number' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildValidatedTextField(
                    controller: _fssaiController,
                    label: '14-Digit FSSAI License Number *',
                    prefixIcon: Icons.verified_user_outlined,
                    keyboardType: TextInputType.number,
                    maxLength: 14,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'FSSAI License is legally mandatory';
                      if (!_fssaiRegex.hasMatch(v)) return 'Invalid 14-digit FSSAI format (Starts with 1 or 2)';
                      return null;
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => launchUrl(Uri.parse('https://foscos.fssai.gov.in/'), mode: LaunchMode.externalApplication),
                      child: const Text('Apply or Verify FSSAI License ↗',
                          style: TextStyle(color: Colors.blueAccent, fontSize: 12, decoration: TextDecoration.underline)),
                    ),
                  ),
                  _buildValidatedTextField(
                    controller: _gstinController,
                    label: 'GSTIN (for tax invoices)',
                    prefixIcon: Icons.receipt_long_outlined,
                    maxLength: 15,
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (value.isEmpty) return null;
                      if (!isValidGstin(value)) return 'Enter a valid 15-character GSTIN';
                      return null;
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      'Leave blank if you are not GST-registered. Customers then get a bill of supply.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ),
                  Divider(height: 32, color: divider),

                  // Kitchen Dispatch Address Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Kitchen Pickup Address',
                          style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 15)),
                      Row(
                        children: [
                          Icon(_latitude != null ? Icons.check_circle : Icons.warning_amber_rounded,
                              size: 14, color: _latitude != null ? Colors.green : Colors.orange),
                          const SizedBox(width: 4),
                          Text(
                            _latitude != null ? 'Coordinates Pinned' : 'Coordinates Missing',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _latitude != null ? Colors.green : Colors.orange),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Drivers navigate to these coordinates for food collection.', style: TextStyle(color: muted, fontSize: 12)),
                  const SizedBox(height: 12),

                  if (_isEditing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: _latitude == null ? AppTheme.primary : Colors.green),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: Icon(Icons.pin_drop, color: _latitude == null ? AppTheme.primary : Colors.green),
                          label: Text(
                            _latitude == null ? 'Pin Exact Kitchen on Map *' : 'Location Pinned (Tap to update)',
                            style: TextStyle(fontWeight: FontWeight.bold, color: _latitude == null ? AppTheme.primary : Colors.green),
                          ),
                          onPressed: _openMapPicker,
                        ),
                      ),
                    ),

                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildValidatedTextField(controller: _houseController, label: 'House / Unit No.'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: _buildValidatedTextField(
                          controller: _cityController,
                          label: 'City *',
                          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildValidatedTextField(
                    controller: _streetController,
                    label: 'Street / Landmark / Colony *',
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildValidatedTextField(
                          controller: _stateController,
                          label: 'State *',
                          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildValidatedTextField(
                          controller: _pincodeController,
                          label: 'PIN Code *',
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          validator: (v) => v == null || v.trim().length != 6 ? '6-digit PIN' : null,
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 36, color: divider),

                  // Automated Settlements & Payout Section
                  const Text('Automated Bank Payout Routing',
                      style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  Card(
                    color: surface,
                    elevation: isDark ? 0 : 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              _payoutEnabled ? Icons.account_balance_wallet : Icons.account_balance,
                              color: _payoutEnabled ? Colors.green : Colors.orange,
                            ),
                            title: Text(
                              _payoutEnabled ? 'Direct Settlement Active' : 'Configure Settlement Account',
                              style: TextStyle(color: titleColor, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              _payoutEnabled
                                  ? 'Earnings settle automatically to your registered account.'
                                  : 'Required for automated split payouts via Razorpay Route.',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                            trailing: _payoutEnabled
                                ? const Chip(backgroundColor: Colors.green, label: Text('Active', style: TextStyle(color: Colors.white, fontSize: 11)))
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                                    onPressed: _isSettingUpPayout ? null : _setupChefPayout,
                                    child: _isSettingUpPayout
                                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                        : const Text('Link', style: TextStyle(color: Colors.white, fontSize: 12)),
                                  ),
                          ),
                          Divider(color: divider.withValues(alpha: 0.5)),
                          _buildValidatedTextField(controller: _beneficiaryNameController, label: 'Account Holder Name'),
                          const SizedBox(height: 10),
                          _buildValidatedTextField(controller: _bankAccountController, label: 'Bank Account Number', keyboardType: TextInputType.number),
                          const SizedBox(height: 10),
                          _buildValidatedTextField(
                            controller: _ifscController,
                            label: 'Bank IFSC Code',
                            maxLength: 11,
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Account Security Card
                  Card(
                    color: surface,
                    elevation: isDark ? 0 : 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: Icon(Icons.security, color: muted),
                      title: Text('Security & Credentials', style: TextStyle(color: titleColor, fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: Text('Update login password', style: TextStyle(color: muted, fontSize: 12)),
                      trailing: Icon(Icons.chevron_right, color: muted),
                      onTap: _showChangePasswordDialog,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Customer Reviews Section
                  const Text('Customer Reviews & Ratings',
                      style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  if (_reviews.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: Text('No reviews received yet.', style: TextStyle(color: muted, fontSize: 13))),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _reviews.length,
                      itemBuilder: (context, index) {
                        final rev = _reviews[index];
                        return Card(
                          color: surface,
                          elevation: isDark ? 0 : 1,
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: List.generate(
                                        5,
                                        (i) => Icon(i < rev.rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 15),
                                      ),
                                    ),
                                    Text(formatOrderDate(rev.createdAt.toIso8601String()), style: TextStyle(color: muted, fontSize: 11)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('Dish: ${rev.mealTitle}',
                                    style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(rev.customerName, style: TextStyle(color: titleColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                if (rev.comment.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('"${rev.comment}"', style: TextStyle(color: muted, fontSize: 12, fontStyle: FontStyle.italic)),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 24),

                  if (_isEditing)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.save_outlined),
                      label: _isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Save Profile Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      onPressed: _isSaving ? null : _saveProfile,
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildValidatedTextField({
    required TextEditingController controller,
    required String label,
    IconData? prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppTheme.textMainDark : AppTheme.textMain;
    final muted = isDark ? Colors.grey.shade400 : AppTheme.textMuted;
    final fill = isDark ? AppTheme.surfaceMutedDark : Colors.white;
    final border = isDark ? Colors.white12 : Colors.grey.shade300;

    return TextFormField(
      controller: controller,
      readOnly: !_isEditing,
      enableInteractiveSelection: true,
      keyboardType: keyboardType,
      maxLength: maxLength,
      validator: validator,
      inputFormatters: inputFormatters,
      style: TextStyle(color: titleColor, fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: muted, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.bold),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: AppTheme.primary, size: 20) : null,
        filled: true,
        fillColor: fill,
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.redAccent)),
      ),
    );
  }
}