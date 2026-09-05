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
import '../utils/helpers.dart';
import '../utils/legal_content.dart';
import '../utils/network.dart';
import '../utils/support.dart';
import '../widgets/app_widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.asSheet = false,
    this.sheetTitle,
    this.sheetSubtitle,
    this.initialReferralCode,
  });

  /// Guest checkout/order uses a modal sheet so the cart stays visible behind.
  final bool asSheet;
  final String? sheetTitle;
  final String? sheetSubtitle;
  final String? initialReferralCode;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  SupabaseClient get _supabase => Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _acceptedTerms = false;
  String? _authError;

  AppRole _selectedRole = AppRole.customer;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _referralController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final seeded = normalizeReferralCode(widget.initialReferralCode);
    if (seeded != null) {
      _referralController.text = seeded;
      _isLogin = false;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  String _friendlyAuthError(Object error) => friendlyAuthError(error);

  void _showAuthError(String message) {
    if (!mounted) return;
    setState(() => _authError = message);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _leaveAuthAfterSuccess() async {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final router = GoRouter.of(context);
    final openedAsSheet = widget.asSheet;
    var role = AuthSession.roleFromSession();
    try {
      role = await AuthSession.resolveRole();
    } catch (_) {}

    void goHub() {
      if (!openedAsSheet || role != AppRole.customer) {
        router.go(role.hubPath);
      }
    }

    if (!mounted) {
      goHub();
      return;
    }
    if (openedAsSheet || Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => goHub());
  }

  Future<void> _submitAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _authError = null;
    });

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
          unawaited(_ensurePublicUserProfile());
          unawaited(PushNotificationService.syncTokenForCurrentUser());
          _leaveAuthAfterSuccess();
        } else {
          _showAuthError('Wrong email or password. Please try again.');
        }
      } else {
        if (!_acceptedTerms) {
          _showAuthError('Please accept the Terms & conditions to create an account.');
        } else {
        // --- SIGN-UP FLOW WITH EXPLICIT ROLE ---
        final name = _nameController.text.trim();
        final phone = _phoneController.text.trim();
        final String? referredBy;
        try {
          referredBy = _selectedRole.usesReferral ? await _resolveSignupReferralCode() : null;
        } on FormatException catch (e) {
          _showAuthError(e.message);
          return;
        }

        final response = await _supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'name': name,
            'phone': phone,
            'role': _selectedRole.storageValue,
            if (referredBy != null) 'referred_by': referredBy,
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
          await _upsertPublicUserRow(
            signupUserPayload(
              id: response.user!.id,
              email: email,
              name: name,
              phone: phone,
              role: _selectedRole.storageValue,
              referredBy: referredBy,
              referralCode: _selectedRole.usesReferral ? generateReferralCode() : null,
              createdAt: DateTime.now().toIso8601String(),
            ),
          );

          unawaited(PushNotificationService.syncTokenForCurrentUser());
          _leaveAuthAfterSuccess();
        }
        }
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Authentication failure');
      _showAuthError(_friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _upsertPublicUserRow(Map<String, dynamic> payload) async {
    final body = Map<String, dynamic>.from(payload);
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await _supabase.from('users').upsert(body).withTimeout(NetworkTimeouts.standard);
        return;
      } on PostgrestException catch (e) {
        if (e.code == '23505' && body.containsKey('referral_code')) {
          body['referral_code'] = generateReferralCode();
          continue;
        }
        if (e.code != 'PGRST204') rethrow;
        final match = RegExp(r"Could not find the '([^']+)' column").firstMatch(e.message);
        final missing = match?.group(1);
        if (missing == null || !body.containsKey(missing)) rethrow;
        body.remove(missing);
      }
    }
  }

  Future<void> _ensurePublicUserProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final existing = await _supabase
          .from('users')
          .select('id, referred_by, referral_code, name, phone, role, email')
          .eq('id', user.id)
          .maybeSingle()
          .withTimeout(NetworkTimeouts.standard);
      final meta = user.userMetadata ?? {};
      final role = existing?['role']?.toString() ?? meta['role']?.toString() ?? 'Customer';
      final existingCode = normalizeReferralCode(existing?['referral_code']?.toString());
      final ownCode = roleUsesReferral(role)
          ? (existingCode ?? generateReferralCode())
          : existingCode;
      final referredBy = roleUsesReferral(role)
          ? sanitizeReferredBy(
              referredBy: existing?['referred_by']?.toString() ?? meta['referred_by']?.toString(),
              ownCode: ownCode,
            )
          : null;
      await _upsertPublicUserRow(
        signupUserPayload(
          id: user.id,
          email: user.email ?? existing?['email']?.toString() ?? '',
          name: existing?['name']?.toString() ?? meta['name']?.toString() ?? '',
          phone: existing?['phone']?.toString() ?? meta['phone']?.toString() ?? '',
          role: role,
          referredBy: referredBy,
          referralCode: ownCode,
        ),
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed ensuring referral profile');
    }
  }

  Future<String?> _resolveSignupReferralCode() async {
    final code = normalizeReferralCode(_referralController.text);
    if (code == null) return null;
    if (!isPlausibleReferralCode(code)) {
      throw const FormatException('That referral code does not look right.');
    }
    try {
      final exists = await _supabase
          .rpc('referral_code_exists', params: {'p_code': code})
          .withTimeout(NetworkTimeouts.standard);
      if (exists != true) {
        throw const FormatException('That referral code was not found. Clear it or check the code.');
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      // RPC not applied yet: still store the typed code so friend counts work if it matches.
    }
    return code;
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
        redirectTo: passwordResetRedirectUri,
      ).withTimeout(NetworkTimeouts.standard);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Check your email and open the reset link on this phone.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyAuthError(e)), backgroundColor: Colors.red),
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
      backgroundColor: AppTheme.canvasOf(context),
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
                        const Center(child: AppLogo(size: 72, elevated: true)).popIn(),
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
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final maxSheetHeight = (media.size.height - keyboard - media.padding.top - 8).clamp(280.0, media.size.height);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Material(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: AutofillGroup(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: muted.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Center(child: AppLogo(size: 48, elevated: true)),
                    const SizedBox(height: 14),
                    Row(
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
                    const SizedBox(height: 12),
                    _buildCredentialCard(isDark),
                    const SizedBox(height: 4),
                    ..._buildAuthLinks(compact: true),
                  ],
                ),
              ),
            ),
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
              suffixIcon: HoldToRevealPasswordIcon(
                obscured: _obscurePassword,
                onObscuredChanged: (hidden) => setState(() => _obscurePassword = hidden),
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
          if (!_isLogin && _selectedRole.usesReferral) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _referralController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Referral code (optional)',
                hintText: 'CHEFXXXXXX',
                prefixIcon: Icon(Icons.card_giftcard_outlined),
              ),
              validator: (v) {
                final code = normalizeReferralCode(v);
                if (code == null) return null;
                return isPlausibleReferralCode(code) ? null : 'Enter a valid referral code';
              },
            ),
          ],
          if (_isLogin)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _handleForgotPassword,
                child: const Text('Forgot Password?'),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _acceptedTerms,
                    onChanged: (value) => setState(() => _acceptedTerms = value == true),
                  ),
                  Expanded(
                    child: Wrap(
                      children: [
                        const Text('I agree to the '),
                        GestureDetector(
                          onTap: () => openLegalDocument(context, LegalDocumentType.terms),
                          child: const Text(
                            'Terms & conditions',
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const Text(' and '),
                        GestureDetector(
                          onTap: () => openLegalDocument(context, LegalDocumentType.privacy),
                          child: const Text(
                            'Privacy policy',
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (_authError != null) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
              ),
              child: Text(
                _authError!,
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
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
        onPressed: _isLoading
            ? null
            : () => setState(() {
                  _isLogin = !_isLogin;
                  _authError = null;
                }),
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