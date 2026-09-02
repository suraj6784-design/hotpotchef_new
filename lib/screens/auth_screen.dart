// lib/screens/auth_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../models/app_role.dart';
import '../services/auth_session.dart';
import '../services/push_notification_service.dart';
import '../utils/account_hint.dart';
import '../utils/app_theme.dart';
import '../utils/helpers.dart';
import '../utils/network.dart';
import '../widgets/app_widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.asSheet = false,
    this.sheetTitle,
    this.sheetSubtitle,
  });

  /// Guest checkout/order uses a modal sheet so the cart stays visible behind.
  final bool asSheet;
  final String? sheetTitle;
  final String? sheetSubtitle;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  SupabaseClient get _supabase => Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;

  AppRole _selectedRole = AppRole.customer;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String _friendlyAuthError(Object error) {
    if (error is NetworkException) return error.message;
    final network = networkErrorMessage(error);
    if (network == NetworkException.timedOutMessage || network == NetworkException.offlineMessage) {
      return network;
    }
    if (error is AuthException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('invalid login') || msg.contains('invalid credentials')) {
        return 'Wrong email or password. Please try again.';
      }
      if (msg.contains('email not confirmed')) {
        return 'Please confirm your email before signing in.';
      }
      if (msg.contains('already registered') || msg.contains('already been registered')) {
        return 'An account with this email already exists. Try signing in.';
      }
      if (msg.contains('network') || msg.contains('failed host lookup')) {
        return 'Network issue. Check your connection and try again.';
      }
      if (error.message.trim().isNotEmpty) return error.message;
    }
    return 'Sign-in failed. Please check your details and try again.';
  }

  void _leaveAuthAfterSuccess() {
    if (!mounted) return;
    final role = AuthSession.roleFromSession();
    final router = GoRouter.of(context);
    if (widget.asSheet || Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
    // Stay on the current hub/cart when a guest customer signs in from a sheet.
    if (!widget.asSheet || role != AppRole.customer) {
      router.go(role.hubPath);
    }
  }

  Future<void> _submitAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (_isLogin) {
        // --- LOGIN FLOW ---
        final response = await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        ).withTimeout(NetworkTimeouts.standard);

        // 🌟 CRITICAL: Tells the OS login succeeded, triggering the device "Save Password" prompt
        TextInput.finishAutofillContext();

        if (response.user != null) {
          unawaited(PushNotificationService.syncTokenForCurrentUser());
          _leaveAuthAfterSuccess();
        }
      } else {
        // --- SIGN-UP FLOW WITH EXPLICIT ROLE ---
        final name = _nameController.text.trim();
        final phone = _phoneController.text.trim();

        final response = await _supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'name': name,
            'phone': phone,
            'role': _selectedRole.storageValue,
          },
        ).withTimeout(NetworkTimeouts.standard);

        // 🌟 CRITICAL: Tells the OS registration/login succeeded, prompting credential saving
        TextInput.finishAutofillContext();

        if (response.user != null) {
          if (response.session == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Account created. Check your email to confirm, then sign in.',
                  ),
                ),
              );
              setState(() => _isLogin = true);
            }
            return;
          }

          // Initialize user record in public.users table with selected role
          await _supabase.from('users').upsert({
            'id': response.user!.id,
            'email': email,
            'name': name,
            'full_name': name,
            'phone': phone,
            'role': _selectedRole.storageValue,
            'created_at': DateTime.now().toIso8601String(),
          }).withTimeout(NetworkTimeouts.standard);

          unawaited(PushNotificationService.syncTokenForCurrentUser());
          _leaveAuthAfterSuccess();
        }
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Authentication failure');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyAuthError(e)),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Forgot Password Logic ---
  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email address in the field above first.')),
      );
      return;
    }

    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.supabase.hotpotchef://reset-callback/',
      ).withTimeout(NetworkTimeouts.standard);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset instructions sent to your email!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // --- Forgot Username / Email Lookup Logic ---
  Future<void> _handleForgotUsername() async {
    final inputController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lookup Account Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the phone number or name on the account. If it matches, a masked email hint is shown. You can only try this a few times per hour.',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: inputController,
              decoration: const InputDecoration(
                labelText: 'Phone or Name',
                hintText: 'e.g. 9876543210 or John Doe',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final query = inputController.text.trim();
              Navigator.pop(ctx);
              if (query.isEmpty) return;
              if (!isValidAccountLookupQuery(query)) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a simple phone number or name.')),
                );
                return;
              }

              try {
                final response = await _supabase.rpc(
                  'lookup_account_hint',
                  params: {'p_query': query},
                ).withTimeout(NetworkTimeouts.standard);

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(accountHintMessage(parseAccountHint(response))),
                    duration: const Duration(seconds: 6),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(networkErrorMessage(e)),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Lookup'),
          ),
        ],
      ),
    );
  }

  void _browseAsGuest() {
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
    } else {
      context.go('/customer-hub');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (widget.asSheet) {
      return _buildSheet(isDark);
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 280,
            child: Container(
              decoration: const BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(36),
                  bottomRight: Radius.circular(36),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: AppTheme.radiusLg,
                              boxShadow: AppTheme.softShadow,
                            ),
                            child: ClipRRect(
                              borderRadius: AppTheme.radiusMd,
                              child: Image.asset('assets/app_icon.png', height: 64, width: 64),
                            ),
                          ),
                        ).popIn(),
                        const SizedBox(height: 16),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Text(
                            _isLogin ? 'Welcome back' : 'Join HotPotChef',
                            key: ValueKey(_isLogin),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isLogin
                              ? 'Sign in to kitchens, orders, and your wallet'
                              : 'Create an account as a diner, home chef, or driver',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                        const SizedBox(height: 28),
                        _buildCredentialCard(isDark).entrance(),
                        const SizedBox(height: 8),
                        ..._buildAuthLinks(compact: false),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSheet(bool isDark) {
    final titleColor = isDark ? AppTheme.textMainDark : AppTheme.textMain;
    final muted = isDark ? Colors.grey.shade400 : AppTheme.textMuted;
    final bg = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final title = widget.sheetTitle ?? (_isLogin ? 'Sign in to continue' : 'Join HotPotChef');
    final subtitle = widget.sheetSubtitle ??
        (_isLogin ? 'Your cart stays on this screen.' : 'Create an account to finish your order.');

    return Material(
      color: bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: titleColor)),
                          const SizedBox(height: 4),
                          Text(subtitle, style: TextStyle(fontSize: 13, height: 1.35, color: muted)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: muted),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildCredentialCard(isDark),
                          const SizedBox(height: 4),
                          ..._buildAuthLinks(compact: true),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCredentialCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: !_isLogin
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'I want to join as',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildRoleChoiceChip(AppRole.customer, Icons.restaurant_rounded),
                          const SizedBox(width: 8),
                          _buildRoleChoiceChip(AppRole.chef, Icons.outdoor_grill_rounded),
                          const SizedBox(width: 8),
                          _buildRoleChoiceChip(AppRole.driver, Icons.delivery_dining_rounded),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _nameController,
                        autofillHints: const [AutofillHints.name],
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) =>
                            !_isLogin && (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                        validator: (v) => !_isLogin && (v == null || v.trim().length < 10)
                            ? 'Enter a valid 10-digit number'
                            : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            decoration: const InputDecoration(
              labelText: 'Email Address',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty || !v.contains('@')) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Please enter your password';
              }
              if (!_isLogin && v.trim().length < 8) {
                return 'Password must be at least 8 characters long';
              }
              return null;
            },
          ),
          if (_isLogin)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _handleForgotPassword,
                child: const Text('Forgot Password?'),
              ),
            )
          else
            const SizedBox(height: 18),
          GradientButton(
            label: _isLogin ? 'Sign In' : 'Register as ${_selectedRole.storageValue}',
            icon: _isLogin ? Icons.login_rounded : Icons.person_add_alt_1_rounded,
            loading: _isLoading,
            onPressed: _isLoading ? null : _submitAuth,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAuthLinks({required bool compact}) {
    return [
      TextButton(
        onPressed: _isLoading ? null : () => setState(() => _isLogin = !_isLogin),
        child: Text(
          _isLogin ? "Don't have an account? Sign Up" : 'Already have an account? Sign In',
        ),
      ),
      if (_isLogin)
        TextButton(
          onPressed: _handleForgotUsername,
          child: const Text(
            'Forgot Email / Username?',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ),
      TextButton(
        onPressed: _browseAsGuest,
        child: Text(compact ? 'Keep my cart and go back' : 'Continue browsing meals'),
      ),
    ];
  }

  Widget _buildRoleChoiceChip(AppRole role, IconData icon) {
    final isSelected = _selectedRole == role;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedRole = role),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Theme.of(context).colorScheme.surface,
            borderRadius: AppTheme.radiusMd,
            border: Border.all(
              color: isSelected ? AppTheme.primary : Colors.grey.shade300,
              width: 1.5,
            ),
            boxShadow: isSelected ? AppTheme.brandGlow(opacity: 0.28) : const [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: isSelected ? Colors.white : AppTheme.textMuted),
              const SizedBox(height: 4),
              Text(
                role.storageValue,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}