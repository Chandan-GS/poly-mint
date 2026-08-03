import 'package:flutter/material.dart';

/// Central color palette for PolyMint. Keep raw colors here only — everything
/// else should consume [ColorScheme] via the theme so dark mode works for free.
abstract class AppColors {
  // Brand
  static const Color primary = Color(0xFF1B8A5A); // deep eco green
  static const Color primaryDark = Color(0xFF0F5C3A);
  static const Color accent = Color(0xFF34D399); // mint accent
  static const Color seed = Color(0xFF1B8A5A);

  // Semantic
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);

  // Neutrals
  static const Color ink = Color(0xFF0F172A);
  static const Color slate = Color(0xFF64748B);
  static const Color mist = Color(0xFFF1F5F9);

  /// Distinct chip colors per resin code, used for badges & charts.
  static const Map<String, Color> polymerAccents = {
    '1-PET': Color(0xFF2563EB),
    '2-HDPE': Color(0xFF16A34A),
    '3-PVC': Color(0xFFDC2626),
    '4-LDPE': Color(0xFF7C3AED),
    '5-PP': Color(0xFFF59E0B),
    '6-PS': Color(0xFF0891B2),
    '7-Other': Color(0xFF64748B),
  };

  static Color forPolymer(String code) =>
      polymerAccents[code] ?? slate;
}
