import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../utils/helpers.dart';
import 'app_widgets.dart';

/// What the diner-home empty state offers as its one primary action.
enum DinerFeedEmptyAction { preorder, signIn, askKitchens, clearFilters }

DinerFeedEmptyAction? dinerFeedEmptyAction(FeedEmptyCopy copy) {
  if (copy.offerPreorder) return DinerFeedEmptyAction.preorder;
  if (copy.promptSignIn) return DinerFeedEmptyAction.signIn;
  if (copy.askKitchens) return DinerFeedEmptyAction.askKitchens;
  if (copy.clearCategory) return DinerFeedEmptyAction.clearFilters;
  return null;
}

String dinerFeedEmptyActionLabel(DinerFeedEmptyAction action) {
  switch (action) {
    case DinerFeedEmptyAction.preorder:
      return 'Pre-order';
    case DinerFeedEmptyAction.signIn:
      return 'Sign In';
    case DinerFeedEmptyAction.askKitchens:
      return 'Ask kitchens';
    case DinerFeedEmptyAction.clearFilters:
      return 'Show all meals';
  }
}

/// Opens Ask kitchens with the occasion and slice already selected on home.
void pushAskKitchens(
  BuildContext context, {
  required String occasion,
  required String slice,
}) {
  context.push(askKitchensLocation(occasion: occasion, slice: slice));
}

/// Empty diner home list. Festivals, Parties, and Specialty (and their slices)
/// get Ask kitchens; other empties keep the action they already had.
class DinerFeedEmpty extends StatelessWidget {
  const DinerFeedEmpty({
    super.key,
    required this.copy,
    required this.showFollowing,
    required this.showFavorites,
    required this.onAskKitchens,
    required this.onSignIn,
    required this.onClearFilters,
    required this.onPreorder,
  });

  final FeedEmptyCopy copy;
  final bool showFollowing;
  final bool showFavorites;
  final VoidCallback onAskKitchens;
  final VoidCallback onSignIn;
  final VoidCallback onClearFilters;
  final VoidCallback onPreorder;

  @override
  Widget build(BuildContext context) {
    final action = dinerFeedEmptyAction(copy);
    // Festivals, Parties, and Specialty sit under the occasion row, slices,
    // and diet chips. The roomy empty column pushes this primary button
    // below a phone fold. Everyday keeps the standard empty spacing.
    final askKitchens = action == DinerFeedEmptyAction.askKitchens;
    return EmptyState(
      icon: copy.offerPreorder
          ? Icons.local_fire_department_outlined
          : copy.promptSignIn || showFollowing
              ? Icons.storefront_outlined
              : showFavorites
                  ? Icons.favorite_border
                  : Icons.search_off_rounded,
      title: copy.title,
      message: copy.message,
      compact: askKitchens,
      actionLabel: action == null ? null : dinerFeedEmptyActionLabel(action),
      actionKey: askKitchens ? const Key('home-occasion-empty-ask') : null,
      onAction: switch (action) {
        DinerFeedEmptyAction.preorder => onPreorder,
        DinerFeedEmptyAction.signIn => onSignIn,
        DinerFeedEmptyAction.askKitchens => onAskKitchens,
        DinerFeedEmptyAction.clearFilters => onClearFilters,
        null => null,
      },
    );
  }
}
