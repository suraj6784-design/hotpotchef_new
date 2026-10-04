import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../utils/meal_occasions.dart';

/// Occasion tabs on the diner home. Switching a tab filters the feed in place.
class HomeOccasionBar extends StatelessWidget {
  const HomeOccasionBar({
    super.key,
    required this.occasion,
    required this.slice,
    required this.onOccasion,
    required this.onSlice,
    required this.onBroadcast,
  });

  final String occasion;
  final String slice;
  final ValueChanged<String> onOccasion;
  final ValueChanged<String> onSlice;
  final VoidCallback onBroadcast;

  @override
  Widget build(BuildContext context) {
    final tab = occasionTabById(occasion);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text(
            'Home-cooked for',
            style: AppTheme.homeSectionLabelOf(context).copyWith(fontSize: 13),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: kOccasionTabs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = kOccasionTabs[index];
              return _Chip(
                key: Key('home-occasion-${item.id}'),
                label: item.label,
                icon: _iconFor(item.id),
                selected: tab.id == item.id,
                onTap: () => onOccasion(item.id),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: tab.slices.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = tab.slices[index];
              return _Chip(
                key: Key('home-occasion-slice-${item.id}'),
                label: item.label,
                selected: slice == item.id,
                onTap: () => onSlice(item.id),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tab.hint,
                  style: AppTheme.caption,
                ),
              ),
              TextButton.icon(
                key: const Key('home-occasion-broadcast'),
                onPressed: onBroadcast,
                icon: const Icon(Icons.campaign_outlined, size: 18),
                label: Text('Ask kitchens'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.linkOf(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _iconFor(String id) {
    switch (id) {
      case kOccasionFestive:
        return Icons.celebration_outlined;
      case kOccasionParty:
        return Icons.cake_outlined;
      case kOccasionSpecialty:
        return Icons.inventory_2_outlined;
      default:
        return Icons.restaurant_outlined;
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: AppTheme.filterChipDecoration(context, selected: selected),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? Colors.white : AppTheme.textMuted),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.onSurfaceOf(context),
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
