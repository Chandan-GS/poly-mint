import 'package:flutter/material.dart';

/// Typography for the Instrument/Technical look.
///
///  * IBM Plex Sans (variable) for all prose & labels.
///  * IBM Plex Mono for every NUMBER — weights, credits, hashes, ids. Monospaced
///    figures line up in columns and read like a measuring instrument.
///
/// Colour is intentionally omitted here — callers set it from the theme so the
/// same scale works in light and dark.
abstract class AppType {
  static const String sans = 'IBM Plex Sans';
  static const String mono = 'IBM Plex Mono';

  static TextStyle _sans(double size, int wght,
          {double? height, double spacing = 0}) =>
      TextStyle(
        fontFamily: sans,
        fontSize: size,
        height: height,
        letterSpacing: spacing,
        fontWeight: _weight(wght),
        // Explicit axis value so the variable font renders the exact weight.
        fontVariations: [FontVariation('wght', wght.toDouble())],
      );

  static TextStyle _mono(double size, int wght,
          {double? height, double spacing = 0}) =>
      TextStyle(
        fontFamily: mono,
        fontSize: size,
        height: height,
        letterSpacing: spacing,
        fontWeight: _weight(wght),
      );

  static FontWeight _weight(int w) => switch (w) {
        <= 400 => FontWeight.w400,
        500 => FontWeight.w500,
        600 => FontWeight.w600,
        _ => FontWeight.w700,
      };

  // --- Prose (Plex Sans) ---
  static TextStyle get screenTitle => _sans(21, 600, height: 1.1);
  static TextStyle get heading => _sans(17, 600, height: 1.2);
  static TextStyle get body => _sans(14.5, 400, height: 1.45);
  static TextStyle get bodyStrong => _sans(14.5, 600, height: 1.4);
  static TextStyle get caption => _sans(12.5, 400, height: 1.35);

  /// Small ALL-CAPS section label (caller upper-cases the text).
  static TextStyle get label => _sans(11, 600, spacing: 1.3);

  // --- Numbers (Plex Mono) ---
  static TextStyle get metricXL => _mono(40, 500, height: 1.0, spacing: -0.8);
  static TextStyle get metricL => _mono(27, 500, height: 1.05, spacing: -0.4);
  static TextStyle get metricM => _mono(19, 500, height: 1.1);
  static TextStyle get monoBody => _mono(13.5, 400, height: 1.3);
  static TextStyle get monoSmall => _mono(11.5, 400, spacing: 0.2);
}
