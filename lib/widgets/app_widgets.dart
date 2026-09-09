// lib/widgets/app_widgets.dart
//
// Premium, reusable building blocks + motion helpers for the HotPotChef revamp.
// Warm & premium direction: gradient CTAs, soft cards, shimmer skeletons,
// friendly empty states, and consistent entrance animations.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';

import '../utils/app_haptics.dart';
import '../utils/app_theme.dart';

// ---------------------------------------------------------------------------
// Motion helpers
// ---------------------------------------------------------------------------

/// Consistent entrance animations used across the app.
/// Honors system "reduce motion" / disableAnimations.
extension AppMotion on Widget {
  static bool _reduce(BuildContext? context) {
    if (context == null) return false;
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  /// Fade + slight upward slide. Stagger is capped so long lists do not wait.
  Widget entrance({int index = 0, Duration? delay}) {
    return Builder(
      builder: (context) {
        if (_reduce(context)) return this;
        final staggerIndex = index.clamp(0, AppTheme.entranceStaggerMaxIndex);
        final d = delay ?? Duration(milliseconds: AppTheme.entranceStaggerMs * staggerIndex);
        const dur = AppTheme.entranceDuration;
        return animate()
            .fadeIn(duration: dur, delay: d, curve: Curves.easeOut)
            .slideY(begin: 0.06, end: 0, duration: dur, delay: d, curve: Curves.easeOutCubic);
      },
    );
  }

  /// Subtle scale-in, good for hero elements and badges.
  Widget popIn({Duration? delay}) {
    return Builder(
      builder: (context) {
        if (_reduce(context)) return this;
        return animate().fadeIn(duration: 300.ms, delay: delay).scaleXY(
              begin: 0.92,
              end: 1,
              duration: 380.ms,
              delay: delay,
              curve: Curves.easeOutBack,
            );
      },
    );
  }

  /// Soft success pulse for confirmations (add-to-cart, FRESH badge).
  Widget successPulse({Duration? delay}) {
    return Builder(
      builder: (context) {
        if (_reduce(context)) return this;
        return animate(delay: delay)
            .fadeIn(duration: 240.ms)
            .scaleXY(begin: 0.96, end: 1, duration: 320.ms, curve: Curves.easeOutBack);
      },
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

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.loading ? '${widget.label}, loading' : widget.label,
      child: GestureDetector(
        onTap: enabled
            ? () {
                AppHaptics.light();
                widget.onPressed?.call();
              }
            : null,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: () => setState(() => _pressed = false),
        child: widget.expand ? SizedBox(width: double.infinity, child: button) : button,
      ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  const AppLogo(size: 56, elevated: true),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                    child: Icon(icon, size: 14, color: Colors.white),
                  ),
                ],
              ),
            ).popIn(),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.cardTitleOf(context),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTheme.bodyMuted,
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

/// Compact order-row skeleton used on chef kitchen / dispatch queues.
class OrderListSkeleton extends StatelessWidget {
  final int count;
  const OrderListSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: count,
      itemBuilder: (_, _) => AppShimmer(
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
            borderRadius: AppTheme.radiusLg,
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ShimmerBox(width: 88, height: 12),
                  Spacer(),
                  ShimmerBox(width: 72, height: 20, borderRadius: AppTheme.radiusMd),
                ],
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  ShimmerBox(width: 44, height: 44, borderRadius: BorderRadius.all(Radius.circular(22))),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBox(width: double.infinity, height: 16),
                        SizedBox(height: 8),
                        ShimmerBox(width: 120, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              ShimmerBox(width: double.infinity, height: 44, borderRadius: AppTheme.radiusMd),
            ],
          ),
        ),
      ),
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

class AppLogo extends StatelessWidget {
  static const assetPath = 'assets/app_icon.png';

  final double size;
  final bool elevated;
  final bool onDark;

  const AppLogo({
    super.key,
    this.size = 28,
    this.elevated = false,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular((size * 0.28).clamp(6, 14));
    final mark = ClipRRect(
      borderRadius: radius,
      child: ColoredBox(
        color: Colors.white,
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Icon(Icons.local_dining_rounded, size: size * 0.72, color: AppTheme.primary),
        ),
      ),
    );
    if (!elevated && !onDark) return mark;
    return Container(
      padding: EdgeInsets.all(size >= 48 ? 8 : 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular((size * 0.28).clamp(8, 18)),
        boxShadow: elevated ? AppTheme.softShadow : null,
      ),
      child: mark,
    );
  }
}

