import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

enum TransactionStatus { verified, pendingSync, flagged }

/// How the polymer on a record was decided (the ML contract's `status`).
enum VerificationMethod {
  /// The model's own top pick, at or above the confidence gate.
  aiVerified('AI_VERIFIED'),

  /// Below the confidence gate, or the user overrode the model's pick.
  manualReview('MANUAL_REVIEW'),

  /// Records written before verification was tracked.
  unknown('UNKNOWN');

  const VerificationMethod(this.wire);
  final String wire;

  static VerificationMethod fromWire(dynamic raw) =>
      VerificationMethod.values.firstWhere(
        (v) => v.wire == raw,
        orElse: () => VerificationMethod.unknown,
      );
}

/// A recorded plastic-recovery event and the credits it minted.
///
/// Serialises to/from Firestore and to a plain JSON map for the offline queue.
class WasteTransaction extends Equatable {
  final String id;
  final String userId;
  final String userName;
  final String polymerCode;
  final double confidence;
  final double weightKg;
  final double creditsMinted;
  final double co2SavedKg;
  final double? lat;
  final double? lng;
  final DateTime timestamp;
  final TransactionStatus status;

  final VerificationMethod verification;

  /// The model's own top pick and its probability, kept even when the user
  /// recorded a different resin.
  final String? aiPolymerCode;
  final double? aiConfidence;
  final String? modelVersion;

  /// The Proof-of-Physical-Presence behind this record (`PoppProof.toJson`),
  /// stored so an auditor can re-check the weighing, not just the credit.
  final Map<String, dynamic>? popp;

  /// `SCALE` or `MANUAL` (see `WeightSource`); null on older records.
  final String? weightSource;

  /// For typed-in weights: the suggestion shown to the operator
  /// (`WeightEstimate.toJson`), kept so an auditor can compare the two.
  final Map<String, dynamic>? weightEstimate;

  /// True while this record still lives only in the local offline queue.
  final bool isLocalOnly;

  const WasteTransaction({
    required this.id,
    required this.userId,
    required this.userName,
    required this.polymerCode,
    required this.confidence,
    required this.weightKg,
    required this.creditsMinted,
    required this.co2SavedKg,
    required this.lat,
    required this.lng,
    required this.timestamp,
    required this.status,
    this.verification = VerificationMethod.unknown,
    this.aiPolymerCode,
    this.aiConfidence,
    this.modelVersion,
    this.popp,
    this.weightSource,
    this.weightEstimate,
    this.isLocalOnly = false,
  });

  WasteTransaction copyWith({TransactionStatus? status, bool? isLocalOnly}) {
    return WasteTransaction(
      id: id,
      userId: userId,
      userName: userName,
      polymerCode: polymerCode,
      confidence: confidence,
      weightKg: weightKg,
      creditsMinted: creditsMinted,
      co2SavedKg: co2SavedKg,
      lat: lat,
      lng: lng,
      timestamp: timestamp,
      status: status ?? this.status,
      verification: verification,
      aiPolymerCode: aiPolymerCode,
      aiConfidence: aiConfidence,
      modelVersion: modelVersion,
      popp: popp,
      weightSource: weightSource,
      weightEstimate: weightEstimate,
      isLocalOnly: isLocalOnly ?? this.isLocalOnly,
    );
  }

  /// Payload for Firestore. Uses a server timestamp when writing live.
  Map<String, dynamic> toFirestore() => {
    'user_id': userId,
    'user_name': userName,
    'polymer_type': polymerCode,
    'confidence': confidence,
    'weight_kg': weightKg,
    'credits_minted': creditsMinted,
    'co2_saved_kg': co2SavedKg,
    'geolocation': lat != null && lng != null ? {'lat': lat, 'lng': lng} : null,
    'status': status.name,
    'verification': verification.wire,
    'ai_polymer': aiPolymerCode,
    'ai_confidence': aiConfidence,
    'model_version': modelVersion,
    'popp': popp,
    'weight_source': weightSource,
    'weight_estimate': weightEstimate,
    'client_id': id,
    'timestamp': FieldValue.serverTimestamp(),
  };

  /// Flat JSON for the local offline queue (no Firestore sentinels).
  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'user_name': userName,
    'polymer_type': polymerCode,
    'confidence': confidence,
    'weight_kg': weightKg,
    'credits_minted': creditsMinted,
    'co2_saved_kg': co2SavedKg,
    'lat': lat,
    'lng': lng,
    'timestamp': timestamp.toIso8601String(),
    'status': status.name,
    'verification': verification.wire,
    'ai_polymer': aiPolymerCode,
    'ai_confidence': aiConfidence,
    'model_version': modelVersion,
    'popp': popp,
    'weight_source': weightSource,
    'weight_estimate': weightEstimate,
  };

  factory WasteTransaction.fromJson(Map<String, dynamic> json) {
    return WasteTransaction(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? 'anonymous',
      userName: json['user_name'] as String? ?? 'Eco Contributor',
      polymerCode: json['polymer_type'] as String? ?? '7-Other',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      weightKg: (json['weight_kg'] as num?)?.toDouble() ?? 0,
      creditsMinted: (json['credits_minted'] as num?)?.toDouble() ?? 0,
      co2SavedKg: (json['co2_saved_kg'] as num?)?.toDouble() ?? 0,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime(2020),
      status: _statusFrom(json['status']),
      verification: VerificationMethod.fromWire(json['verification']),
      aiPolymerCode: json['ai_polymer'] as String?,
      aiConfidence: (json['ai_confidence'] as num?)?.toDouble(),
      modelVersion: json['model_version'] as String?,
      popp: (json['popp'] as Map?)?.cast<String, dynamic>(),
      weightSource: json['weight_source'] as String?,
      weightEstimate: (json['weight_estimate'] as Map?)
          ?.cast<String, dynamic>(),
      isLocalOnly: true,
    );
  }

  factory WasteTransaction.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final geo = data['geolocation'] as Map<String, dynamic>?;
    final ts = data['timestamp'];
    return WasteTransaction(
      id: (data['client_id'] as String?) ?? doc.id,
      userId: data['user_id'] as String? ?? 'anonymous',
      userName: data['user_name'] as String? ?? 'Eco Contributor',
      polymerCode: data['polymer_type'] as String? ?? '7-Other',
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
      weightKg: (data['weight_kg'] as num?)?.toDouble() ?? 0,
      creditsMinted: (data['credits_minted'] as num?)?.toDouble() ?? 0,
      co2SavedKg: (data['co2_saved_kg'] as num?)?.toDouble() ?? 0,
      lat: (geo?['lat'] as num?)?.toDouble(),
      lng: (geo?['lng'] as num?)?.toDouble(),
      timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
      status: _statusFrom(data['status']),
      verification: VerificationMethod.fromWire(data['verification']),
      aiPolymerCode: data['ai_polymer'] as String?,
      aiConfidence: (data['ai_confidence'] as num?)?.toDouble(),
      modelVersion: data['model_version'] as String?,
      popp: (data['popp'] as Map?)?.cast<String, dynamic>(),
      weightSource: data['weight_source'] as String?,
      weightEstimate: (data['weight_estimate'] as Map?)
          ?.cast<String, dynamic>(),
    );
  }

  static TransactionStatus _statusFrom(dynamic raw) {
    final value = (raw as String?)?.toLowerCase();
    return TransactionStatus.values.firstWhere(
      (s) => s.name.toLowerCase() == value,
      orElse: () => TransactionStatus.verified,
    );
  }

  @override
  List<Object?> get props => [id, status, isLocalOnly];
}
