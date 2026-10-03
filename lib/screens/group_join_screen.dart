import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/cart_provider.dart';
import '../services/shared_cart_service.dart';
import '../utils/app_flavor.dart';
import '../utils/helpers.dart';
import '../widgets/app_widgets.dart';

/// Lands a teammate from `https://hotpotchef.com/group/GRP-XXXXXX` into that cart.
class GroupJoinScreen extends ConsumerStatefulWidget {
  const GroupJoinScreen({super.key, required this.roomCode});

  final String roomCode;

  @override
  ConsumerState<GroupJoinScreen> createState() => _GroupJoinScreenState();
}

class _GroupJoinScreenState extends ConsumerState<GroupJoinScreen> {
  bool _loading = true;
  String? _error;

  String? get _code => parseGroupRoomCode(widget.roomCode);

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    final code = _code;
    if (code == null) {
      setState(() {
        _loading = false;
        _error = 'This group link is missing a room code.';
      });
      return;
    }
    if (kAppStorefront.isPartner) {
      setState(() {
        _loading = false;
        _error = 'Open this link in the HotPotChef diner app to join the lunch.';
      });
      return;
    }
    if (Supabase.instance.client.auth.currentUser == null) {
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(cartProvider.notifier).joinSharedRoom(code);
      if (!mounted) return;
      context.go('/customer-hub?tab=cart');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Group link join failed');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SharedCartException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code ?? widget.roomCode.trim().toUpperCase();
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.canvasOf(context),
        appBar: HubAppBar(title: 'Group lunch'),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 16),
              Text('Joining $code…', style: AppTheme.caption),
            ],
          ),
        ),
      );
    }

    final signedOut = Supabase.instance.client.auth.currentUser == null && _error == null;
    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: HubAppBar(title: 'Group lunch'),
      body: EmptyState(
        icon: Icons.apartment_outlined,
        title: signedOut ? 'Sign in to join' : 'Could not join',
        message: signedOut
            ? 'Open $code after you sign in. The host pays once at checkout.'
            : (_error ?? 'This group link could not be opened.'),
        actionLabel: signedOut ? 'Sign in' : 'Back to cart',
        onAction: () {
          if (signedOut) {
            context.go('/auth?next=${Uri.encodeComponent('/group/$code')}');
            return;
          }
          context.go('/customer-hub?tab=cart');
        },
      ),
    );
  }
}
