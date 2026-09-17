import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

class DinerSectionHeader extends StatelessWidget {
  const DinerSectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.seeAllLabel = 'See all',
  });

  final String title;
  final VoidCallback? onSeeAll;
  final String seeAllLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: AppTheme.homeSectionLabelOf(context)),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: Text(
                seeAllLabel,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class DinerCircleModeChip extends StatelessWidget {
  const DinerCircleModeChip({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = AppTheme.primary,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 92,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? accent : AppTheme.surfaceOf(context),
                border: Border.all(
                  color: selected ? accent : AppTheme.hairlineOf(context),
                ),
                boxShadow: selected ? AppTheme.softShadow : const [],
              ),
              child: Icon(icon, color: selected ? Colors.white : accent, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: selected ? accent : AppTheme.onSurfaceOf(context),
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DinerSegmentBar extends StatelessWidget {
  const DinerSegmentBar({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.hairlineOf(context)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: index == i ? AppTheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: index == i ? Colors.white : AppTheme.onSurfaceOf(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DinerSegmentTabs extends StatelessWidget {
  const DinerSegmentTabs({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.showRight,
    required this.onChanged,
  });

  final String leftLabel;
  final String rightLabel;
  final bool showRight;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.hairlineOf(context)),
      ),
      child: Row(
        children: [
          _tab(context, leftLabel, selected: !showRight, onTap: () => onChanged(false)),
          _tab(context, rightLabel, selected: showRight, onTap: () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, String label, {required bool selected, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : AppTheme.onSurfaceOf(context),
            ),
          ),
        ),
      ),
    );
  }
}

class DinerAccentCard extends StatelessWidget {
  const DinerAccentCard({
    super.key,
    required this.child,
    this.accent = AppTheme.primary,
    this.onTap,
    this.unread = false,
  });

  final Widget child;
  final Color accent;
  final VoidCallback? onTap;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceOf(context),
      borderRadius: AppTheme.radiusLg,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.radiusLg,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppTheme.radiusLg,
            border: Border.all(color: AppTheme.hairlineOf(context)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: unread ? accent : AppTheme.hairlineOf(context),
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppTheme.rLg)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
                    child: child,
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
