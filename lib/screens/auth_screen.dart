// lib/screens/auth_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../models/app_role.dart';
import '../services/auth_session.dart';
import '../utils/helpers.dart';
import '../widgets/app_widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _supabase = Supabase.instance.client;
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

  Future<void> _routeUserByRole(User user) async {
    if (!mounted) return;
    // Navigate using the role from the session metadata — this is instant and
    // does not depend on a `public.users` query, which could stall and leave the
    // Sign In button spinning even though authentication already succeeded.
    // This mirrors the router's own redirect logic.
    await AuthSession.goToHub(context, role: AuthSession.roleFromSession());
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
        );

        // 🌟 CRITICAL: Tells the OS login succeeded, triggering the device "Save Password" prompt
        TextInput.finishAutofillContext();

        if (response.user != null) {
          await _routeUserByRole(response.user!);
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
        );

        // 🌟 CRITICAL: Tells the OS registration/login succeeded, prompting credential saving
        TextInput.finishAutofillContext();

        if (response.user != null) {
          // Initialize user record in public.users table with selected role
          await _supabase.from('users').upsert({
            'id': response.user!.id,
            'email': email,
            'name': name,
            'full_name': name,
            'phone': phone,
            'role': _selectedRole.storageValue,
            'created_at': DateTime.now().toIso8601String(),
          });

          await _routeUserByRole(response.user!);
        }
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Authentication failure');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Authentication Failed: $e'),
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
      );

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
              'Enter your registered phone number or full name to check your account email hint.',
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

              try {
                final response = await _supabase
                    .from('users')
                    .select('email')
                    .or('phone.eq.$query,name.eq.$query')
                    .maybeSingle();

                if (!mounted) return;

                if (response != null && response['email'] != null) {
                  final email = response['email'].toString();
                  final atIndex = email.indexOf('@');
                  final maskedEmail = atIndex > 1
                      ? email.replaceRange(1, atIndex, '***')
                      : email;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Account found! Registered email: $maskedEmail'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 6),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No account found matching those details.')),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Lookup failed: $e'), backgroundColor: Colors.red),
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
                        Container(
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
                        ).entrance(),
                        const SizedBox(height: 8),
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
                          child: const Text('Continue browsing meals'),
                        ),
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