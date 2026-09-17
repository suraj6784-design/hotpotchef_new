import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/app_theme.dart';

/// Shared HotPotChef account chrome for diner, chef, and driver.
enum ProfileWorkspace { diner, chef, driver }

String profileWorkspaceTitle(ProfileWorkspace workspace) {
  switch (workspace) {
    case ProfileWorkspace.diner:
      return 'My Profile';
    case ProfileWorkspace.chef:
      return 'My Profile';
    case ProfileWorkspace.driver:
      return 'My Profile';
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
        ],
      ),
      body: loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppTheme.primary),
                  const SizedBox(height: 16),
                  Text('Opening your table…', style: AppTheme.captionOf(context)),
                ],
              ),
            )
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        children: [
          avatar,
          const SizedBox(height: 12),
          Text(
            displayName,
            textAlign: TextAlign.center,
            style: AppTheme.sectionTitleOf(context).copyWith(fontSize: 22),
          ),
          if ((subtitle ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle!, textAlign: TextAlign.center, style: AppTheme.captionOf(context).copyWith(fontWeight: FontWeight.w700)),
          ],
          if ((meta ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(meta!, textAlign: TextAlign.center, style: AppTheme.captionOf(context)),
          ],
          if (onEdit != null)
            TextButton(
              onPressed: onEdit,
              child: Text(editLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
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
  const PremiumProfileLogoutButton({
    super.key,
    required this.onPressed,
    this.label = 'Log out securely',
    this.danger = true,
  });

  final VoidCallback onPressed;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppTheme.error : AppTheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.4),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusLg),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
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
