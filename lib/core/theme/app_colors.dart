import 'package:flutter/material.dart';

/// PolyMint palette — "Instrument / Technical" direction.
///
/// Near-monochrome warm-neutral ink on paper, with ONE confident green accent
/// used only for verified/interactive states. No gradients, no rainbow. Colour
/// carries meaning (verified / review / rejected), never decoration.
///
/// Legacy member names are kept so screens compile while they're re-skinned.
abstract class AppColors {
  // --- Light neutrals ---
  static const Color paper = Color(0xFFF6F5F1); // warm off-white background
  static const Color surface = Color(0xFFFFFFFF); // raised rows / sheets
  static const Color hairline = Color(0xFFE4E2DA); // 1px dividers & borders
  static const Color ink = Color(0xFF17191C); // primary text
  static const Color muted = Color(0xFF64696F); // secondary text
  static const Color faint = Color(0xFF9AA0A6); // tertiary / hints

  // --- Dark neutrals ---
  static const Color paperDark = Color(0xFF0E0F11);
  static const Color surfaceDark = Color(0xFF17191C);
  static const Color hairlineDark = Color(0xFF2A2D31);
  static const Color inkDark = Color(0xFFECEBE6);
  static const Color mutedDark = Color(0xFF9096A0);

  // --- The single accent ---
  static const Color accent = Color(0xFF12885B); // deep signal green
  static const Color accentDark = Color(0xFF2FCB8B); // brighter on dark
  static const Color accentWash = Color(0xFFE7F1EC); // faint green fill

  // --- Semantic (muted, functional) ---
  static const Color verified = Color(0xFF12885B);
  static const Color review = Color(0xFFB4791F); // amber, not neon
  static const Color rejected = Color(0xFFB23A2E); // terracotta red

  // Legacy aliases (kept for compatibility with un-migrated screens).
  static const Color primary = accent;
  static const Color primaryDark = Color(0xFF0C6042);
  static const Color seed = accent;
  static const Color success = verified;
  static const Color warning = review;
  static const Color danger = rejected;
  static const Color info = Color(0xFF3E6B8F);
  static const Color slate = muted;
  static const Color mist = paper;

  /// Per-resin colours for charts/badges — a refined, equal-weight categorical
  /// palette (harmonised saturation) instead of clashing primaries.
  static const Map<String, Color> polymerAccents = {
    '1-PET': Color(0xFF2E7D6B),
    '2-HDPE': Color(0xFF3E6B8F),
    '3-PVC': Color(0xFFB23A2E),
    '4-LDPE': Color(0xFF7A6BA8),
    '5-PP': Color(0xFFC0892E),
    '6-PS': Color(0xFF2F8C8C),
    '7-Other': Color(0xFF6B7078),
  };

  static Color forPolymer(String code) => polymerAccents[code] ?? muted;
}
