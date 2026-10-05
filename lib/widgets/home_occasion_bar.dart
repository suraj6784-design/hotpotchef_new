import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../utils/meal_occasions.dart';

/// Occasion controls on the diner home.
///
/// One row of four buttons filters the feed in place. Slices under the
/// selected button are the only secondary filter for that occasion.
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Home-cooked for', style: AppTheme.homeSectionLabelOf(context)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < kOccasionTabs.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _OccasionButton(
                    key: Key('home-occasion-${kOccasionTabs[i].id}'),
                    label: kOccasionTabs[i].label,
                    icon: _iconFor(kOccasionTabs[i].id),
                    selected: tab.id == kOccasionTabs[i].id,
                    onTap: () => onOccasion(kOccasionTabs[i].id),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tab.slices.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = tab.slices[index];
                final selected = slice == item.id;
                return _SliceChip(
                  key: Key('home-occasion-slice-${item.id}'),
                  label: item.label,
                  selected: selected,
                  onTap: () => onSlice(item.id),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(tab.hint, style: AppTheme.captionOf(context)),
              ),
              TextButton.icon(
                key: const Key('home-occasion-broadcast'),
                onPressed: onBroadcast,
                icon: const Icon(Icons.campaign_outlined, size: 18),
                label: const Text('Ask kitchens'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.linkOf(context),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ],
      ),
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

class _OccasionButton extends StatelessWidget {
  const _OccasionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppTheme.onSurfaceOf(context);
    final iconColor = selected ? Colors.white : AppTheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 68,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary : AppTheme.surfaceOf(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? AppTheme.primary
                    : AppTheme.hairlineOf(context),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      letterSpacing: -0.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SliceChip extends StatelessWidget {
  const _SliceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? AppTheme.primary.withValues(alpha: 0.45)
                    : AppTheme.hairlineOf(context),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? AppTheme.linkOf(context)
                    : AppTheme.textMutedOf(context),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
