import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';
import '../utils/helpers.dart';
import '../utils/network.dart';
import '../widgets/app_widgets.dart';
import '../widgets/customer_ui_components.dart';

/// Deep link / App Link target for `https://hotpotchef.com/chef/{id}`.
class ChefLinkScreen extends ConsumerStatefulWidget {
  final String chefId;

  const ChefLinkScreen({super.key, required this.chefId});

  @override
  ConsumerState<ChefLinkScreen> createState() => _ChefLinkScreenState();
}

class _ChefLinkScreenState extends ConsumerState<ChefLinkScreen> {
  bool _loading = true;
  String? _error;
  String _name = 'Home kitchen';
  String _fssai = '';
  String? _story;
  List<Map<String, dynamic>> _meals = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final chefId = widget.chefId.trim();
    if (chefId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Missing kitchen link.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      Map<String, dynamic>? user;
      try {
        final row = await client
            .from('users')
            .select('name, full_name, fssai_number')
            .eq('id', chefId)
            .maybeSingle();
        if (row != null) user = Map<String, dynamic>.from(row);
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chef link user load failure');
      }

      Map<String, dynamic>? kitchen;
      try {
        final row = await client
            .from('chef_profiles')
            .select('local_kitchen_name, kitchen_story')
            .eq('user_id', chefId)
            .maybeSingle();
        if (row != null) kitchen = Map<String, dynamic>.from(row);
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chef link kitchen load failure');
      }

      List<Map<String, dynamic>> meals = const [];
      try {
        final rows = await client
            .from('meals')
            .select()
            .eq('chef_id', chefId)
            .eq('status', 'Available')
            .order('created_at', ascending: false)
            .limit(48);
        meals = rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chef link meals load failure');
      }

      if (!mounted) return;

      if (user == null && kitchen == null && meals.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'This home kitchen could not be found.';
        });
        return;
      }

      final kitchenName = kitchen?['local_kitchen_name']?.toString().trim() ?? '';
      final userName = (user?['name'] ?? user?['full_name'])?.toString().trim() ?? '';
      setState(() {
        _name = kitchenName.isNotEmpty
            ? kitchenName
            : (userName.isNotEmpty ? userName : 'Home kitchen');
        _fssai = user?['fssai_number']?.toString().trim() ?? '';
        _story = kitchen?['kitchen_story']?.toString().trim();
        _meals = meals;
        _loading = false;
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chef link load failure');
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
        appBar: HubAppBar(title: 'Kitchen'),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppTheme.canvasOf(context),
        appBar: HubAppBar(title: 'Kitchen'),
        body: EmptyState(
          icon: Icons.kitchen_outlined,
          title: 'Kitchen unavailable',
          message: _error!,
          actionLabel: 'Back to feed',
          onAction: () => context.go('/customer-hub'),
        ),
      );
    }

    final story = _story;
    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: HubAppBar(
        title: _name,
        extraActions: [
          IconButton(
            tooltip: 'Kitchen profile',
            onPressed: () => showChefProfileDialog(context, widget.chefId, _name, _fssai),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            _fssai.isEmpty ? 'Neighbourhood home kitchen' : 'FSSAI $_fssai',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
          if (story != null && story.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(story, style: TextStyle(color: AppTheme.onSurfaceOf(context), height: 1.4)),
          ],
          const SizedBox(height: 18),
          Text(
            'Available plates',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppTheme.onSurfaceOf(context),
            ),
          ),
          const SizedBox(height: 10),
          if (_meals.isEmpty)
            EmptyState(
              icon: Icons.restaurant_outlined,
              title: 'No plates right now',
              message: 'This kitchen has no Available dishes at the moment.',
              actionLabel: 'Browse feed',
              onAction: () => context.go('/customer-hub'),
            )
          else
            ..._meals.map((meal) {
              final title = mealDisplayTitle(meal);
              final price = meal['price'];
              final priceLabel = price == null ? '' : '₹${_asMoney(price)}';
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: priceLabel.isEmpty ? null : Text(priceLabel),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    final id = meal['id']?.toString() ?? '';
                    if (id.isEmpty) return;
                    context.push('/meal/$id');
                  },
                ),
              );
            }),
        ],
      ),
    );
  }

  String _asMoney(Object? value) {
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0;
    if (n <= 0) return '';
    return n.round().toString();
  }
}
