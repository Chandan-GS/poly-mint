import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Rich, real-world metadata for a single plastic resin type.
///
/// This is the single source of truth for credit economics, environmental
/// impact factors and the recycling guidance shown throughout the app.
@immutable
class PolymerInfo {
  /// Resin code label exactly as it appears in `assets/labels.txt`, e.g. `1-PET`.
  final String code;

  /// Human-friendly full name, e.g. "Polyethylene Terephthalate".
  final String fullName;

  /// Short common name, e.g. "PET".
  final String shortName;

  /// Compliance credits minted per kilogram recovered.
  final double creditRate;

  /// Kilograms of CO₂-equivalent emissions avoided per kg recycled.
  final double co2SavedPerKg;

  /// 0..1 practical recyclability / market demand score.
  final double recyclability;

  /// One-line description of the material.
  final String description;

  /// Everyday examples that fall under this resin code.
  final List<String> commonItems;

  /// Actionable prep tips to maximise credit value & recyclability.
  final List<String> tips;

  const PolymerInfo({
    required this.code,
    required this.fullName,
    required this.shortName,
    required this.creditRate,
    required this.co2SavedPerKg,
    required this.recyclability,
    required this.description,
    required this.commonItems,
    required this.tips,
  });

  Color get color => AppColors.forPolymer(code);

  /// Resin number 1..7 parsed from the code prefix.
  int get resinNumber => int.tryParse(code.split('-').first) ?? 7;

  String get recyclabilityLabel {
    if (recyclability >= 0.75) return 'Widely recyclable';
    if (recyclability >= 0.45) return 'Commonly recyclable';
    if (recyclability >= 0.2) return 'Limited recycling';
    return 'Rarely recycled';
  }
}

/// Static catalog of all resin codes PolyMint recognises. Keyed by the exact
/// label string produced by the model so lookups from inference are O(1).
abstract class PolymerCatalog {
  static const PolymerInfo unknown = PolymerInfo(
    code: '7-Other',
    fullName: 'Unclassified / Mixed Polymer',
    shortName: 'Other',
    creditRate: 0.2,
    co2SavedPerKg: 1.0,
    recyclability: 0.15,
    description:
        'Mixed or unidentified plastics. Includes multilayer packaging and '
        'composites that require specialised processing.',
    commonItems: ['Multilayer pouches', 'Toys', 'Composite packaging'],
    tips: [
      'Separate any attached caps or labels of a different resin.',
      'When unsure, capture a clear shot of the recycling triangle symbol.',
    ],
  );

  static const Map<String, PolymerInfo> byCode = {
    '1-PET': PolymerInfo(
      code: '1-PET',
      fullName: 'Polyethylene Terephthalate',
      shortName: 'PET',
      creditRate: 1.5,
      co2SavedPerKg: 2.2,
      recyclability: 0.9,
      description:
          'Clear, strong and lightweight. The most valuable and widely '
          'recycled bottle plastic.',
      commonItems: ['Water bottles', 'Soda bottles', 'Food jars'],
      tips: [
        'Empty and rinse before scanning.',
        'Remove the cap (often PP) and crush to save space.',
        'Keep labels on — MRFs remove them automatically.',
      ],
    ),
    '2-HDPE': PolymerInfo(
      code: '2-HDPE',
      fullName: 'High-Density Polyethylene',
      shortName: 'HDPE',
      creditRate: 1.2,
      co2SavedPerKg: 1.8,
      recyclability: 0.85,
      description:
          'Opaque, tough and chemical-resistant. High market demand for '
          'recycled pellets.',
      commonItems: ['Milk jugs', 'Detergent bottles', 'Shampoo bottles'],
      tips: [
        'Rinse out residue from cleaning products.',
        'Flatten jugs to reduce transport volume.',
      ],
    ),
    '3-PVC': PolymerInfo(
      code: '3-PVC',
      fullName: 'Polyvinyl Chloride',
      shortName: 'PVC',
      creditRate: 0.5,
      co2SavedPerKg: 1.1,
      recyclability: 0.25,
      description:
          'Rigid or flexible. Difficult to recycle and must be kept out of '
          'PET streams as it contaminates them.',
      commonItems: ['Pipes', 'Blister packs', 'Cling film'],
      tips: [
        'Never mix PVC with PET — it ruins the batch.',
        'Check for the "3" inside the recycling triangle.',
      ],
    ),
    '4-LDPE': PolymerInfo(
      code: '4-LDPE',
      fullName: 'Low-Density Polyethylene',
      shortName: 'LDPE',
      creditRate: 0.8,
      co2SavedPerKg: 1.4,
      recyclability: 0.4,
      description:
          'Soft and flexible film plastic. Recyclable through specialised '
          'film-collection streams.',
      commonItems: ['Plastic bags', 'Bread bags', 'Squeeze bottles'],
      tips: [
        'Keep films clean and dry.',
        'Bundle bags together for easier processing.',
      ],
    ),
    '5-PP': PolymerInfo(
      code: '5-PP',
      fullName: 'Polypropylene',
      shortName: 'PP',
      creditRate: 1.0,
      co2SavedPerKg: 1.6,
      recyclability: 0.6,
      description:
          'Heat-resistant and versatile. Increasingly accepted by recyclers.',
      commonItems: ['Bottle caps', 'Yogurt tubs', 'Straws'],
      tips: [
        'Scrape out food residue from tubs.',
        'Group small items like caps in a larger container.',
      ],
    ),
    '6-PS': PolymerInfo(
      code: '6-PS',
      fullName: 'Polystyrene',
      shortName: 'PS',
      creditRate: 0.4,
      co2SavedPerKg: 0.9,
      recyclability: 0.2,
      description:
          'Rigid or foamed (Styrofoam). Low density makes recycling '
          'uneconomical in most regions.',
      commonItems: ['Foam cups', 'Takeaway boxes', 'Packing foam'],
      tips: [
        'Keep foam clean and free of food.',
        'Compress foam blocks where possible.',
      ],
    ),
    '7-Other': unknown,
  };

  /// All resins in resin-code order (1 → 7).
  static List<PolymerInfo> get all => byCode.values.toList(growable: false);

  /// Look up a resin by its label, falling back to the "Other" bucket.
  static PolymerInfo lookup(String code) => byCode[code] ?? unknown;
}
