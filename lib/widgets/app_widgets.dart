// lib/widgets/app_widgets.dart
//
// Premium, reusable building blocks + motion helpers for the HotPotChef revamp.
// Warm & premium direction: gradient CTAs, soft cards, shimmer skeletons,
// friendly empty states, and consistent entrance animations.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';

import '../utils/app_theme.dart';

// ---------------------------------------------------------------------------
// Motion helpers
// ---------------------------------------------------------------------------

/// Consistent entrance animations used across the app.
extension AppMotion on Widget {
  /// Fade + gentle upward slide. Pass [index] for a staggered list effect.
  Widget entrance({int index = 0, Duration? delay}) {
    final d = delay ?? Duration(milliseconds: 60 * index);
    return animate()
        .fadeIn(duration: 420.ms, delay: d, curve: Curves.easeOut)
        .slideY(begin: 0.12, end: 0, duration: 420.ms, delay: d, curve: Curves.easeOutCubic);
  }

  /// Subtle scale-in, good for hero elements and badges.
  Widget popIn({Duration? delay}) {
    return animate().fadeIn(duration: 300.ms, delay: delay).scaleXY(
          begin: 0.92,
          end: 1,
          duration: 380.ms,
          delay: delay,
          curve: Curves.easeOutBack,
        );
  }
}

// ---------------------------------------------------------------------------
// Gradient primary CTA
// ---------------------------------------------------------------------------

class GradientButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final double height;
  final Gradient? gradient;
  final EdgeInsetsGeometry? padding;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 54,
    this.gradient,
    this.padding,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final gradient = widget.gradient ?? AppTheme.primaryGradient;

    final content = widget.loading
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );

    final button = AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.55,
        duration: const Duration(milliseconds: 150),
        child: Container(
          height: widget.height,
          padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: AppTheme.radiusMd,
            boxShadow: enabled ? AppTheme.brandGlow() : const [],
          ),
          child: content,
        ),
      ),
    );

    return GestureDetector(
      onTap: enabled ? widget.onPressed : null,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: widget.expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: AppTheme.radiusSm,
            ),
            child: Icon(icon, color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.textMuted)),
                ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / error state
// ---------------------------------------------------------------------------

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.16),
                    AppTheme.accent.withValues(alpha: 0.16),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: AppTheme.primary),
            ).popIn(),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              GradientButton(label: actionLabel!, onPressed: onAction, expand: false),
            ],
          ],
        ).entrance(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shimmer skeleton loaders
// ---------------------------------------------------------------------------

class ShimmerBox extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  const ShimmerBox({super.key, this.width, this.height = 16, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? Colors.white : Colors.black,
        borderRadius: borderRadius ?? AppTheme.radiusSm,
      ),
    );
  }
}

/// Wraps content in a shimmer effect. Use with [ShimmerBox] placeholders.
class AppShimmer extends StatelessWidget {
  final Widget child;
  const AppShimmer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE9E2DC),
      highlightColor: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF7F2EE),
      child: child,
    );
  }
}

/// A skeleton placeholder mimicking a meal card while data loads.
class MealCardSkeleton extends StatelessWidget {
  const MealCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppShimmer(
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
          borderRadius: AppTheme.radiusLg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBox(width: 96, height: 96, borderRadius: AppTheme.radiusMd),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  ShimmerBox(width: double.infinity, height: 16),
                  SizedBox(height: 10),
                  ShimmerBox(width: 140, height: 12),
                  SizedBox(height: 10),
                  ShimmerBox(width: 90, height: 12),
                  SizedBox(height: 18),
                  ShimmerBox(width: 110, height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A vertical list of [MealCardSkeleton]s for full-screen loading states.
class MealListSkeleton extends StatelessWidget {
  final int count;
  const MealListSkeleton({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (_, _) => const MealCardSkeleton(),
    );
  }
}

// ---------------------------------------------------------------------------
// Small decorative helpers
// ---------------------------------------------------------------------------

/// A rounded pill tag with an optional leading icon.
class PillTag extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool filled;

  const PillTag({
    super.key,
    required this.label,
    this.icon,
    this.color = AppTheme.primary,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: filled ? Colors.white : color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: filled ? Colors.white : color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
