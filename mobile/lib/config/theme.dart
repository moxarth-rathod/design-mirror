/// DesignMirror AI — App Theme
///
/// Centralized Material 3 theme with a modern, clean aesthetic
/// suited for an interior design application.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ── Color Palette ───────────────────────────
  static const Color primary = Color(0xFF2D3436);       // Dark charcoal
  static const Color primaryLight = Color(0xFF636E72);   // Medium grey
  static const Color accent = Color(0xFFE17055);         // Warm coral
  static const Color accentLight = Color(0xFFFAB1A0);    // Light coral
  static const Color background = Color(0xFFF5F6FA);     // Off-white
  static const Color surface = Color(0xFFFFFFFF);        // Pure white
  static const Color error = Color(0xFFD63031);          // Red
  static const Color success = Color(0xFF00B894);        // Teal green
  static const Color textPrimary = Color(0xFF2D3436);    // Dark
  static const Color textSecondary = Color(0xFF636E72);  // Medium grey
  static const Color divider = Color(0xFFDFE6E9);        // Light grey

  // ── Dark Palette ───────────────────────────
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkDivider = Color(0xFF2C2C2C);
  static const Color darkTextSecondary = Color(0xFFBBBBBB);

  /// Theme-aware secondary text color. Use instead of the static
  /// [textSecondary] constant when building widgets inside a BuildContext.
  static Color secondaryTextOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkTextSecondary
          : textSecondary;

  /// Theme-aware muted/placeholder color (icons, subtle labels).
  static Color mutedOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF9E9E9E)
          : primaryLight;

  /// Theme-aware handle/divider accent for bottom sheets and drag handles.
  static Color handleOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF555555)
          : Colors.grey[300]!;

  /// Theme-aware subtle container background (cards, info boxes).
  static Color surfaceDimOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF252525)
          : background;

  // ── Light Theme ─────────────────────────────
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  // ── Dark Theme ──────────────────────────────
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? darkBackground : background;
    final sfc = isDark ? darkSurface : surface;
    final txt = isDark ? const Color(0xFFECECEC) : textPrimary;
    final txtSec = isDark ? const Color(0xFFBBBBBB) : textSecondary;
    final div = isDark ? const Color(0xFF363636) : divider;
    final inputFill = isDark ? const Color(0xFF2A2A2A) : surface;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: isDark ? const Color(0xFF90CAF9) : primary,
        secondary: accent,
        surface: sfc,
        error: error,
        brightness: brightness,
      ),
      scaffoldBackgroundColor: bg,

      textTheme: GoogleFonts.interTextTheme(
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ).copyWith(
        headlineLarge: GoogleFonts.inter(
          fontSize: 28, fontWeight: FontWeight.w700, color: txt),
        headlineMedium: GoogleFonts.inter(
          fontSize: 22, fontWeight: FontWeight.w600, color: txt),
        titleLarge: GoogleFonts.inter(
          fontSize: 18, fontWeight: FontWeight.w600, color: txt),
        titleMedium: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w600, color: txt),
        bodyLarge: GoogleFonts.inter(fontSize: 16, color: txt),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: txtSec),
        labelLarge: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w600, color: sfc),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: sfc,
        foregroundColor: txt,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18, fontWeight: FontWeight.w600, color: txt),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? const Color(0xFF90CAF9) : primary,
          foregroundColor: isDark ? darkBackground : surface,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(
            fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? const Color(0xFF90CAF9) : primary,
          minimumSize: const Size(double.infinity, 52),
          side: BorderSide(
            color: isDark ? const Color(0xFF90CAF9) : primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: div)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: div)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF90CAF9) : primary, width: 2)),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error)),
        hintStyle: GoogleFonts.inter(color: txtSec, fontSize: 14),
      ),

      cardTheme: CardThemeData(
        color: sfc,
        elevation: isDark ? 0 : 2,
        shadowColor: isDark ? Colors.transparent : Colors.black12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isDark
              ? BorderSide(color: div, width: 1)
              : BorderSide.none,
        ),
      ),

      dividerTheme: DividerThemeData(color: div, thickness: 1),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: sfc,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: sfc,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

