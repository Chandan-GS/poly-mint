import 'package:equatable/equatable.dart';

/// Where a record's weight came from.
enum WeightSource {
  /// Read from the scale (Bluetooth or simulated) and bound to the photo by
  /// the PoPP proof.
  scale('SCALE'),

  /// Typed in by the operator, with no scale proof.
  manual('MANUAL');

  const WeightSource(this.wire);
  final String wire;
}

/// The everyday item a resin usually arrives as, and what one weighs.
class TypicalItem {
  final String noun;
  final double kg;
  const TypicalItem(this.noun, this.kg);
}

/// Rough per-item masses for common packaging, used only to suggest a batch
/// weight when there is no scale. The operator confirms or types the real
/// weight, and the record keeps both.
const Map<String, TypicalItem> typicalItems = {
  '1-PET': TypicalItem('bottle', 0.025), // 500 ml-1 L drink bottle
  '2-HDPE': TypicalItem('bottle or can', 0.045), // shampoo bottle, oil can
  '3-PVC': TypicalItem('pack or pipe piece', 0.030),
  '4-LDPE': TypicalItem('bag or film', 0.008), // carry bag, milk pouch
  '5-PP': TypicalItem('container', 0.025), // takeaway box, tub
  '6-PS': TypicalItem('cup or tray', 0.008),
  '7-Other': TypicalItem('item', 0.020),
};

TypicalItem typicalItemFor(String polymerCode) =>
    typicalItems[polymerCode] ?? typicalItems['7-Other']!;

/// A suggested batch weight: [itemCount] typical items of the detected resin.
class WeightEstimate extends Equatable {
  final String polymerCode;
  final int itemCount;
  final double unitKg;

  const WeightEstimate({
    required this.polymerCode,
    required this.itemCount,
    required this.unitKg,
  });

  factory WeightEstimate.of(String polymerCode, int itemCount) =>
      WeightEstimate(
        polymerCode: polymerCode,
        itemCount: itemCount,
        unitKg: typicalItemFor(polymerCode).kg,
      );

  String get itemNoun => typicalItemFor(polymerCode).noun;

  /// Rounded to the gram, like a kitchen scale.
  double get kg => double.parse((itemCount * unitKg).toStringAsFixed(3));

  Map<String, dynamic> toJson() => {
    'polymer': polymerCode,
    'item_count': itemCount,
    'unit_kg': unitKg,
    'estimate_kg': kg,
  };

  @override
  List<Object?> get props => [polymerCode, itemCount, unitKg];
}

/// Parses a typed weight in kg; accepts a comma as the decimal mark.
/// Returns 0 for anything that is not a positive number.
double parseWeightKg(String raw) {
  final w = double.tryParse(raw.trim().replaceAll(',', '.')) ?? 0;
  return w.isFinite && w > 0 ? w : 0;
}
