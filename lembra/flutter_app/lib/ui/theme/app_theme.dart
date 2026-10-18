import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta tirada dos protótipos: fundo creme, hero verde-floresta,
/// laranja queimado como cor de ação e cores vivas só para categorias/status.
class AppColors {
  AppColors._();

  // Superfícies
  static const cream = Color(0xFFF7F1E8);
  static const card = Colors.white;
  static const cardBorder = Color(0xFFE6DDCF);
  static const field = Color(0xFFEFE6D8);

  // Hero
  static const forest = Color(0xFF2F3E36);
  static const forestDeep = Color(0xFF1C2822);

  // Marca
  static const brand = Color(0xFFB45309);
  static const brandSoft = Color(0xFFFB8C3C);

  // Texto
  static const ink = Color(0xFF1F2A24);
  static const muted = Color(0xFF6B7468);
  static const onDark = Color(0xFFF7F1E8);
  static const onDarkMuted = Color(0xFFB7C0B6);

  // Categorias e status
  static const orange = Color(0xFFFB8C3C);
  static const yellow = Color(0xFFFFC93C);
  static const green = Color(0xFF4ADE80);
  static const cyan = Color(0xFF35D0E6);
  static const cyanDeep = Color(0xFF0891B2); // cyan legível sobre fundo branco
  static const red = Color(0xFFFF5A52);
  static const slate = Color(0xFF8FA0B5);
}

/// Estilos extras que não cabem no TextTheme padrão.
class AppText {
  AppText._();

  /// Fonte monoespaçada para horários e valores (07:00, R$ 842,50).
  static TextStyle mono({
    double size = 16,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.ink,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.brand,
    onPrimary: Colors.white,
    surface: AppColors.cream,
    onSurface: AppColors.ink,
    outline: AppColors.cardBorder,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.light,
  );

  final fontFamily = GoogleFonts.plusJakartaSans().fontFamily;
final text = base.textTheme.apply(
  fontFamily: fontFamily,
  bodyColor: AppColors.ink,
  displayColor: AppColors.ink,
);

  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.cream,
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size(88, 52),
        shape: const StadiumBorder(),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(AppColors.cardBorder),
      enabledBorder: border(AppColors.cardBorder),
      focusedBorder: border(AppColors.brand, 1.5),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.brand.withValues(alpha: 0.14),
    ),
  );
}