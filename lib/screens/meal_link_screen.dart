import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import '../utils/network.dart';
import '../widgets/app_widgets.dart';
import '../widgets/customer_ui_components.dart';

class MealLinkScreen extends ConsumerStatefulWidget {
  final String mealId;

  const MealLinkScreen({super.key, required this.mealId});

  @override
  ConsumerState<MealLinkScreen> createState() => _MealLinkScreenState();
}

class _MealLinkScreenState extends ConsumerState<MealLinkScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _meal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = await Supabase.instance.client
          .from('meals')
          .select()
          .eq('id', widget.mealId)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _loading = false;
          _error = 'This dish is no longer on the menu.';
          _meal = null;
        });
        return;
      }
      setState(() {
        _meal = Map<String, dynamic>.from(row);
        _loading = false;
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Meal link load failure');
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
        appBar: HubAppBar(title: 'Dish'),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    final meal = _meal;
    if (meal == null) {
      return Scaffold(
        backgroundColor: AppTheme.canvasOf(context),
        appBar: HubAppBar(title: 'Dish'),
        body: EmptyState(
          icon: Icons.restaurant_outlined,
          title: 'Dish unavailable',
          message: _error ?? 'This dish is no longer on the menu.',
          actionLabel: 'Back to feed',
          onAction: () => context.go('/customer-hub'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      body: MealDetailsBody(meal: meal, ref: ref),
    );
  }
}
