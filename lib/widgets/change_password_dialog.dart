import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// Theme-following change-password dialog. Returns `true` after a successful update.
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({
    super.key,
    required this.onSubmit,
  });

  final Future<void> Function({
    required String currentPassword,
    required String newPassword,
  }) onSubmit;

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _current.text.trim();
    final newPass = _next.text.trim();
    final confirm = _confirm.text.trim();

    if (current.isEmpty) {
      setState(() => _error = 'Enter your old password.');
      return;
    }
    if (newPass.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters long.');
      return;
    }
    if (newPass != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(currentPassword: current, newPassword: newPass);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not update password. Check your old password and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppTheme.textMainDark : AppTheme.textMain;
    final muted = isDark ? Colors.grey.shade300 : AppTheme.textMuted;
    final fill = isDark ? AppTheme.surfaceMutedDark : AppTheme.surfaceMutedLight;

    InputDecoration decoration(String label, IconData icon) {
      return InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: muted),
        prefixIcon: Icon(icon, color: AppTheme.primary),
        filled: true,
        fillColor: fill,
      );
    }

    return AlertDialog(
      backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Change Password',
        style: TextStyle(color: titleColor, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _current,
              obscureText: true,
              enabled: !_submitting,
              autofocus: true,
              style: TextStyle(color: titleColor),
              decoration: decoration('Old password', Icons.lock_outline),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _next,
              obscureText: true,
              enabled: !_submitting,
              style: TextStyle(color: titleColor),
              decoration: decoration('New password (min 8 chars)', Icons.lock_reset),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              enabled: !_submitting,
              style: TextStyle(color: titleColor),
              decoration: decoration('Confirm new password', Icons.lock_reset),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: muted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('Update'),
        ),
      ],
    );
  }
}
