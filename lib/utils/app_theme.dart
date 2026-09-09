// lib/utils/app_theme.dart

import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design system for HotPotChef.
///
/// Matches the marketing site: terracotta flame, cream canvas, Fraunces titles,
/// Figtree UI. Semantic tokens keep veg / price / surfaces consistent.
class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------------------
  // 1. Brand & semantic colors (aligned with website/css/site.css)
  // ---------------------------------------------------------------------------
  static const Color primary = Color(0xFFF4511E);
  static const Color primaryGradientEnd = Color(0xFFFF7043);
  static const Color primaryDark = Color(0xFFBF360C);
  static const Color accent = Color(0xFFFFB300);

  static const Color success = Color(0xFF2E9E5B);
  static const Color warning = Color(0xFFF6A609);
  static const Color error = Color(0xFFE53935);
  static const Color info = Color(0xFF2E7CF6);

  static const Color veg = Color(0xFF6B8F71);
  static const Color nonVeg = Color(0xFFC45C4A);
  static const Color price = Color(0xFF241F1C);
  static const Color photoFallback = Color(0xFFF6EDE4);

  // Backgrounds
  static const Color snow = Color(0xFFF7F3EE);
  static const Color background = snow;
  static const Color backgroundLight = snow;
  static const Color backgroundDark = Color(0xFF1A1410);

  // Surfaces (cards, sheets)
  static const Color surfaceLight = Color(0xFFFFFCF8);
  static const Color surfaceDark = Color(0xFF2A1F18);
  static const Color surfaceElevated = Color(0xFFFFFCF8);
  static const Color surfaceMutedLight = Color(0xFFF0E8E0);
  static const Color surfaceMutedDark = Color(0xFF3A2E26);

  // Text
  static const Color textMain = Color(0xFF241F1C);
  static const Color textMuted = Color(0xFF8C8279);
  static const Color textMainLight = Colors.black87;
  static const Color textMainDark = Colors.white;

  // ---------------------------------------------------------------------------
  // 2. Gradients
  // ---------------------------------------------------------------------------
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryGradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warmGradient = LinearGradient(
    colors: [Color(0xFFFF7043), Color(0xFFFFB300)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ---------------------------------------------------------------------------
  // 3. Radii & spacing tokens
  // ---------------------------------------------------------------------------
  static const double rSm = 10;
  static const double rMd = 14;
  static const double rLg = 20;
  static const double rXl = 28;

  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(rSm));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(rMd));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(rLg));
  static const BorderRadius radiusXl = BorderRadius.all(Radius.circular(rXl));

  static const Duration tabDuration = Duration(milliseconds: 240);
  static const Duration pageDuration = Duration(milliseconds: 340);
  static const Duration pageReverseDuration = Duration(milliseconds: 280);
  static const Curve pageCurve = Curves.easeOutCubic;

  // ---------------------------------------------------------------------------
  // 4. Shadows
  // ---------------------------------------------------------------------------
  static const List<BoxShadow> softShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 6)),
  ];

  static const List<BoxShadow> heavyShadow = [
    BoxShadow(color: Color(0x24000000), blurRadius: 24, offset: Offset(0, 10)),
  ];

  /// Warm, brand-tinted glow for primary CTAs.
  static List<BoxShadow> brandGlow({double opacity = 0.35}) => [
        BoxShadow(
          color: primary.withValues(alpha: opacity),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];

  // ---------------------------------------------------------------------------
  // 5. Reusable decorations
  // ---------------------------------------------------------------------------
  static Color canvasOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? backgroundDark : background;

  static Color onSurfaceOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? textMainDark : textMain;

  static Color surfaceOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? surfaceDark : surfaceLight;

  static Color surfaceMutedOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? surfaceMutedDark : surfaceMutedLight;

  static Color hairlineOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.08)
          : const Color(0xFFEDE6E0);

  static BoxDecoration cardDecoration({bool isDark = false}) {
    return BoxDecoration(
      color: isDark ? surfaceDark : surfaceLight,
      borderRadius: radiusLg,
      boxShadow: isDark ? const [] : softShadow,
      border: Border.all(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFEDE6E0),
      ),
    );
  }

  static BoxDecoration bottomSheetDecoration({bool isDark = false}) {
    return BoxDecoration(
      color: isDark ? surfaceDark : surfaceLight,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(rXl)),
      boxShadow: heavyShadow,
    );
  }

  static ShapeBorder get sheetShape =>
      const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(rXl)));

  static ShapeBorder get dialogShape =>
      const RoundedRectangleBorder(borderRadius: radiusLg);

  // ---------------------------------------------------------------------------
  // Typography + chip helpers (premium uniformity)
  // ---------------------------------------------------------------------------
  static TextStyle sectionTitleOf(BuildContext context) => GoogleFonts.fraunces(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: onSurfaceOf(context),
        height: 1.15,
      );

  static TextStyle cardTitleOf(BuildContext context) => GoogleFonts.fraunces(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: onSurfaceOf(context),
        height: 1.2,
      );

  static TextStyle bodyOf(BuildContext context) => GoogleFonts.figtree(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: onSurfaceOf(context),
        height: 1.4,
      );

  static TextStyle metaOf(BuildContext context) => GoogleFonts.figtree(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: textMuted.withValues(alpha: 0.92),
        height: 1.35,
      );

  /// Shared Home section label (offers, shelf, diet, meal grid).
  static TextStyle homeSectionLabelOf(BuildContext context) => GoogleFonts.figtree(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: onSurfaceOf(context),
        height: 1.2,
      );

  static TextStyle homeKickerOf(BuildContext context) => GoogleFonts.figtree(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
        color: primary,
        height: 1.2,
      );

  static TextStyle homeCardTitleOf(BuildContext context) => GoogleFonts.figtree(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: onSurfaceOf(context),
        height: 1.25,
      );

  static TextStyle priceOf(BuildContext context) => GoogleFonts.figtree(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).brightness == Brightness.dark ? textMainDark : price,
        fontFeatures: const [FontFeature.tabularFigures()],
        height: 1.2,
      );

  static BoxDecoration filterChipDecoration(
    BuildContext context, {
    required bool selected,
  }) {
    return BoxDecoration(
      color: selected ? primary : surfaceOf(context),
      borderRadius: radiusXl,
      border: Border.all(color: selected ? primary : hairlineOf(context)),
      boxShadow: selected ? brandGlow(opacity: 0.22) : const [],
    );
  }

  static ButtonStyle secondaryOutline(BuildContext context) {
    return OutlinedButton.styleFrom(
      foregroundColor: primary,
      minimumSize: const Size(0, 48),
      side: const BorderSide(color: primary, width: 1.4),
      shape: const RoundedRectangleBorder(borderRadius: radiusMd),
      textStyle: GoogleFonts.figtree(fontSize: 14, fontWeight: FontWeight.w700),
    );
  }

  // ---------------------------------------------------------------------------
  // 6. Theme engine
  // ---------------------------------------------------------------------------
  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scaffoldBg = isDark ? backgroundDark : background;
    final surface = isDark ? surfaceDark : surfaceLight;
    final onSurface = isDark ? textMainDark : textMain;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      surface: surface,
      error: error,
    );

    final baseTypography =
        isDark ? Typography.material2021().white : Typography.material2021().black;
    final textTheme = GoogleFonts.figtreeTextTheme(baseTypography).copyWith(
      displaySmall: GoogleFonts.fraunces(fontWeight: FontWeight.w700, color: onSurface, fontSize: 28),
      headlineMedium: GoogleFonts.fraunces(fontWeight: FontWeight.w700, color: onSurface, fontSize: 24),
      headlineSmall: GoogleFonts.fraunces(fontWeight: FontWeight.w600, color: onSurface, fontSize: 20),
      titleLarge: GoogleFonts.fraunces(fontWeight: FontWeight.w600, color: onSurface, fontSize: 18),
      titleMedium: GoogleFonts.figtree(fontWeight: FontWeight.w600, color: onSurface),
      labelLarge: GoogleFonts.figtree(fontWeight: FontWeight.w600),
    ).apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: scaffoldBg,
      colorScheme: colorScheme,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: onSurface),
        titleTextStyle: GoogleFonts.figtree(
          color: onSurface,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: radiusLg),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: GoogleFonts.figtree(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: GoogleFonts.figtree(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.figtree(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: GoogleFonts.figtree(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? surfaceMutedDark : surfaceMutedLight,
        selectedColor: primary,
        secondarySelectedColor: primary,
        labelStyle: GoogleFonts.figtree(fontSize: 12, fontWeight: FontWeight.w600, color: onSurface),
        secondaryLabelStyle: GoogleFonts.figtree(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        height: 68,
        indicatorColor: primary.withValues(alpha: 0.14),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => GoogleFonts.figtree(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? primary : textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? primary : textMuted,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2C2C2C) : const Color(0xFF2B2320),
        contentTextStyle: GoogleFonts.figtree(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500),
        actionTextColor: accent,
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        insetPadding: const EdgeInsets.all(16),
        elevation: 6,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: radiusLg),
        titleTextStyle: GoogleFonts.figtree(fontSize: 18, fontWeight: FontWeight.w700, color: onSurface),
        contentTextStyle: GoogleFonts.figtree(fontSize: 14, color: isDark ? Colors.white70 : textMain),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(rXl))),
        showDragHandle: true,
        dragHandleColor: isDark ? Colors.white24 : Colors.black12,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
        thickness: 1,
        space: 24,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        titleTextStyle: GoogleFonts.figtree(fontSize: 14.5, fontWeight: FontWeight.w600, color: onSurface),
        subtitleTextStyle: GoogleFonts.figtree(fontSize: 12.5, color: textMuted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? surfaceMutedDark : snow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(borderRadius: radiusMd, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: primary, width: 1.6),
        ),
        labelStyle: GoogleFonts.figtree(color: textMuted, fontSize: 13),
        hintStyle: GoogleFonts.figtree(color: textMuted, fontSize: 13),
        prefixIconColor: textMuted,
      ),
    );
  }
}
