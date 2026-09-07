// lib/screens/ops_invite_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../services/auth_session.dart';
import '../utils/helpers.dart';
import '../utils/network.dart';
import '../utils/platform_ops_access.dart';
import '../widgets/app_widgets.dart';

/// Redeem a platform helper invite code after sign-in.
class OpsInviteScreen extends StatefulWidget {
  const OpsInviteScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  State<OpsInviteScreen> createState() => _OpsInviteScreenState();
}

class _OpsInviteScreenState extends State<OpsInviteScreen> {
  late final TextEditingController _code;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: (widget.initialCode ?? '').trim().toUpperCase());
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in first, then open this invite again.')),
      );
      context.push('/auth');
      return;
    }
    final code = _code.text.trim().toUpperCase();
    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the invite code from the platform owner.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final raw = await Supabase.instance.client.rpc(
        'ops_redeem_helper_invite',
        params: {'p_code': code},
      ).withTimeout(NetworkTimeouts.standard);
      AuthSession.clearOpsCache();
      final perms = normalizeOpsPermissions(
        raw is Map ? raw['permissions'] : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            perms.isEmpty
                ? 'Helper access unlocked'
                : 'Helper access: ${perms.map(opsPermissionLabel).join(', ')}',
          ),
          backgroundColor: Colors.green,
        ),
      );
      context.go('/platform-ops');
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'Ops invite redeem failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(networkErrorMessage(e)), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(title: const Text('Ops invite')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Enter the access code from the HotPotChef platform owner to unlock limited Platform Ops tabs.',
            style: AppTheme.metaOf(context).copyWith(height: 1.4, fontSize: 14),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Invite code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: _busy ? 'Redeeming…' : 'Unlock helper access',
            icon: Icons.vpn_key_outlined,
            onPressed: _busy ? null : _redeem,
          ),
        ],
      ),
    );
  }
}
