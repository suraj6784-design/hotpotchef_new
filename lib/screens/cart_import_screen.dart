import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/cart_provider.dart';
import '../utils/app_theme.dart';
import '../utils/network.dart';
import '../widgets/app_widgets.dart';

/// Imports items from `https://hotpotchef.com/cart?items=mealId:qty,...` into the app cart.
class CartImportScreen extends ConsumerStatefulWidget {
  final String itemsParam;

  const CartImportScreen({super.key, required this.itemsParam});

  @override
  ConsumerState<CartImportScreen> createState() => _CartImportScreenState();
}

class _CartImportScreenState extends ConsumerState<CartImportScreen> {
  bool _loading = true;
  String? _error;
  int _added = 0;

  @override
  void initState() {
    super.initState();
    _import();
  }

  List<({String id, int qty})> _parseItems(String raw) {
    final out = <({String id, int qty})>[];
    for (final part in raw.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final bits = trimmed.split(':');
      final id = Uri.decodeComponent(bits.first).trim();
      if (id.isEmpty) continue;
      final qty = bits.length > 1 ? int.tryParse(bits[1]) ?? 1 : 1;
      out.add((id: id, qty: qty.clamp(1, 99)));
    }
    return out;
  }

  Future<void> _import() async {
    final specs = _parseItems(widget.itemsParam);
    if (specs.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No plates found in this cart link.';
      });
      return;
    }

    try {
      final client = Supabase.instance.client;
      final notifier = ref.read(cartProvider.notifier);
      var added = 0;

      for (final spec in specs) {
        final row = await client.from('meals').select().eq('id', spec.id).maybeSingle();
        if (row == null) continue;
        final meal = Map<String, dynamic>.from(row);
        final status = meal['status']?.toString() ?? '';
        if (status.isNotEmpty && status != 'Available') continue;
        final ok = notifier.addToCart(meal, spec.qty, clearIfVendorConflict: added == 0);
        if (ok) added += 1;
      }

      if (!mounted) return;
      if (added == 0) {
        setState(() {
          _loading = false;
          _error = 'Those plates are no longer Available. Browse the feed for other kitchens.';
        });
        return;
      }

      setState(() {
        _added = added;
        _loading = false;
      });

      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      context.go('/customer-hub?tab=cart');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Web cart import failure');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = networkErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.canvasOf(context),
        appBar: HubAppBar(title: 'Importing cart'),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppTheme.canvasOf(context),
        appBar: HubAppBar(title: 'Cart'),
        body: EmptyState(
          icon: Icons.shopping_bag_outlined,
          title: 'Could not import cart',
          message: _error!,
          actionLabel: 'Open feed',
          onAction: () => context.go('/customer-hub'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: HubAppBar(title: 'Cart'),
      body: EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Cart ready',
        message: 'Added $_added plate${_added == 1 ? '' : 's'}. Opening checkout…',
        actionLabel: 'Go to cart',
        onAction: () => context.go('/customer-hub?tab=cart'),
      ),
    );
  }
}
