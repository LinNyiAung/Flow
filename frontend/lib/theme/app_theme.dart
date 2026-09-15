// Toe Pwar · jade Material 3 theme.
// Source of truth: "Toe Pwar Handoff.dc.html" section 04, values verified
// against "Toe Pwar Prototype.dc.html" (light + dark CSS custom properties).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ── Light palette ──────────────────────────────────────────────
  static const jade = Color(0xFF0B6B54);
  static const jadeContainer = Color(0xFFB9E9D8);
  static const jadeContainer2 = Color(0xFFA2E0CB);
  static const jadeContainer3 = Color(0xFF8FD5BE);
  static const jadeOnContainer = Color(0xFF05261E);
  static const jadeLabel = Color(0xFF134539);
  static const jadeLabel2 = Color(0xFF05452F);
  static const secondaryContainer = Color(0xFFDCEFE8);
  static const page = Color(0xFFE7EDEA);
  static const surface = Color(0xFFF6FAF8);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF101815);
  static const inkMuted = Color(0xFF3F4A45);
  static const inkMuted2 = Color(0xFF5A655F);
  static const hint = Color(0xFF8A948E);
  static const outline = Color(0xFFC6D0CB);
  static const divider = Color(0xFFEEF2F0);
  static const track = Color(0xFFE6EBE8);
  static const danger = Color(0xFFB3261E);
  static const dangerContainer = Color(0xFFFBE3E0);
  static const onDangerContainer = Color(0xFF5C1712);
  static const gold = Color(0xFF6E5411);
  static const goldContainer = Color(0xFFFBF3DE);
  static const onGoldContainer = Color(0xFF4A3A0C);
  static const info = Color(0xFF2F4B7C);
  static const infoContainer = Color(0xFFE8EEF9);
  static const star = Color(0xFFB8860B);
  static const snack = Color(0xFF1F2A25);
  static const onSnack = Color(0xFFEDF3F0);
  static const snackAccent = Color(0xFF7FD9BE);

  // ── Dark counterparts for the roles above that have no ColorScheme slot ──
  static const darkHint = Color(0xFF7C867F);
  static const darkInfo = Color(0xFFA8C4F0);
  static const darkInfoContainer = Color(0xFF1C2740);
  static const darkStar = Color(0xFFF6DE9C);

  static bool _isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  /// Placeholder/disabled-glyph tone — below the 4.5:1 body-text floor, so
  /// never use this for a label, value or instruction.
  static Color hintFor(BuildContext context) => _isDark(context) ? darkHint : hint;
  static Color starFor(BuildContext context) => _isDark(context) ? darkStar : star;
  static Color infoFor(BuildContext context) => _isDark(context) ? darkInfo : info;
  static Color infoContainerFor(BuildContext context) => _isDark(context) ? darkInfoContainer : infoContainer;
  /// Progress-bar track tone — has no ColorScheme slot of its own. Dark
  /// value matches what dark's own progressIndicatorTheme already uses for
  /// linearTrackColor, so this stays consistent with the built-in progress
  /// bars rather than picking a new value.
  static Color trackFor(BuildContext context) => _isDark(context) ? darkDivider : track;
  /// Label/supporting text meant to sit on a primaryContainer tint — a
  /// shade distinct from onPrimaryContainer. No ColorScheme slot either.
  static Color jadeLabelFor(BuildContext context) => _isDark(context) ? darkJadeLabel : jadeLabel;
  /// Richer/darker variant of [jadeLabel] used in a couple of spots for
  /// secondary text on a tinted card. Both converge on the same accessible
  /// mint tone in dark mode — the light-mode distinction between the two
  /// doesn't need a second dark value.
  static Color jadeLabel2For(BuildContext context) => _isDark(context) ? darkJadeLabel : jadeLabel2;

  /// Series ramp for pies and stacked bars, light mode.
  static const chartRamp = <Color>[
    Color(0xFF0B6B54),
    Color(0xFF2F8E75),
    Color(0xFF66B79F),
    Color(0xFFA2D8C7),
    Color(0xFFD6EDE5),
  ];

  // ── Dark palette ───────────────────────────────────────────────
  static const darkPrimary = Color(0xFF0A7A5E); // filled buttons, keeps white ink
  static const darkPrimaryContainer = Color(0xFF00513F);
  static const darkOnPrimaryContainer = Color(0xFFC6F7E6);
  static const darkAccent = Color(0xFF7FD9BE); // accent TEXT, meter fills, links
  static const darkSurface = Color(0xFF0F1412);
  static const darkCard = Color(0xFF171E1B);
  static const darkInk = Color(0xFFE4EAE6);
  static const darkInkMuted = Color(0xFFA9B4AE);
  static const darkOutline = Color(0xFF3B453F);
  static const darkDivider = Color(0xFF2A3B34);
  static const darkError = Color(0xFFF2B8B5);
  static const darkErrorContainer = Color(0xFF4E1512);
  static const darkGold = Color(0xFFF6DE9C);
  static const darkGoldContainer = Color(0xFF38321A);
  static const darkOnGoldContainer = Color(0xFFF5EFDF);
  static const darkJadeLabel = Color(0xFF9DF2D6);

  /// Chart ramp, dark. Reversed order — light hues read first on dark.
  static const chartRampDark = <Color>[
    Color(0xFF7FD9BE),
    Color(0xFF4FB79A),
    Color(0xFF2F8E75),
    Color(0xFF1E6B58),
    Color(0xFF124A3C),
  ];

  /// Amounts only — keeps digits in vertical columns.
  static TextStyle money(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) => GoogleFonts.manrope(
    fontSize: size,
    fontWeight: weight,
    color: color ?? ink,
    letterSpacing: size >= 32 ? -size * 0.025 : 0,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Builds a brightness-correct text theme — [light] and [dark] each call
  /// this with their own ink colors so headings/body text never fall back to
  /// the light-mode near-black default on a dark surface.
  static TextTheme _textThemeFor({required Color ink, required Color inkMuted}) {
    return GoogleFonts.manropeTextTheme().apply(bodyColor: ink, displayColor: ink).copyWith(
      displaySmall: money(40, weight: FontWeight.w800, color: ink),
      headlineMedium: money(32, weight: FontWeight.w800, color: ink),
      titleLarge: GoogleFonts.manrope(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.22,
        color: ink,
      ),
      titleMedium: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      bodyLarge: GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: ink,
      ),
      labelMedium: GoogleFonts.manrope(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: inkMuted,
      ),
      labelSmall: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.22,
        color: inkMuted,
      ),
    );
  }

  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: jade,
      onPrimary: Colors.white,
      primaryContainer: jadeContainer,
      onPrimaryContainer: jadeOnContainer,
      secondaryContainer: secondaryContainer,
      tertiary: gold,
      onTertiary: Colors.white,
      tertiaryContainer: goldContainer,
      onTertiaryContainer: onGoldContainer,
      error: danger,
      onError: Colors.white,
      errorContainer: dangerContainer,
      onErrorContainer: onDangerContainer,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: inkMuted2,
      outline: outline,
      outlineVariant: divider,
    );

    final text = _textThemeFor(ink: ink, inkMuted: inkMuted2);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      textTheme: text,
      appBarTheme: AppBarTheme(
        toolbarHeight: 64,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: const IconThemeData(color: ink, size: 24),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 1,
        shadowColor: const Color(0x1A101815),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
        indent: 70,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: jade,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: jade,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: jade,
          textStyle: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: jade,
        foregroundColor: Colors.white,
        elevation: 3,
        extendedTextStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: jade,
        side: const BorderSide(color: outline),
        labelStyle: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: ink),
        secondarySelectedColor: jade,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: jade, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger),
        ),
        hintStyle: GoogleFonts.manrope(fontSize: 15, color: hint),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: jade,
        linearMinHeight: 6,
        linearTrackColor: track,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: snack,
        contentTextStyle: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w500, color: onSnack),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? jade : outline,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: inkMuted2,
        textColor: ink,
      ),
      iconTheme: const IconThemeData(color: inkMuted2),
      drawerTheme: const DrawerThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
        ),
      ),
    );
  }

  /// Dark mode reuses every shape, size and spacing value above — only the
  /// scheme changes. See "Toe Pwar Prototype Dark.dc.html".
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: darkPrimary,
      onPrimary: Colors.white,
      primaryContainer: darkPrimaryContainer,
      onPrimaryContainer: darkOnPrimaryContainer,
      secondary: darkAccent,
      onSecondary: Color(0xFF00382C),
      secondaryContainer: darkPrimaryContainer,
      tertiary: darkGold,
      onTertiary: Color(0xFF3A3213),
      tertiaryContainer: darkGoldContainer,
      onTertiaryContainer: darkOnGoldContainer,
      error: darkError,
      onError: Color(0xFF601410),
      errorContainer: darkErrorContainer,
      onErrorContainer: darkError,
      surface: darkSurface,
      onSurface: darkInk,
      onSurfaceVariant: darkInkMuted,
      outline: darkOutline,
      outlineVariant: darkDivider,
    );

    final base = light;
    final darkText = _textThemeFor(ink: darkInk, inkMuted: darkInkMuted);
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: darkText,
      cardTheme: base.cardTheme.copyWith(
        color: darkCard,
        shadowColor: const Color(0x8C000000),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        titleTextStyle: darkText.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      ),
      dividerTheme: base.dividerTheme.copyWith(color: scheme.outlineVariant),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkAccent,
          textStyle: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        backgroundColor: darkPrimary,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: darkCard,
        selectedColor: darkPrimary,
        secondarySelectedColor: darkPrimary,
        side: const BorderSide(color: darkOutline),
        labelStyle: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: darkInk),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: darkCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkOutline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkPrimary, width: 1.5),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: darkAccent,
        linearMinHeight: 6,
        linearTrackColor: darkDivider,
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: const Color(0xFF2E3A34),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: darkSurface,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(darkInk),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? darkPrimary : darkDivider,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: darkCard,
        titleTextStyle: darkText.titleMedium,
        contentTextStyle: darkText.bodyMedium,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: darkInkMuted,
        textColor: darkInk,
      ),
      iconTheme: const IconThemeData(color: darkInkMuted),
      drawerTheme: const DrawerThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
        ),
      ),
    );
  }

  /// Chart ramp for the active brightness.
  static List<Color> chartRampFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? chartRampDark : chartRamp;
}
