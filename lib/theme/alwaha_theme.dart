import 'package:flutter/material.dart';

/// ألوان «الواحة»: خلفية بحرية داكنة وتوهّج فيروزي وأخضر وذهبي كما في التصميم المعتمد.
class AlwahaColors {
  static const background = Color(0xff04141c);
  static const panel = Color(0xff0b2330);
  static const teal = Color(0xff22d3b6);
  static const green = Color(0xff4ade80);
  static const gold = Color(0xfff2c94c);
  static const sky = Color(0xff4cc9f0);
  static const glass = Color(0x14ffffff);
  static const glassBorder = Color(0x3322d3b6);
  static const textMuted = Color(0xffa9c4c9);
}

ThemeData buildAlwahaTheme() {
  const teal = AlwahaColors.teal;
  const radius16 = BorderRadius.all(Radius.circular(16));
  final scheme = ColorScheme.fromSeed(
    seedColor: teal,
    brightness: Brightness.dark,
  ).copyWith(
    primary: teal,
    onPrimary: const Color(0xff00201b),
    secondary: AlwahaColors.gold,
    tertiary: AlwahaColors.sky,
    surface: AlwahaColors.panel,
    onSurface: const Color(0xffe6f2f2),
    error: const Color(0xffff6b6b),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: AlwahaColors.panel,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: const CardThemeData(
      color: AlwahaColors.glass,
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
        side: BorderSide(color: AlwahaColors.glassBorder),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AlwahaColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(26)),
        side: BorderSide(color: AlwahaColors.glassBorder),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0x22ffffff),
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: teal,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minLeadingWidth: 24,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x1affffff),
      labelStyle: const TextStyle(color: AlwahaColors.textMuted),
      border: const OutlineInputBorder(borderRadius: radius16),
      enabledBorder: const OutlineInputBorder(
        borderRadius: radius16,
        borderSide: BorderSide(color: Color(0x3322d3b6)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: radius16,
        borderSide: BorderSide(color: teal, width: 1.6),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: radius16,
        borderSide: BorderSide(color: Color(0xffff6b6b)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: const Color(0xff00201b),
        backgroundColor: teal,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: const RoundedRectangleBorder(borderRadius: radius16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        foregroundColor: teal,
        side: const BorderSide(color: Color(0x9922d3b6)),
        shape: const RoundedRectangleBorder(borderRadius: radius16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: teal),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: teal,
      foregroundColor: Color(0xff00201b),
      shape: StadiumBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xd9061a24),
      surfaceTintColor: Colors.transparent,
      indicatorColor: const Color(0x3822d3b6),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: states.contains(WidgetState.selected)
              ? teal
              : AlwahaColors.textMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? teal
              : AlwahaColors.textMuted,
        ),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: teal,
      unselectedLabelColor: AlwahaColors.textMuted,
      indicatorColor: teal,
      dividerColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xff12404a),
      contentTextStyle: TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
  );
}
