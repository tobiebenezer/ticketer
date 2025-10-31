import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryDarkGreen = Color(0xFF2B7A2E);
  static const Color secondaryLeafGreen = Color(0xFF87C442);
  static const Color accentYellow = Color(0xFFF1D30D);

  static const MaterialColor brandSwatch = MaterialColor(
    0xFF2B7A2E,
    <int, Color>{
      50: Color(0xFFE6EEE7),
      100: Color(0xFFC1D8C3),
      200: Color(0xFF98C098),
      300: Color(0xFF6FA86E),
      400: Color(0xFF509652),
      500: Color(0xFF2B7A2E),
      600: Color(0xFF277228),
      700: Color(0xFF216720),
      800: Color(0xFF1B5D19),
      900: Color(0xFF104A0C),
    },
  );

  static final ColorScheme lightScheme = ColorScheme.fromSeed(
    seedColor: primaryDarkGreen,
  ).copyWith(
    secondary: secondaryLeafGreen,
    tertiary: accentYellow,
  );

  static final ColorScheme darkScheme = ColorScheme.fromSeed(
    seedColor: primaryDarkGreen,
    brightness: Brightness.dark,
  ).copyWith(
    secondary: secondaryLeafGreen,
    tertiary: accentYellow,
  );

  static const double _radius = 12;

  static OutlineInputBorder _outline(Color color, {double width = 1.2}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide(color: color, width: width),
      );

  static InputDecorationTheme _inputTheme(ColorScheme cs) => InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest.withOpacity(0.2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: _outline(cs.outline),
        enabledBorder: _outline(cs.outline),
        focusedBorder: _outline(cs.primary, width: 2),
        errorBorder: _outline(cs.error),
        focusedErrorBorder: _outline(cs.error, width: 2),
        labelStyle: TextStyle(color: cs.onSurfaceVariant),
        prefixIconColor: cs.onSurfaceVariant,
      );

  static ButtonStyle _filledButton(ColorScheme cs) => FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
      );

  static ButtonStyle _elevatedButton(ColorScheme cs) => ElevatedButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
      );

  static AppBarTheme _appBar(ColorScheme cs) => AppBarTheme(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: cs.onPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: cs.onPrimary),
        actionsIconTheme: IconThemeData(color: cs.onPrimary),
        surfaceTintColor: cs.primary,
      );

  static SnackBarThemeData _snackBar(ColorScheme cs) => SnackBarThemeData(
        backgroundColor: cs.primary,
        contentTextStyle: TextStyle(color: cs.onPrimary),
        actionTextColor: cs.onPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
      );

  static BottomNavigationBarThemeData _bottomNav(ColorScheme cs) =>
      BottomNavigationBarThemeData(
        backgroundColor: cs.surface,
        selectedItemColor: cs.primary,
        unselectedItemColor: cs.onSurfaceVariant,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      );

  static NavigationBarThemeData _navBar(ColorScheme cs) => NavigationBarThemeData(
        backgroundColor: cs.surface,
        indicatorColor: cs.primary.withOpacity(0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? cs.primary : cs.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? cs.primary : cs.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      );

  static ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: lightScheme,
    primarySwatch: brandSwatch,
    elevatedButtonTheme: ElevatedButtonThemeData(style: _elevatedButton(lightScheme)),
    filledButtonTheme: FilledButtonThemeData(style: _filledButton(lightScheme)),
    inputDecorationTheme: _inputTheme(lightScheme),
    appBarTheme: _appBar(lightScheme),
    snackBarTheme: _snackBar(lightScheme),
    bottomNavigationBarTheme: _bottomNav(lightScheme),
    navigationBarTheme: _navBar(lightScheme),
  );

  static ThemeData dark = ThemeData(
    useMaterial3: true,
    colorScheme: darkScheme,
    primarySwatch: brandSwatch,
    elevatedButtonTheme: ElevatedButtonThemeData(style: _elevatedButton(darkScheme)),
    filledButtonTheme: FilledButtonThemeData(style: _filledButton(darkScheme)),
    inputDecorationTheme: _inputTheme(darkScheme),
    appBarTheme: _appBar(darkScheme),
    snackBarTheme: _snackBar(darkScheme),
    bottomNavigationBarTheme: _bottomNav(darkScheme),
    navigationBarTheme: _navBar(darkScheme),
  );
}
