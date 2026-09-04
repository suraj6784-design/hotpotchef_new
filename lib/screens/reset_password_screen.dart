import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../services/auth_session.dart';
import '../utils/helpers.dart';
import '../utils/network.dart';
import '../widgets/app_widgets.dart';

/// Sets a new password after the email recovery link opens the app.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    this.hasRecoverySession,
    this.onSubmit,
  });

  /// When null, reads the live Supabase session and listens for recovery.
  final bool? hasRecoverySession;
  final Future<void> Function(String password)? onSubmit;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  StreamSubscription<AuthState>? _authSub;
  bool _hasSession = false;
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hasSession = widget.hasRecoverySession ??
        Supabase.instance.client.auth.currentSession != null;
    if (widget.hasRecoverySession == null) {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (!mounted) return;
        setState(() {
          _hasSession = data.session != null ||
              data.event == AuthChangeEvent.passwordRecovery;
        });
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    final validation = resetPasswordValidationError(password: password, confirm: confirm);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final submit = widget.onSubmit ?? _updatePassword;
      await submit(password.trim());
      if (!mounted) return;
      if (widget.onSubmit != null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated. You are signed in.'),
          backgroundColor: Colors.green,
        ),
      );
      await AuthSession.goToHub(context);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Password recovery update failed');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = friendlyAuthError(e);
      });
    }
  }

  Future<void> _updatePassword(String password) {
    return Supabase.instance.client.auth
        .updateUser(UserAttributes(password: password))
        .withTimeout(NetworkTimeouts.standard);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        title: Text(
          'Set a new password',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.onSurfaceOf(context),
          ),
        ),
        backgroundColor: AppTheme.surfaceOf(context),
        foregroundColor: AppTheme.onSurfaceOf(context),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: AppTheme.cardDecoration(isDark: isDark),
              child: _hasSession ? _buildForm() : _buildWaiting(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaiting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Open the reset link from your email on this phone to choose a new password.',
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: AppTheme.onSurfaceOf(context),
          ),
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => context.go('/auth'),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose a new password for this account. You do not need the old one.',
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: AppTheme.onSurfaceOf(context),
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          enabled: !_submitting,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'New password (min 8 chars)',
            prefixIcon: const Icon(Icons.lock_reset),
            suffixIcon: HoldToRevealPasswordIcon(
              obscured: _obscurePassword,
              onObscuredChanged: (hidden) => setState(() => _obscurePassword = hidden),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirmController,
          obscureText: _obscurePassword,
          enabled: !_submitting,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(
            labelText: 'Confirm new password',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        GradientButton(
          label: 'Save password',
          icon: Icons.check_rounded,
          loading: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}
