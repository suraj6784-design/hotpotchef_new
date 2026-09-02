// lib/screens/auth_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../models/app_role.dart';
import '../services/auth_session.dart';
import '../utils/app_theme.dart';
import '../utils/helpers.dart';

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
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Lookup Account Email',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your registered phone number or full name to check your account email hint.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: inputController,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                labelText: 'Phone or Name',
                labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                floatingLabelStyle: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                hintText: 'e.g. 9876543210 or John Doe',
                hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            // 🌟 1. Wrapped form fields in an AutofillGroup to enable OS password persistence
            child: AutofillGroup(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset('assets/app_icon.png', height: 72, width: 72),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isLogin ? 'Welcome Back!' : 'Create Account',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isLogin ? 'Sign in to access your dashboard' : 'Join HotPot Chef as a customer, cook, or driver',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 28),

                    // --- ROLE SELECTION (SIGN UP ONLY) ---
                    if (!_isLogin) ...[
                      const Text(
                        'I want to join as:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textMain),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildRoleChoiceChip(AppRole.customer, Icons.restaurant),
                          const SizedBox(width: 8),
                          _buildRoleChoiceChip(AppRole.chef, Icons.outdoor_grill),
                          const SizedBox(width: 8),
                          _buildRoleChoiceChip(AppRole.driver, Icons.delivery_dining),
                        ],
                      ),
                      const SizedBox(height: 20),

                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(color: AppTheme.textMain, fontSize: 14),
                        // 🌟 2. Added name autofill hint
                        autofillHints: const [AutofillHints.name],
                        decoration: InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: const Icon(Icons.person_outline, color: AppTheme.primary),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        validator: (v) => !_isLogin && (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: AppTheme.textMain, fontSize: 14),
                        // 🌟 3. Added telephone autofill hint
                        autofillHints: const [AutofillHints.telephoneNumber],
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: const Icon(Icons.phone_outlined, color: AppTheme.primary),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        validator: (v) => !_isLogin && (v == null || v.trim().length < 10) ? 'Enter a valid 10-digit number' : null,
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: AppTheme.textMain, fontSize: 14),
                      // 🌟 4. Added email/username autofill hints
                      autofillHints: const [AutofillHints.email, AutofillHints.username],
                      decoration: InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.primary),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty || !v.contains('@')) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: AppTheme.textMain, fontSize: 14),
                      // 🌟 5. Added password autofill hint
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.primary),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Please enter your password';
                        }
                        // Only enforce 8+ chars for new registrations; allow legacy passwords on login
                        if (!_isLogin && v.trim().length < 8) {
                          return 'Password must be at least 8 characters long';
                        }
                        return null;
                      },
                    ),

                    if (_isLogin) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _handleForgotPassword,
                          child: const Text('Forgot Password?', style: TextStyle(color: AppTheme.primary, fontSize: 12)),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: _isLoading ? null : _submitAuth,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              _isLogin ? 'Sign In' : 'Register as ${_selectedRole.storageValue}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                    const SizedBox(height: 16),

                    TextButton(
                      onPressed: () => setState(() => _isLogin = !_isLogin),
                      child: Text(
                        _isLogin ? "Don't have an account? Sign Up" : "Already have an account? Sign In",
                        style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                      ),
                    ),

                    if (_isLogin) ...[
                      TextButton(
                        onPressed: _handleForgotUsername,
                        child: const Text('Forgot Email / Username?', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Helper Widget for Role Selection Buttons ---
  Widget _buildRoleChoiceChip(AppRole role, IconData icon) {
    final isSelected = _selectedRole == role;
    final roleName = role.storageValue;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedRole = role),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.primary : Colors.grey.shade300,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: isSelected ? Colors.white : Colors.grey.shade700),
              const SizedBox(height: 4),
              Text(
                roleName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}