class BrandMark extends StatelessWidget {
  final String title;
  final double iconSize;

  const BrandMark({super.key, required this.title, this.iconSize = 24});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppLogo(size: iconSize),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).appBarTheme.titleTextStyle,
          ),
        ),
      ],
    );
  }
}

class HubAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onProfile;
  final VoidCallback? onLogout;
  final List<Widget>? extraActions;

  const HubAppBar({
    super.key,
    required this.title,
    this.onProfile,
    this.onLogout,
    this.extraActions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: BrandMark(title: title),
      actions: [
        ...?extraActions,
        if (onProfile != null || onLogout != null)
          HubProfileActions(onProfile: onProfile, onLogout: onLogout),
      ],
    );
  }
}

class HubProfileActions extends StatelessWidget {
  final VoidCallback? onProfile;
  final VoidCallback? onLogout;

  const HubProfileActions({super.key, this.onProfile, this.onLogout});

  @override
  Widget build(BuildContext context) {
    // Prefer a single Account entry — logout lives in Profile to keep hub chrome calm.
    if (onProfile != null) {
      return IconButton(
        tooltip: 'Account',
        icon: const Icon(Icons.person_outline_rounded, color: AppTheme.primary),
        onPressed: onProfile,
      );
    }
    if (onLogout != null) {
      return IconButton(
        tooltip: 'Log out',
        icon: Icon(Icons.logout_rounded, color: AppTheme.textMuted),
        onPressed: onLogout,
      );
    }
    return const SizedBox.shrink();
  }
}

/// Compact toolbar action. Use for Share, Copy, Call, Track, Edit — keep labeled
/// buttons for primary CTAs (Pay, Add to cart, Save).
class AppIconAction extends StatelessWidget {
  const AppIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = enabled ? (color ?? AppTheme.primary) : AppTheme.textMuted;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: fg,
        backgroundColor: fg.withValues(alpha: enabled ? 0.10 : 0.06),
        side: BorderSide(color: fg.withValues(alpha: 0.32)),
        minimumSize: const Size(44, 44),
        maximumSize: const Size(48, 48),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

class HubDockDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;

  const HubDockDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });
}

/// Keeps every hub tab mounted. Only the selected child is painted.
class HubTabSwitcher extends StatelessWidget {
  final int index;
  final List<Widget> children;

  const HubTabSwitcher({
    super.key,
    required this.index,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: index,
      sizing: StackFit.expand,
      children: children,
    );
  }
}

/// Floating pill navigation used on customer and driver hubs.
class HubBottomDock extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<HubDockDestination> destinations;

  const HubBottomDock({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final surface = AppTheme.surfaceOf(context);
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: AppTheme.hairlineOf(context)),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < destinations.length; i++)
                _HubDockButton(
                  destination: destinations[i],
                  selected: selectedIndex == i,
                  onTap: () {
                    if (i == selectedIndex) return;
                    AppHaptics.selection();
                    onSelect(i);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubDockButton extends StatelessWidget {
  final HubDockDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _HubDockButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = destination.badgeCount > 0 ? ', ${destination.badgeCount} items' : '';
    return Semantics(
      button: true,
      selected: selected,
      label: '${destination.label}$badge',
      child: GestureDetector(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(horizontal: selected ? 18 : 14, vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Badge(
                  label: Text('${destination.badgeCount}'),
                  isLabelVisible: destination.badgeCount > 0,
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    color: selected ? AppTheme.linkOf(context) : AppTheme.textMutedOf(context),
                    size: 22,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Text(
                    destination.label,
                    style: TextStyle(
                      color: AppTheme.linkOf(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Password stays dotted unless the eye is held down.
class HoldToRevealPasswordIcon extends StatelessWidget {
  const HoldToRevealPasswordIcon({
    super.key,
    required this.obscured,
    required this.onObscuredChanged,
  });

  final bool obscured;
  final ValueChanged<bool> onObscuredChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Hold to show password',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onObscuredChanged(false),
        onTapUp: (_) => onObscuredChanged(true),
        onTapCancel: () => onObscuredChanged(true),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        ),
      ),
    );
  }
}
