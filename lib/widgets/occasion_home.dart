import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../utils/occasion_catalog.dart';

/// Occasion groups on diner Home. One occasion can be selected at a time.
class OccasionHomeBoard extends StatelessWidget {
  const OccasionHomeBoard({
    super.key,
    required this.selectedLabel,
    required this.onSelect,
    required this.onAskKitchens,
  });

  final String selectedLabel;
  final ValueChanged<FoodOccasion?> onSelect;
  final ValueChanged<FoodOccasion> onAskKitchens;

  @override
  Widget build(BuildContext context) {
    final selected = foodOccasionByLabel(selectedLabel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in kOccasionGroups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.title, style: AppTheme.homeSectionLabelOf(context)),
                const SizedBox(height: 2),
                Text(group.blurb, style: AppTheme.caption),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: group.occasions.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final occasion = group.occasions[index];
                final on = selected?.id == occasion.id;
                return FilterChip(
                  label: Text(occasion.label),
                  avatar: Icon(occasion.icon, size: 16, color: on ? Colors.white : AppTheme.primary),
                  selected: on,
                  showCheckmark: false,
                  selectedColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    color: on ? Colors.white : AppTheme.onSurfaceOf(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  onSelected: (_) => onSelect(on ? null : occasion),
                );
              },
            ),
          ),
        ],
        if (selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(selected.hint, style: AppTheme.caption),
                ),
                TextButton(
                  onPressed: () => onAskKitchens(selected),
                  child: const Text('Ask kitchens'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
