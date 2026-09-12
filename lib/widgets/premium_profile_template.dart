import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/app_theme.dart';

/// Shared HotPotChef account chrome for diner, chef, and driver.
enum ProfileWorkspace { diner, chef, driver }

String profileWorkspaceTitle(ProfileWorkspace workspace) {
  switch (workspace) {
    case ProfileWorkspace.diner:
      return 'Your table';
    case ProfileWorkspace.chef:
      return 'Your kitchen';
    case ProfileWorkspace.driver:
      return 'Your run';
  }
}

String profileWorkspaceRoleLabel(ProfileWorkspace workspace) {
  switch (workspace) {
    case ProfileWorkspace.diner:
      return 'Diner';
    case ProfileWorkspace.chef:
      return 'Home chef';
    case ProfileWorkspace.driver:
      return 'Delivery partner';
  }
}

String profileWorkspaceTrustLine(ProfileWorkspace workspace) {
  switch (workspace) {
    case ProfileWorkspace.diner:
      return 'Secure checkout · Nearby home kitchens · HotPot Coins';
    case ProfileWorkspace.chef:
      return 'FSSAI-first kitchen · Clear payouts · Diner-ready card';
    case ProfileWorkspace.driver:
      return 'Verified partner · Live runs · Protected earnings';
  }
}

IconData profileWorkspaceIcon(ProfileWorkspace workspace) {
  switch (workspace) {
    case ProfileWorkspace.diner:
      return Icons.restaurant_menu_rounded;
    case ProfileWorkspace.chef:
      return Icons.soup_kitchen_outlined;
    case ProfileWorkspace.driver:
      return Icons.two_wheeler_outlined;
  }
}

class PremiumProfileStat {
  const PremiumProfileStat({
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;
}

class PremiumProfileScaffold extends StatelessWidget {
  const PremiumProfileScaffold({
    super.key,
    required this.workspace,
    required this.displayName,
    required this.avatar,
    required this.body,
    this.subtitle,
    this.meta,
    this.badgeLabel,
    this.trustLine,
    this.stats = const [],
    this.onBack,
    this.onLogout,
    this.headerActions = const [],
    this.loading = false,
    this.footer,
  });

  final ProfileWorkspace workspace;
  final String displayName;
  final Widget avatar;
  final Widget body;
  final String? subtitle;
  final String? meta;
  final String? badgeLabel;
  final String? trustLine;
  final List<PremiumProfileStat> stats;
  final VoidCallback? onBack;
  final VoidCallback? onLogout;
  final List<Widget> headerActions;
  final bool loading;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final title = profileWorkspaceTitle(workspace);
    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: onBack,
              ),
        title: Text(title, style: AppTheme.cardTitleOf(context)),
        actions: [
          ...headerActions,
          if (onLogout != null)
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout_rounded, color: AppTheme.textMuted),
              onPressed: onLogout,
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
              children: [
                Expanded(child: body),
                ?footer,
              ],
            ),
    );
  }
}

class PremiumProfileHero extends StatelessWidget {
  const PremiumProfileHero({
    super.key,
    required this.workspace,
    required this.displayName,
    required this.avatar,
    this.subtitle,
    this.meta,
    this.badgeLabel,
    this.trustLine,
    this.onEdit,
    this.editLabel = 'Edit profile',
  });

  final ProfileWorkspace workspace;
  final String displayName;
  final Widget avatar;
  final String? subtitle;
  final String? meta;
  final String? badgeLabel;
  final String? trustLine;
  final VoidCallback? onEdit;
  final String editLabel;

  @override
  Widget build(BuildContext context) {
    final role = badgeLabel ?? profileWorkspaceRoleLabel(workspace);
    final trust = trustLine ?? profileWorkspaceTrustLine(workspace);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: AppTheme.radiusXl,
        boxShadow: AppTheme.brandGlow(opacity: 0.28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
                  ],
                ),
                child: avatar,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(profileWorkspaceIcon(workspace), size: 13, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            role.toUpperCase(),
                            style: GoogleFonts.figtree(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.fraunces(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    if ((subtitle ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: GoogleFonts.figtree(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if ((meta ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.figtree(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            trust,
            style: GoogleFonts.figtree(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (onEdit != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onEdit,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(editLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}

class PremiumProfileStatsRow extends StatelessWidget {
  const PremiumProfileStatsRow({super.key, required this.stats});

  final List<PremiumProfileStat> stats;

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _StatChip(stat: stats[i])),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.stat});

  final PremiumProfileStat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: AppTheme.cardDecoration(isDark: Theme.of(context).brightness == Brightness.dark),
      child: Column(
        children: [
          Text(
            stat.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.fraunces(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.onSurfaceOf(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.metaOf(context).copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class PremiumProfileSection extends StatelessWidget {
  const PremiumProfileSection({
    super.key,
    required this.title,
    required this.children,
    this.caption,
    this.padded = true,
  });

  final String title;
  final String? caption;
  final List<Widget> children;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title, style: AppTheme.homeSectionLabelOf(context)),
          ),
          if ((caption ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(caption!, style: AppTheme.metaOf(context)),
            ),
          Container(
            width: double.infinity,
            decoration: AppTheme.cardDecoration(isDark: isDark),
            padding: padded ? const EdgeInsets.symmetric(vertical: 6) : EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ],
      ),
    );
  }
}

class PremiumProfileTile extends StatelessWidget {
  const PremiumProfileTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          title: Text(
            title,
            style: GoogleFonts.figtree(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AppTheme.onSurfaceOf(context),
            ),
          ),
          subtitle: (subtitle ?? '').trim().isEmpty
              ? null
              : Text(subtitle!, style: AppTheme.metaOf(context).copyWith(fontSize: 12)),
          trailing: onTap == null
              ? null
              : const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
        ),
        if (showDivider)
          Divider(height: 1, indent: 68, color: AppTheme.hairlineOf(context)),
      ],
    );
  }
}

/// Cream card + form fields for chef and driver profiles.
class PremiumProfileFormSection extends StatelessWidget {
  const PremiumProfileFormSection({
    super.key,
    required this.title,
    required this.children,
    this.caption,
  });

  final String title;
  final String? caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PremiumProfileSection(
      title: title,
      caption: caption,
      padded: false,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

class PremiumProfileLogoutButton extends StatelessWidget {
  const PremiumProfileLogoutButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.error,
          side: const BorderSide(color: AppTheme.error, width: 1.4),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusLg),
        ),
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Log out securely', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        onPressed: onPressed,
      ),
    );
  }
}

class PremiumProfileVersionFooter extends StatelessWidget {
  const PremiumProfileVersionFooter({super.key, this.label = 'HotPotChef · 1.0.0'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      child: Center(
        child: Text(label, style: AppTheme.metaOf(context).copyWith(fontSize: 11)),
      ),
    );
  }
}
