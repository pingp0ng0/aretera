import 'package:flutter/material.dart';

class BiviColors {
  BiviColors._();

  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E2420);
  static const surfaceHigh = Color(0xFF27302A);
  static const forest = Color(0xFF2E5A44);
  static const forestLight = Color(0xFF4F8A6B);
  static const amber = Color(0xFFFF6B35);
  static const contour = Color(0xFF3A4A40);
  static const textPrimary = Color(0xFFE8ECE9);
  static const textSecondary = Color(0xFF9AA59E);
}

ThemeData buildBiviTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: BiviColors.forest,
    brightness: Brightness.dark,
  ).copyWith(
    primary: BiviColors.forestLight,
    onPrimary: Colors.white,
    primaryContainer: BiviColors.forest,
    onPrimaryContainer: Colors.white,
    secondary: BiviColors.amber,
    onSecondary: Colors.black,
    error: BiviColors.amber,
    onError: Colors.black,
    surface: BiviColors.surface,
    onSurface: BiviColors.textPrimary,
    onSurfaceVariant: BiviColors.textSecondary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: BiviColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: BiviColors.background,
      foregroundColor: BiviColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: BiviColors.textPrimary,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: BiviColors.surface,
      indicatorColor: BiviColors.forest,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? Colors.white
              : BiviColors.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? BiviColors.textPrimary
              : BiviColors.textSecondary,
        ),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: BiviColors.surface,
      showDragHandle: true,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: BiviColors.surface,
      selectedColor: BiviColors.forest,
      side: const BorderSide(color: BiviColors.contour),
      labelStyle: const TextStyle(color: BiviColors.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? BiviColors.forestLight
            : Colors.transparent,
      ),
      side: const BorderSide(color: BiviColors.textSecondary, width: 1.5),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: BiviColors.surfaceHigh,
      contentTextStyle: TextStyle(color: BiviColors.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: BiviColors.contour, thickness: 1),
  );
}
