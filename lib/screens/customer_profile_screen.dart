// lib/screens/customer_profile_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:go_router/go_router.dart';

import 'address_form_screen.dart';
import 'auth_screen.dart';
import 'referral_screen.dart';
import 'customer_order_history_screen.dart';
import '../services/auth_session.dart';
import '../utils/helpers.dart';
import '../utils/legal_content.dart';
import '../utils/support.dart';
import '../widgets/avatar_upload.dart';
import '../widgets/loyalty_badge_card.dart';
import '../widgets/app_widgets.dart';
import '../widgets/change_password_dialog.dart';

class CustomerProfileScreen extends StatefulWidget {
  final VoidCallback? onLogout;

  const CustomerProfileScreen({super.key, this.onLogout});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  final _supabase = Supabase.instance.client;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _allergiesController = TextEditingController();

  String _gender = 'Not Specified';
  String _dietaryPref = 'Vegetarian';

  double _hotpotCoins = 0.0;
  String? _avatarUrl;
  List<Map<String, dynamic>> _addresses = [];
  int _orderCount = 0;
  String _email = '';

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _allergiesController.dispose();
    super.dispose();
  }

  // --- Safe Back Navigation Logic ---

  Future<void> _handleSafeBack() async {
    if (AuthSession.currentUser == null) {
      if (mounted) context.go('/auth');
      return;
    }
    await AuthSession.goToHub(context);
  }

  // --- Data Loading ---

  Future<void> _loadProfileData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      _email = user.email ?? '';

      final futures = await Future.wait([
        _supabase.from('users').select().eq('id', user.id).maybeSingle(),
        _supabase.from('user_addresses').select().eq('user_id', user.id),
        _supabase.from('orders').select('status').eq('customer_id', user.id),
      ].cast<Future<dynamic>>());

      final userData = futures[0] as Map<String, dynamic>?;
      final addressResponse = futures[1] as List<dynamic>;
      final ordersResponse = futures[2] as List<dynamic>;

      if (userData != null && mounted) {
        setState(() {
          _nameController.text = userData['name']?.toString() ?? user.userMetadata?['name']?.toString() ?? 'Valued Customer';
          _phoneController.text = userData['phone']?.toString() ?? user.userMetadata?['phone']?.toString() ?? '';
          _dobController.text = userData['dob']?.toString() ?? '';
          _gender = userData['gender']?.toString() ?? 'Not Specified';
          _dietaryPref = userData['dietary_preference']?.toString() ?? 'Vegetarian';
          _allergiesController.text = userData['allergies']?.toString() ?? '';
          _hotpotCoins = double.tryParse(userData['hotpot_coins']?.toString() ?? '0') ?? 0.0;
          _avatarUrl = userData['avatar_url']?.toString();
        });
      }

      int pastOrdersCount = ordersResponse.where((o) {
        final status = o['status']?.toString().toLowerCase() ?? '';
        return status.contains('delivered') || 
               status.contains('completed') || 
               status.contains('cancelled') || 
               status.contains('rejected');
      }).length;

      if (mounted) {
        setState(() {
          _addresses = List<Map<String, dynamic>>.from(addressResponse);
          _orderCount = pastOrdersCount;
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Customer profile load failure');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Profile Mutation ---

  Future<void> _saveProfileChanges(StateSetter setSheetState) async {
    setSheetState(() => _isSaving = true);
    setState(() => _isSaving = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final newName = _nameController.text.trim();
      final newPhone = _phoneController.text.trim();

      await _supabase.from('users').update({
        'name': newName,
        'phone': newPhone,
        'dob': _dobController.text.trim(),
        'gender': _gender,
        'dietary_preference': _dietaryPref,
        'allergies': _allergiesController.text.trim(),
        if (_avatarUrl != null) 'avatar_url': _avatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);

      await _supabase.auth.updateUser(UserAttributes(data: {'name': newName, 'phone': newPhone}));

      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar('Profile updated successfully! 🎉');
      _loadProfileData();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Profile update failure');
      _showSnackBar('Error updating profile: $e', isError: true);
    } finally {
      if (mounted) {
        setSheetState(() => _isSaving = false);
        setState(() => _isSaving = false);
      }
    }
  }

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
            FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Password change failure');
            rethrow;
          }
        },
      ),
    ).then((ok) {
      if (ok == true) _showSnackBar('Password changed successfully!');
    });
  }

  Future<void> _selectDateOfBirth(BuildContext context, StateSetter setSheetState) async {
    DateTime initialDate = DateTime.now().subtract(const Duration(days: 6570));
    if (_dobController.text.isNotEmpty) {
      try {
        final parts = _dobController.text.split('-');
        if (parts.length == 3) {
          initialDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        }
      } catch (_) {}
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData(
            brightness: isDark ? Brightness.dark : Brightness.light,
            colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              surface: isDark ? AppTheme.surfaceDark : Colors.white,
              onSurface: isDark ? Colors.white : AppTheme.textMain,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      final formattedDate = "${picked.day.toString().padLeft(2, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.year}";
      setSheetState(() => _dobController.text = formattedDate);
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

  // --- Dynamic Input Helpers ---

  Widget _buildSheetTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool enabled = true,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black87,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
        floatingLabelStyle: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
        prefixIcon: Icon(icon, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
      ),
    );
  }

  // --- Modals & Sheets ---

  void _showEditProfileSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Edit Profile & Dietary Info',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.textMain)),
                const SizedBox(height: 20),
                Center(
                  child: AvatarUploadWidget(
                    initialAvatarUrl: _avatarUrl,
                    isEditing: true,
                    onUploadComplete: (newUrl) => setSheetState(() => _avatarUrl = newUrl),
                  ),
                ),
                const SizedBox(height: 20),
                _buildSheetTextField(
                  context: ctx,
                  controller: _nameController,
                  label: 'Full Name',
                  icon: Icons.person,
                ),
                const SizedBox(height: 16),
                _buildSheetTextField(
                  context: ctx,
                  controller: _phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _selectDateOfBirth(context, setSheetState),
                        child: AbsorbPointer(
                          child: _buildSheetTextField(
                            context: ctx,
                            controller: _dobController,
                            label: 'DOB (DD-MM-YYYY)',
                            icon: Icons.calendar_today_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: ['Male', 'Female', 'Other', 'Not Specified'].contains(_gender) ? _gender : 'Not Specified',
                        dropdownColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          labelText: 'Gender',
                          labelStyle: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                          floatingLabelStyle: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
                        ),
                        items: ['Male', 'Female', 'Other', 'Not Specified']
                            .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                            .toList(),
                        onChanged: (val) => setSheetState(() => _gender = val ?? 'Not Specified'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: ['Vegetarian', 'Non-Vegetarian', 'Vegan', 'Jain'].contains(_dietaryPref) ? _dietaryPref : 'Vegetarian',
                  dropdownColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    labelText: 'Dietary Preference',
                    labelStyle: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                    floatingLabelStyle: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                    prefixIcon: Icon(Icons.restaurant_menu, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
                  ),
                  items: ['Vegetarian', 'Non-Vegetarian', 'Vegan', 'Jain']
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (val) => setSheetState(() => _dietaryPref = val ?? 'Vegetarian'),
                ),
                const SizedBox(height: 16),
                _buildSheetTextField(
                  context: ctx,
                  controller: _allergiesController,
                  label: 'Food Allergies (e.g. Peanuts, Gluten)',
                  icon: Icons.warning_amber_rounded,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isSaving ? null : () => _saveProfileChanges(setSheetState),
                  child: _isSaving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Save Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showWalletDialog() {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final user = _supabase.auth.currentUser;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
      title: Row(
        children: [
          const Icon(Icons.account_balance_wallet, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text('HotPot Wallet', style: TextStyle(color: isDark ? Colors.white : AppTheme.textMain)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: AppTheme.radiusLg,
                  boxShadow: AppTheme.brandGlow(opacity: 0.28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Available Balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('₹${_hotpotCoins.toInt()} Value (${_hotpotCoins.toInt()} Coins)',
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('Transaction & Order History', style: TextStyle(color: isDark ? Colors.white : AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              
              // HotPot Coins ledger: credits (earned) and debits (redeemed).
              FutureBuilder<List<Map<String, dynamic>>>(
                future: user != null
                    ? _supabase.from('transactions').select().eq('user_id', user.id).order('created_at', ascending: false).limit(20)
                    : Future.value([]),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)));
                  }

                  final transactions = snapshot.data ?? [];
                  if (transactions.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('No coin activity yet.', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey, fontSize: 13)),
                    );
                  }

                  return Column(
                    children: transactions.map((txn) {
                      final type = txn['transaction_type']?.toString() ?? '';
                      final rawAmount = (txn['amount'] as num?)?.toDouble() ?? 0.0;
                      // Treat known debit types (or an explicit negative amount) as spent.
                      final isDebit = rawAmount < 0 ||
                          RegExp('debit|spent|redeem|used|deduct', caseSensitive: false).hasMatch(type);
                      final coins = rawAmount.abs();
                      final title = (txn['description']?.toString().trim().isNotEmpty ?? false)
                          ? txn['description'].toString()
                          : (type.isNotEmpty ? type : 'Coin Transaction');
                      final date = formatOrderDate(txn['created_at']?.toString());
                      final color = isDebit ? Colors.redAccent : Colors.green;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text(date, style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey, fontSize: 11)),
                                ],
                              ),
                            ),
                            Text('${isDebit ? '-' : '+'}${coins.toInt()} 🪙',
                                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ],
    ),
  );
}

  Widget _buildTxItem(String title, String amount, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)),
          Text(amount, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  void _showAddressesSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Saved Addresses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.textMain)),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16, color: AppTheme.primary),
                    label: const Text('Add New', style: TextStyle(color: AppTheme.primary)),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressFormScreen()));
                      _loadProfileData();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_addresses.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No saved addresses.', style: TextStyle(color: Colors.grey)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: _addresses.map((addr) {
                      final displayStr = "${addr['house_no'] ?? ''}, ${addr['street'] ?? ''}, ${addr['city'] ?? ''}";
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.location_on, color: AppTheme.primary),
                          title: Text(displayStr, style: TextStyle(color: isDark ? Colors.white : AppTheme.textMain, fontSize: 14)),
                          trailing: Icon(Icons.edit, size: 16, color: isDark ? Colors.white70 : Colors.grey),
                          onTap: () async {
                            Navigator.pop(ctx);
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => AddressFormScreen(existingAddress: addr)));
                            _loadProfileData();
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListTile({required IconData icon, required String title, String? subtitle, required VoidCallback onTap, required bool isDark}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppTheme.primary, size: 20),
      ),
      title: Text(title, style: TextStyle(color: isDark ? Colors.white : AppTheme.textMain, fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: isDark ? Colors.grey.shade300 : AppTheme.textMuted, fontSize: 12)) : null,
      trailing: Icon(Icons.chevron_right, color: isDark ? Colors.white70 : Colors.grey, size: 20),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_supabase.auth.currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleSafeBack,
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.asset('assets/app_icon.png', height: 24, width: 24)),
              const SizedBox(width: 8),
              const Text('Account'),
            ],
          ),
        ),
        body: EmptyState(
          icon: Icons.person_outline_rounded,
          title: 'Sign in to manage your account',
          message: 'Save addresses, track HotPot Coins, and keep your dietary preferences in one place.',
          actionLabel: 'Go to Login',
          onAction: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthScreen())),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleSafeBack();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleSafeBack,
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.asset('assets/app_icon.png', height: 24, width: 24)),
              const SizedBox(width: 8),
              const Text('Account'),
            ],
          ),
          centerTitle: true,
          actions: [
            if (widget.onLogout != null)
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.grey),
                onPressed: widget.onLogout,
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          AvatarUploadWidget(
                            initialAvatarUrl: _avatarUrl,
                            isEditing: false,
                            onUploadComplete: (newUrl) {
                              setState(() => _avatarUrl = newUrl);
                            },
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _nameController.text.isEmpty ? 'Valued Customer' : _nameController.text,
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : AppTheme.textMain),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _phoneController.text.isEmpty ? 'Add phone number' : _phoneController.text,
                                  style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade300 : AppTheme.textMuted),
                                ),
                                const SizedBox(height: 2),
                                Text(_email,
                                    style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : AppTheme.textMuted),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: _showEditProfileSheet,
                                  child: const Text('Edit Profile & Dietary Info',
                                      style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const LoyaltyBadgeCard(),

                    _buildListTile(
                      icon: Icons.card_giftcard,
                      title: 'Refer & Earn',
                      subtitle: 'Invite friends and earn HotPot Coins',
                      isDark: isDark,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ReferralScreen()),
                        );
                      },
                    ),
                    Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1, indent: 64),

                    _buildListTile(
                      icon: Icons.tune,
                      title: 'Personalise Your Experience',
                      subtitle: '$_dietaryPref • ${_allergiesController.text.isEmpty ? 'No Allergies Noted' : _allergiesController.text}',
                      isDark: isDark,
                      onTap: _showEditProfileSheet,
                    ),
                    Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1, indent: 64),

                    _buildListTile(
                      icon: Icons.shopping_bag_outlined,
                      title: 'Order History',
                      subtitle: 'Total completed / past orders: $_orderCount',
                      isDark: isDark,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CustomerOrderHistoryScreen()),
                        );
                      },
                    ),
                    Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1, indent: 64),

                    _buildListTile(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'HotPot Wallet',
                      subtitle: 'HotPot Coins Available: ₹${_hotpotCoins.toInt()} (Tap for history)',
                      isDark: isDark,
                      onTap: _showWalletDialog,
                    ),
                    Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1, indent: 64),

                    _buildListTile(
                      icon: Icons.location_on_outlined,
                      title: 'Addresses',
                      subtitle: '${_addresses.length} Saved Addresses',
                      isDark: isDark,
                      onTap: _showAddressesSheet,
                    ),

                    Container(height: 8, color: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade100, margin: const EdgeInsets.symmetric(vertical: 16)),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text('Settings & Help', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.textMain)),
                    ),
                    _buildListTile(icon: Icons.lock_outline, title: 'Change Password', onTap: _showChangePasswordDialog, isDark: isDark),
                    Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1, indent: 64),
                    _buildListTile(
                      icon: Icons.article_outlined,
                      title: 'Terms & conditions',
                      onTap: () => openLegalDocument(context, LegalDocumentType.terms),
                      isDark: isDark,
                    ),
                    Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1, indent: 64),
                    _buildListTile(
                      icon: Icons.help_outline,
                      title: 'FAQs',
                      onTap: () => openLegalDocument(context, LegalDocumentType.faq),
                      isDark: isDark,
                    ),
                    Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1, indent: 64),
                    _buildListTile(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy policy',
                      onTap: () => openLegalDocument(context, LegalDocumentType.privacy),
                      isDark: isDark,
                    ),
                    Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1, indent: 64),
                    _buildListTile(
                      icon: Icons.chat_bubble_outline,
                      title: 'Contact Us',
                      onTap: () => showContactSupportSheet(context),
                      isDark: isDark,
                    ),
                    Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1, indent: 64),
                    _buildListTile(
                      icon: Icons.notifications_none,
                      title: 'Cancellation & Reschedule Policy',
                      onTap: () => openLegalDocument(context, LegalDocumentType.cancellation),
                      isDark: isDark,
                    ),
                    if (SupportConfig.playStoreUrl != null) ...[
                      Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1, indent: 64),
                      _buildListTile(
                        icon: Icons.star_outline,
                        title: 'Rate us on Play Store',
                        onTap: launchPlayStore,
                        isDark: isDark,
                      ),
                    ],

                    if (widget.onLogout != null)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent, width: 1.5),
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: const Icon(Icons.logout),
                          label: const Text('Log Out of Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          onPressed: widget.onLogout,
                        ),
                      ),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Text('App Version: 1.0.0 (Build 12)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}