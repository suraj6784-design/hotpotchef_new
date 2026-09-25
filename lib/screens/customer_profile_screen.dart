// lib/screens/customer_profile_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:go_router/go_router.dart';

import 'address_form_screen.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/kitchen_follows_provider.dart';
import '../providers/last_order_provider.dart';
import '../providers/meal_plans_provider.dart';
import '../services/auth_session.dart';
import '../services/ticket_reply_seen_store.dart';
import '../utils/diner_locale.dart';
import '../utils/helpers.dart';
import '../utils/network.dart';
import '../utils/legal_content.dart';
import '../utils/payment_preferences.dart';
import '../utils/support.dart';
import '../widgets/avatar_upload.dart';
import '../widgets/loyalty_badge_card.dart';
import '../widgets/app_widgets.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/premium_profile_template.dart';
import '../widgets/customer_ui_components.dart';

class CustomerProfileScreen extends ConsumerStatefulWidget {
  final VoidCallback? onLogout;
  final bool embedded;

  const CustomerProfileScreen({super.key, this.onLogout, this.embedded = false});

  @override
  ConsumerState<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends ConsumerState<CustomerProfileScreen> {
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
  String _email = '';
  String _preferredPayMethod = 'upi';
  String? _savedVpa;
  String _supportTicketsSubtitle = 'Track replies and open conversations';
  String _accountStatus = 'active';

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isPlatformOps = false;
  int _loadSeq = 0;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfileData());
    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.session == null) {
        setState(() => _isLoading = false);
        return;
      }
      if (data.event == AuthChangeEvent.signedIn || data.event == AuthChangeEvent.initialSession) {
        unawaited(_loadProfileData());
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _allergiesController.dispose();
    super.dispose();
  }

  // --- Safe Back Navigation Logic ---

  Future<void> _handleSafeBack() async {
    if (widget.embedded) return;
    if (AuthSession.currentUser == null) {
      if (mounted) context.go('/auth');
      return;
    }
    await AuthSession.goToHub(context);
  }

  Future<void> _handleLogout() async {
    if (widget.onLogout != null) {
      widget.onLogout!();
      return;
    }
    await AuthSession.confirmSignOut(context, beforeNavigate: () async {
      ref.read(cartProvider.notifier).clearCart();
      ref.invalidate(favoritesProvider);
      ref.invalidate(kitchenFollowsProvider);
      ref.invalidate(lastOrderProvider);
      ref.invalidate(mealPlansProvider);
    });
  }

  // --- Data Loading ---

  Future<void> _loadProfileData() async {
    final seq = ++_loadSeq;
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted && seq == _loadSeq) setState(() => _isLoading = false);
        return;
      }

      if (mounted && seq == _loadSeq) setState(() => _isLoading = true);
      _email = user.email ?? '';

      final futures = await Future.wait<dynamic>([
        _supabase
            .from('users')
            .select('name, phone, dob, gender, dietary_preference, allergies, hotpot_coins, avatar_url, account_status')
            .eq('id', user.id)
            .maybeSingle(),
        _supabase.from('user_addresses').select().eq('user_id', user.id),
      ]).withTimeout(NetworkTimeouts.standard);

      final userData = futures[0] as Map<String, dynamic>?;
      final addressResponse = futures[1] as List<dynamic>;

      if (userData != null && mounted && seq == _loadSeq) {
        setState(() {
          _nameController.text = userData['name']?.toString() ?? user.userMetadata?['name']?.toString() ?? 'Valued Customer';
          _phoneController.text = userData['phone']?.toString() ?? user.userMetadata?['phone']?.toString() ?? '';
          _dobController.text = userData['dob']?.toString() ?? '';
          _gender = userData['gender']?.toString() ?? 'Not Specified';
          _dietaryPref = userData['dietary_preference']?.toString() ?? 'Vegetarian';
          _allergiesController.text = userData['allergies']?.toString() ?? '';
          _hotpotCoins = double.tryParse(userData['hotpot_coins']?.toString() ?? '0') ?? 0.0;
          _avatarUrl = userData['avatar_url']?.toString();
          _accountStatus = normalizeAccountStatus(userData['account_status']?.toString());
        });
      }

      final preferredPay = await loadPreferredPaymentMethod();
      final savedVpa = await loadSavedVpa();
      var ops = false;
      try {
        ops = await AuthSession.isPlatformOps().withTimeout(NetworkTimeouts.short);
      } catch (_) {}
      var ticketsSubtitle = 'Track replies and open conversations';
      try {
        final ticketRows = await _supabase
            .from('support_tickets')
            .select('id, public_id, status, last_message_at')
            .eq('created_by', user.id)
            .eq('status', 'pending_customer')
            .order('last_message_at', ascending: false)
            .limit(8)
            .withTimeout(NetworkTimeouts.short);
        final tickets = List<Map<String, dynamic>>.from(ticketRows as List);
        final seen = await TicketReplySeenStore.lastSeenByTicket(
          tickets.map((row) => row['id']?.toString() ?? ''),
        );
        final waiting = tickets.where((row) {
          final id = row['id']?.toString() ?? '';
          return dinerHasSupportReplyWaiting(
            status: row['status']?.toString(),
            lastMessageAt: row['last_message_at']?.toString(),
            lastSeenMessageAt: seen[id],
          );
        }).toList();
        if (waiting.isNotEmpty) {
          ticketsSubtitle = supportRepliedNoticeCopy(
            publicId: waiting.first['public_id']?.toString(),
            extraCount: waiting.length - 1,
          );
        }
      } catch (_) {}

      if (mounted && seq == _loadSeq) {
        setState(() {
          _addresses = uniqueSavedAddresses(List<Map<String, dynamic>>.from(addressResponse));
          _preferredPayMethod = preferredPay;
          _savedVpa = savedVpa;
          _isPlatformOps = ops;
          _supportTicketsSubtitle = ticketsSubtitle;
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Customer profile load failure');
      if (mounted && seq == _loadSeq) setState(() => _isLoading = false);
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

  Future<void> _toggleAccountActive() async {
    final deactivate = !accountIsDeactivated(_accountStatus);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(deactivate ? 'Deactivate account?' : 'Activate account?'),
        content: Text(
          deactivate
              ? 'You can still sign in. Ordering stays off until you activate again.'
              : 'Your diner account will be able to place orders again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(deactivate ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final next = await _supabase.rpc(
        'set_own_account_status',
        params: {'p_active': !deactivate},
      );
      if (!mounted) return;
      setState(() => _accountStatus = normalizeAccountStatus(next?.toString()));
      _showSnackBar(
        accountIsDeactivated(_accountStatus) ? 'Account deactivated' : 'Account activated',
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Toggle account active failed');
      if (!mounted) return;
      _showSnackBar('Could not update account: $e', isError: true);
    }
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
        labelStyle: TextStyle(color: isDark ? AppTheme.textMuted : AppTheme.textMuted),
        floatingLabelStyle: const TextStyle(color: AppTheme.link, fontWeight: FontWeight.bold),
        prefixIcon: Icon(icon, color: isDark ? AppTheme.textMuted : AppTheme.textMuted),
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
                Text(
                  'Edit profile',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.textMain),
                ),
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
                          labelStyle: TextStyle(color: isDark ? AppTheme.textMuted : AppTheme.textMuted),
                          floatingLabelStyle: const TextStyle(color: AppTheme.link, fontWeight: FontWeight.bold),
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
                    labelStyle: TextStyle(color: isDark ? AppTheme.textMuted : AppTheme.textMuted),
                    floatingLabelStyle: const TextStyle(color: AppTheme.link, fontWeight: FontWeight.bold),
                    prefixIcon: Icon(Icons.restaurant_menu, color: isDark ? AppTheme.textMuted : AppTheme.textMuted),
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

  Future<Map<String, dynamic>> _loadWalletLedger() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return {
        'coins': _hotpotCoins,
        'entries': const <CoinLedgerEntry>[],
        'orders': const <WalletOrderSummary>[],
      };
    }

    List<Map<String, dynamic>> transactions = const [];
    List<Map<String, dynamic>> orders = const [];
    var coins = _hotpotCoins;

    try {
      final profile = await _supabase.from('users').select('hotpot_coins').eq('id', user.id).maybeSingle();
      coins = double.tryParse(profile?['hotpot_coins']?.toString() ?? '') ?? coins;
    } catch (_) {}

    try {
      transactions = List<Map<String, dynamic>>.from(
        await _supabase
            .from('transactions')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(80) as List,
      );
    } catch (_) {}

    const orderSelects = [
      'id, order_id, items, total_price, total_amount, status, coins_applied, created_at',
      'id, order_id, items, total_price, status, coins_applied, created_at',
      'id, order_id, coins_applied, created_at, total_price, status',
      'id, order_id, coins_applied, created_at',
    ];
    for (final columns in orderSelects) {
      try {
        orders = List<Map<String, dynamic>>.from(
          await _supabase
              .from('orders')
              .select(columns)
              .eq('customer_id', user.id)
              .order('created_at', ascending: false)
              .limit(80) as List,
        );
        break;
      } catch (_) {}
    }

    if (mounted && coins != _hotpotCoins) {
      setState(() => _hotpotCoins = coins);
    }

    return {
      'coins': coins,
      'entries': mergeCoinLedger(transactions: transactions, orders: orders),
      'orders': walletOrderSummaries(orders),
    };
  }

  void _showWalletDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
            child: FutureBuilder<Map<String, dynamic>>(
            future: _loadWalletLedger(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
                );
              }

              final coins = (snapshot.data?['coins'] as num?)?.toDouble() ?? _hotpotCoins;
              final entries = (snapshot.data?['entries'] as List<CoinLedgerEntry>?) ?? const <CoinLedgerEntry>[];
              final orders = (snapshot.data?['orders'] as List<WalletOrderSummary>?) ?? const <WalletOrderSummary>[];
              final muted = isDark ? AppTheme.textMuted : Colors.grey;

              return SingleChildScrollView(
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
                          Text(
                            '₹${coins.toInt()} Value (${coins.toInt()} Coins)',
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Order summary',
                      style: TextStyle(color: isDark ? Colors.white : AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    if (orders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No orders yet.',
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                      )
                    else
                      ...orders.map((order) {
                        return InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            context.push('/order-history');
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        order.dishLine,
                                        style: TextStyle(
                                          color: isDark ? Colors.white70 : Colors.black87,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${order.orderRef.isEmpty ? 'Order' : 'Order ${order.orderRef}'} · ${formatOrderDate(order.at?.toIso8601String())}',
                                        style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w700),
                                      ),
                                      Text(
                                        order.statusLabel,
                                        style: TextStyle(color: muted, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      order.total > 0 ? '₹${order.total.toStringAsFixed(0)}' : '—',
                                      style: TextStyle(
                                        color: isDark ? Colors.white : AppTheme.textMain,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (order.coinsApplied > 0)
                                      Text(
                                        '−${order.coinsApplied.toInt()} 🪙',
                                        style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w700),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    if (orders.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            context.push('/order-history');
                          },
                          child: const Text('See all orders'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Coin activity',
                      style: TextStyle(color: isDark ? Colors.white : AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    if (entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No coin activity yet.',
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                      )
                    else
                      ...entries.map((entry) {
                        final color = entry.isDebit ? Colors.redAccent : Colors.green;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.title,
                                      style: TextStyle(
                                        color: isDark ? Colors.white70 : Colors.black87,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if ((entry.orderRef ?? '').isNotEmpty)
                                      Text(
                                        coinWalletOrderLine(isDebit: entry.isDebit, orderRef: entry.orderRef),
                                        style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w700),
                                      ),
                                    if ((entry.detail ?? '').isNotEmpty)
                                      Text(
                                        entry.detail!,
                                        style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    Text(
                                      formatOrderDate(entry.at?.toIso8601String()),
                                      style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${entry.isDebit ? '-' : '+'}${entry.amount.toInt()} 🪙',
                                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              );
            },
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _markDefaultAddress(Map<String, dynamic> addr) async {
    final id = addr['id'];
    final user = _supabase.auth.currentUser;
    if (id == null || user == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      try {
        await _supabase.from('user_addresses').update({'is_default': false}).eq('user_id', user.id);
        await _supabase.from('user_addresses').update({
          'is_default': true,
          'updated_at': now,
        }).eq('id', id);
      } catch (_) {
        // Older schemas have no is_default; recency still drives the Home pin.
        await _supabase.from('user_addresses').update({'updated_at': now}).eq('id', id);
      }
      if (mounted) {
        setState(() {
          _addresses = [
            for (final row in _addresses) {...row, 'is_default': row['id'] == id},
          ];
        });
      }
      await _loadProfileData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Default delivery address updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not set default address: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showPaymentOptionsSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    var selected = _preferredPayMethod;
    final vpaController = TextEditingController(text: _savedVpa ?? '');

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Payment options',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.textMain,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose how Razorpay opens. Save a UPI ID on this phone (unlocked with biometrics). Card numbers stay in Razorpay.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: isDark ? AppTheme.textMuted : AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              for (final method in kCustomerPayMethods)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    method == 'card'
                        ? Icons.credit_card
                        : method == 'netbanking'
                            ? Icons.account_balance_outlined
                            : Icons.qr_code_2_outlined,
                    color: AppTheme.primary,
                  ),
                  title: Text(
                    customerPayMethodLabel(method),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppTheme.textMain,
                    ),
                  ),
                  subtitle: Text(
                    customerPayMethodSubtitle(method),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppTheme.textMuted : AppTheme.textMuted,
                    ),
                  ),
                  trailing: Icon(
                    selected == method ? Icons.check_circle : Icons.circle_outlined,
                    color: selected == method ? AppTheme.primary : AppTheme.textMuted,
                  ),
                  onTap: () => setSheetState(() => selected = method),
                ),
              TextField(
                controller: vpaController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Saved UPI ID (optional)',
                  hintText: 'name@upi',
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final vpa = vpaController.text.trim();
                    if (vpa.isNotEmpty && !looksLikeVpa(vpa)) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Enter a UPI ID like name@upi, or leave it blank.')),
                      );
                      return;
                    }
                    await savePreferredPaymentMethod(selected);
                    await saveSavedVpa(vpa);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    setState(() {
                      _preferredPayMethod = selected;
                      _savedVpa = normalizeSavedVpa(vpa);
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Preferred payment: ${customerPayMethodLabel(selected)}'
                          '${_savedVpa == null ? '' : ' · UPI saved on this phone'}',
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  child: const Text('Save preference', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => ConstrainedBox(
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
                  IconButton(
                    tooltip: 'Add address',
                    icon: const Icon(Icons.add, color: AppTheme.primary),
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
                  child: Text('No saved addresses.', style: TextStyle(color: AppTheme.textMuted)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: _addresses.map((addr) {
                      final displayStr = formatSavedAddress(addr);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.location_on, color: AppTheme.primary),
                          title: Text(displayStr, style: TextStyle(color: isDark ? Colors.white : AppTheme.textMain, fontSize: 14)),
                          subtitle: addr['is_default'] == true
                              ? const Text('Default', style: TextStyle(color: AppTheme.link, fontSize: 12, fontWeight: FontWeight.w700))
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: addr['is_default'] == true ? 'Default address' : 'Use as default',
                                icon: Icon(
                                  addr['is_default'] == true ? Icons.star : Icons.star_border,
                                  color: addr['is_default'] == true ? Colors.amber : (AppTheme.textMuted),
                                ),
                                onPressed: addr['is_default'] == true
                                    ? null
                                    : () async {
                                        await _markDefaultAddress(addr);
                                        setSheetState(() {});
                                      },
                              ),
                              Icon(Icons.edit, size: 16, color: AppTheme.textMuted),
                            ],
                          ),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_supabase.auth.currentUser == null) {
      return Scaffold(
        appBar: widget.embedded
            ? const HubAppBar(title: 'My Profile')
            : AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleSafeBack,
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 24),
              const SizedBox(width: 8),
              const Text('Account'),
            ],
          ),
        ),
        body: EmptyState(
          icon: Icons.person_outline_rounded,
          title: 'Sign in to manage your account',
          message: 'Save addresses, track HotPot Coins, and keep your dietary preferences in one place.',
          actionLabel: 'Sign In',
          onAction: () => showAuthBottomSheet(context, () {
            if (mounted) setState(() {});
          }),
        ),
      );
    }

    return PopScope(
      canPop: widget.embedded,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleSafeBack();
      },
      child: PremiumProfileScaffold(
        workspace: ProfileWorkspace.diner,
        displayName: _nameController.text.isEmpty ? 'Valued diner' : _nameController.text,
        avatar: AvatarUploadWidget(
          initialAvatarUrl: _avatarUrl,
          isEditing: false,
          onUploadComplete: (newUrl) => setState(() => _avatarUrl = newUrl),
        ),
        loading: _isLoading,
        onBack: widget.embedded ? null : _handleSafeBack,
        onLogout: null,
        body: SingleChildScrollView(
          child: Column(
            children: [
              PremiumProfileHero(
                workspace: ProfileWorkspace.diner,
                displayName: _nameController.text.isEmpty ? 'Valued diner' : _nameController.text,
                subtitle: _phoneController.text.isEmpty ? 'Add a phone number' : _phoneController.text,
                meta: _email,
                avatar: AvatarUploadWidget(
                  initialAvatarUrl: _avatarUrl,
                  isEditing: false,
                  onUploadComplete: (newUrl) => setState(() => _avatarUrl = newUrl),
                ),
                onEdit: _showEditProfileSheet,
                editLabel: 'Edit profile',
              ),
              PremiumProfileSection(
                title: 'Saved addresses',
                children: [
                  PremiumProfileTile(
                    icon: Icons.location_on_outlined,
                    title: _addresses.isEmpty ? 'Add a drop-off' : 'Manage drops',
                    subtitle: _addresses.isEmpty
                        ? 'Save a pin for faster checkout'
                        : (_addresses.length == 1
                            ? formatSavedAddress(_addresses.first)
                            : '${formatSavedAddress(_addresses.first)} · ${_addresses.length} saved'),
                    onTap: _showAddressesSheet,
                    showDivider: false,
                  ),
                ],
              ),
              PremiumProfileSection(
                title: 'Payment Method',
                children: [
                  PremiumProfileTile(
                    icon: Icons.payments_outlined,
                    title: customerPayMethodLabel(_preferredPayMethod),
                    subtitle: _savedVpa == null ? 'Razorpay on this phone' : 'Saved UPI on this phone',
                    onTap: _showPaymentOptionsSheet,
                    showDivider: false,
                  ),
                ],
              ),
              LoyaltyBadgeCard(
                coins: _hotpotCoins,
                onOpenWallet: _showWalletDialog,
              ),
              PremiumProfileSection(
                title: 'Dining',
                caption: 'Plans and kitchen chats.',
                children: [
                  PremiumProfileTile(
                    icon: Icons.event_repeat_outlined,
                    title: 'Weekly plans',
                    subtitle: 'Standing tiffin days',
                    onTap: () => context.push('/customer-plans'),
                  ),
                  PremiumProfileTile(
                    icon: Icons.forum_outlined,
                    title: 'Order chats',
                    subtitle: 'Reopen an Order# group',
                    onTap: () => context.push('/chats'),
                  ),
                  PremiumProfileTile(
                    icon: Icons.campaign_outlined,
                    title: 'Bulk / catering',
                    subtitle: 'Broadcast a larger order nearby',
                    onTap: () => context.push('/bulk-request'),
                  ),
                  PremiumProfileTile(
                    icon: Icons.confirmation_number_outlined,
                    title: 'Support tickets',
                    subtitle: _supportTicketsSubtitle,
                    onTap: () => context.push('/support-tickets'),
                    showDivider: false,
                  ),
                ],
              ),
              PremiumProfileSection(
                title: DinerLocaleController.instance.copy.language,
                caption: 'Home tabs and kitchen cards stay in this language.',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final locale in kDinerLocales)
                          ChoiceChip(
                            label: Text(dinerLocaleLabel(locale)),
                            selected: DinerLocaleController.instance.code == locale,
                            onSelected: (_) async {
                              await DinerLocaleController.instance.setCode(locale);
                              if (mounted) setState(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              PremiumProfileSection(
                title: 'Help & Support',
                children: [
                  PremiumProfileTile(
                    icon: Icons.lock_outline_rounded,
                    title: 'Change password',
                    onTap: _showChangePasswordDialog,
                  ),
                  PremiumProfileTile(
                    icon: Icons.article_outlined,
                    title: 'Terms & conditions',
                    onTap: () => openLegalDocument(context, LegalDocumentType.terms),
                  ),
                  PremiumProfileTile(
                    icon: Icons.help_outline_rounded,
                    title: 'FAQs',
                    onTap: () => openLegalDocument(context, LegalDocumentType.faq),
                  ),
                  PremiumProfileTile(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy policy',
                    onTap: () => openLegalDocument(context, LegalDocumentType.privacy),
                  ),
                  if (_isPlatformOps)
                    PremiumProfileTile(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'Admin desk',
                      subtitle: 'Catalog, accounts, tickets',
                      onTap: () => context.go('/platform-ops'),
                    ),
                  PremiumProfileTile(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Contact us',
                    onTap: () => showContactSupportSheet(context),
                  ),
                  PremiumProfileTile(
                    icon: accountIsDeactivated(_accountStatus)
                        ? Icons.person_outline_rounded
                        : Icons.person_off_outlined,
                    title: accountActivationTileTitle(_accountStatus),
                    subtitle: accountActivationTileSubtitle(_accountStatus),
                    onTap: _toggleAccountActive,
                  ),
                  PremiumProfileTile(
                    icon: Icons.event_busy_outlined,
                    title: 'Cancellation policy',
                    onTap: () => openLegalDocument(context, LegalDocumentType.cancellation),
                  ),
                  PremiumProfileTile(
                    icon: Icons.star_outline_rounded,
                    title: 'Rate us on Play Store',
                    onTap: launchPlayStore,
                    showDivider: false,
                  ),
                ],
              ),
              PremiumProfileLogoutButton(
                onPressed: _handleLogout,
                label: 'Log Out',
                danger: false,
              ),
              const PremiumProfileVersionFooter(),
            ],
          ),
        ),
      ),
    );
  }
}