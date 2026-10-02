import 'package:flutter/material.dart';

/// Design tokens from design-system/cutnsave/MASTER.md ("Accessible & Ethical" style).
class AppColors {
  static const primary = Color(0xFF0369A1);
  static const onPrimary = Color(0xFFFFFFFF);
  static const secondary = Color(0xFF38BDF8);
  static const accent = Color(0xFF16A34A); // success / positive actions
  static const onAccent = Color(0xFF000000);
  static const background = Color(0xFFF0F9FF);
  static const foreground = Color(0xFF0C4A6E);
  static const card = Color(0xFFFFFFFF);
  static const muted = Color(0xFFE7EFF5);
  static const mutedForeground = Color(0xFF475569);
  static const border = Color(0xFFE0F2FE);
  static const destructive = Color(0xFFDC2626);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    secondary: AppColors.secondary,
    surface: AppColors.card,
    onSurface: AppColors.foreground,
    error: AppColors.destructive,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // No custom fontFamily: Android's system fallback chain (Roboto, then
    // Noto Sans Devanagari for Marathi/Hindi glyphs) already covers both
    // scripts consistently without bundling a font asset.
    scaffoldBackgroundColor: AppColors.background,
  );
  // `base.textTheme` only carries colors at this point — Material 3 resolves
  // font size/weight geometry (englishLike/dense/tall) later, from the
  // BuildContext's locale, via the `Theme` widget. `TextTheme.apply` asserts
  // every style already has a concrete fontSize, so merge in the default
  // geometry first (`geometry.merge(base.textTheme)`: geometry supplies
  // fontSize/weight, base.textTheme's non-null fields such as color win)
  // before scaling it 1.15x for an older reader.
  final geometry = Typography.material2021(platform: base.platform, colorScheme: scheme).englishLike;
  final resolvedTextTheme = geometry.merge(base.textTheme);
  return base.copyWith(
    // 16px+ body text, 1.15x scale on top of Material defaults for an older reader.
    textTheme: resolvedTextTheme.apply(fontSizeFactor: 1.15),
    cardTheme: CardThemeData(
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    // Minimum 44x44pt touch targets throughout; primary actions get an even larger 60px hit area.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(fontSize: 18),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    // Clear 3px focus ring (keyboard/TalkBack focus), matches the design system's a11y requirement.
    focusColor: AppColors.primary.withValues(alpha: 0.24),
  );
}
