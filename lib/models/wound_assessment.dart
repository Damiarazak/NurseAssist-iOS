import 'package:cloud_firestore/cloud_firestore.dart';

/// Data models for wound assessments.
///
/// Key design rule: the original AI prediction is stored once and NEVER
/// overwritten.  Clinician corrections are stored alongside in separate
/// fields so the full model-vs-clinician history is preserved for retraining.
class WoundAssessment {
  final String id;
  final String patientId;
  final String imageUrl;
  final DateTime assessmentDate;
  final WoundAnalysisResult? analysisResult;
  final String? woundPosition;
  final String? additionalNotes;
  final bool requiresSpecialistConfirmation;
  final bool? specialistConfirmed;

  // ── Original AI prediction (set once on creation, never mutated) ────────
  /// The wound type integer (1–8) the TFLite model originally predicted.
  /// Null only for legacy assessments created before this field existed.
  final int? modelPredictedType;

  /// Softmax confidence the model reported for [modelPredictedType].
  final double? modelConfidence;

  // ── Clinician correction (set by nurse / lecturer after reviewing) ───────
  /// The wound type integer the clinician believes is correct.
  /// Null until a clinician explicitly verifies or corrects the result.
  final int? clinicianCorrectedType;

  /// Display name matching [clinicianCorrectedType] (e.g. 'Type_3').
  final String? clinicianCorrectedName;

  /// Staff / user ID of whoever performed the correction.
  final String? correctedBy;

  /// Full name of whoever performed the correction (denormalized for
  /// display so the UI doesn't have to look up the staff record).
  /// Null for legacy records created before this field existed — in that
  /// case the UI should fall back to showing [correctedBy].
  final String? correctedByName;

  /// Timestamp of the clinician correction.
  final DateTime? correctedAt;

  // ── ML training approval (set by Lecturer / Admin only) ─────────────────
  /// True once a Lecturer or Admin has approved this image+label pair for
  /// inclusion in the next model training run.
  final bool approvedForTraining;

  /// User ID of the Lecturer/Admin who approved the image.
  final String? approvedBy;

  /// Timestamp of training approval.
  final DateTime? approvedAt;

  // ── ML training rejection (set by Lecturer / Admin only) ─────────────────
  /// True if a Lecturer or Admin has rejected this image from the training
  /// queue (e.g. poor quality, wrong angle).
  final bool rejectedForTraining;

  /// User ID of whoever rejected the image.
  final String? rejectedBy;

  /// Timestamp of rejection.
  final DateTime? rejectedAt;

  // ── Supervisor type reassignment (set by Supervisor / Admin only) ───────
  /// Wound type the supervisor believes is correct, overriding
  /// [clinicianCorrectedType] for display/training purposes only.
  /// Never overwrites the clinician's own record.
  final int? supervisorCorrectedType;

  /// Display name matching [supervisorCorrectedType] (e.g. 'Type_3').
  final String? supervisorCorrectedName;

  // ── Supervisor feedback (set by Supervisor / Admin only) ─────────────────
  /// Free-text comment left by the supervisor for the nurse to read.
  final String? supervisorFeedback;

  /// Staff / user ID of the supervisor who left the feedback.
  final String? supervisorFeedbackBy;

  /// Timestamp of the supervisor feedback.
  final DateTime? supervisorFeedbackAt;

  /// True whenever a supervisor has left a comment and/or reassigned the
  /// type. Denormalized so the nurse's "needs attention" badge can be
  /// queried with two cheap equality filters.
  final bool hasSupervisorFeedback;

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  WoundAssessment({
    required this.id,
    required this.patientId,
    required this.imageUrl,
    required this.assessmentDate,
    this.analysisResult,
    this.woundPosition,
    this.additionalNotes,
    this.requiresSpecialistConfirmation = false,
    this.specialistConfirmed,
    // AI prediction snapshot
    this.modelPredictedType,
    this.modelConfidence,
    // Clinician correction
    this.clinicianCorrectedType,
    this.clinicianCorrectedName,
    this.correctedBy,
    this.correctedByName,
    this.correctedAt,
    // Training approval
    this.approvedForTraining = false,
    this.approvedBy,
    this.approvedAt,
    // Training rejection
    this.rejectedForTraining = false,
    this.rejectedBy,
    this.rejectedAt,
    // Supervisor type reassignment
    this.supervisorCorrectedType,
    this.supervisorCorrectedName,
    // Supervisor feedback
    this.supervisorFeedback,
    this.supervisorFeedbackBy,
    this.supervisorFeedbackAt,
    this.hasSupervisorFeedback = false,
  });

  /// Returns the wound type to display in the UI.
  /// Prefers the supervisor reassignment, then the clinician correction.
  int get displayWoundType =>
      supervisorCorrectedType ??
      clinicianCorrectedType ??
      analysisResult?.woundType ??
      1;

  /// Returns the wound type name to display.
  String get displayWoundName =>
      supervisorCorrectedName ??
      clinicianCorrectedName ??
      analysisResult?.woundName ??
      'Type_1';

  /// True when a clinician has reviewed and submitted a correction.
  bool get isClinicianVerified => clinicianCorrectedType != null;

  /// True when the clinician agreed with the model (no change needed).
  bool get modelWasCorrect =>
      isClinicianVerified && clinicianCorrectedType == modelPredictedType;

  /// Display string for who verified/corrected this assessment.
  /// Prefers "Name (ID)"; falls back to just the ID for legacy records
  /// that predate [correctedByName].
  String get correctedByDisplay {
    if (correctedByName != null && correctedByName!.isNotEmpty) {
      return correctedBy != null
          ? '$correctedByName ($correctedBy)'
          : correctedByName!;
    }
    return correctedBy ?? 'clinician';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patientId': patientId,
      'imageUrl': imageUrl,
      'assessmentDate': assessmentDate.toIso8601String(),
      'analysisResult': analysisResult?.toJson(),
      'woundPosition': woundPosition,
      'additionalNotes': additionalNotes,
      'requiresSpecialistConfirmation': requiresSpecialistConfirmation,
      'specialistConfirmed': specialistConfirmed,
      // AI snapshot
      'modelPredictedType': modelPredictedType,
      'modelConfidence': modelConfidence,
      // Clinician correction
      'clinicianCorrectedType': clinicianCorrectedType,
      'clinicianCorrectedName': clinicianCorrectedName,
      'correctedBy': correctedBy,
      'correctedByName': correctedByName,
      'correctedAt': correctedAt?.toIso8601String(),
      // Training approval
      'approvedForTraining': approvedForTraining,
      'approvedBy': approvedBy,
      'approvedAt': approvedAt?.toIso8601String(),
      // Training rejection
      'rejectedForTraining': rejectedForTraining,
      'rejectedBy': rejectedBy,
      'rejectedAt': rejectedAt?.toIso8601String(),
      // Supervisor type reassignment
      'supervisorCorrectedType': supervisorCorrectedType,
      'supervisorCorrectedName': supervisorCorrectedName,
      // Supervisor feedback
      'supervisorFeedback': supervisorFeedback,
      'supervisorFeedbackBy': supervisorFeedbackBy,
      'supervisorFeedbackAt': supervisorFeedbackAt?.toIso8601String(),
      'hasSupervisorFeedback': hasSupervisorFeedback,
    };
  }

  factory WoundAssessment.fromJson(Map<String, dynamic> json) {
    return WoundAssessment(
      id: json['id'],
      patientId: json['patientId'],
      imageUrl: json['imageUrl'],
      assessmentDate: DateTime.parse(json['assessmentDate']),
      analysisResult: json['analysisResult'] != null
          ? WoundAnalysisResult.fromJson(json['analysisResult'])
          : null,
      woundPosition: json['woundPosition'],
      additionalNotes: json['additionalNotes'],
      requiresSpecialistConfirmation:
          json['requiresSpecialistConfirmation'] ?? false,
      specialistConfirmed: json['specialistConfirmed'],
      // AI snapshot — null-safe for legacy documents
      modelPredictedType: json['modelPredictedType'],
      modelConfidence: (json['modelConfidence'] as num?)?.toDouble(),
      // Clinician correction
      clinicianCorrectedType: json['clinicianCorrectedType'],
      clinicianCorrectedName: json['clinicianCorrectedName'],
      correctedBy: json['correctedBy'],
      correctedByName: json['correctedByName'],
      correctedAt: _parseDate(json['correctedAt']),
      // Training approval
      approvedForTraining: json['approvedForTraining'] ?? false,
      approvedBy: json['approvedBy'],
      approvedAt: _parseDate(json['approvedAt']),
      // Training rejection
      rejectedForTraining: json['rejectedForTraining'] ?? false,
      rejectedBy: json['rejectedBy'],
      rejectedAt: _parseDate(json['rejectedAt']),
      // Supervisor type reassignment
      supervisorCorrectedType: json['supervisorCorrectedType'],
      supervisorCorrectedName: json['supervisorCorrectedName'],
      // Supervisor feedback
      supervisorFeedback: json['supervisorFeedback'],
      supervisorFeedbackBy: json['supervisorFeedbackBy'],
      supervisorFeedbackAt: _parseDate(json['supervisorFeedbackAt']),
      hasSupervisorFeedback: json['hasSupervisorFeedback'] ?? false,
    );
  }

  WoundAssessment copyWith({
    String? woundPosition,
    String? additionalNotes,
    bool? requiresSpecialistConfirmation,
    bool? specialistConfirmed,
    WoundAnalysisResult? analysisResult,
    int? clinicianCorrectedType,
    String? clinicianCorrectedName,
    String? correctedBy,
    String? correctedByName,
    DateTime? correctedAt,
    bool? approvedForTraining,
    String? approvedBy,
    DateTime? approvedAt,
    bool? rejectedForTraining,
    String? rejectedBy,
    DateTime? rejectedAt,
    int? supervisorCorrectedType,
    String? supervisorCorrectedName,
    String? supervisorFeedback,
    String? supervisorFeedbackBy,
    DateTime? supervisorFeedbackAt,
    bool? hasSupervisorFeedback,
  }) {
    return WoundAssessment(
      id: id,
      patientId: patientId,
      imageUrl: imageUrl,
      assessmentDate: assessmentDate,
      analysisResult: analysisResult ?? this.analysisResult,
      woundPosition: woundPosition ?? this.woundPosition,
      additionalNotes: additionalNotes ?? this.additionalNotes,
      requiresSpecialistConfirmation:
          requiresSpecialistConfirmation ?? this.requiresSpecialistConfirmation,
      specialistConfirmed: specialistConfirmed ?? this.specialistConfirmed,
      // AI snapshot is immutable — always carry original values through
      modelPredictedType: modelPredictedType,
      modelConfidence: modelConfidence,
      // Clinician correction
      clinicianCorrectedType:
          clinicianCorrectedType ?? this.clinicianCorrectedType,
      clinicianCorrectedName:
          clinicianCorrectedName ?? this.clinicianCorrectedName,
      correctedBy: correctedBy ?? this.correctedBy,
      correctedByName: correctedByName ?? this.correctedByName,
      correctedAt: correctedAt ?? this.correctedAt,
      // Training approval
      approvedForTraining: approvedForTraining ?? this.approvedForTraining,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      // Training rejection
      rejectedForTraining: rejectedForTraining ?? this.rejectedForTraining,
      rejectedBy: rejectedBy ?? this.rejectedBy,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      // Supervisor type reassignment
      supervisorCorrectedType:
          supervisorCorrectedType ?? this.supervisorCorrectedType,
      supervisorCorrectedName:
          supervisorCorrectedName ?? this.supervisorCorrectedName,
      // Supervisor feedback
      supervisorFeedback: supervisorFeedback ?? this.supervisorFeedback,
      supervisorFeedbackBy: supervisorFeedbackBy ?? this.supervisorFeedbackBy,
      supervisorFeedbackAt: supervisorFeedbackAt ?? this.supervisorFeedbackAt,
      hasSupervisorFeedback:
          hasSupervisorFeedback ?? this.hasSupervisorFeedback,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class WoundAnalysisResult {
  final double confidenceScore;
  final int woundType; // 1-8
  final String woundName;
  final String severity;
  final double?
  estimatedSize; // in cm², null until nurse measures and enters it
  final WoundCharacteristics characteristics;
  final WoundManagement management;
  final String? segmentationMapUrl;

  /// Softmax probabilities for all 8 types from the TFLite model.
  /// Index 0 = Type_1 … index 7 = Type_8.
  /// Null when the cloud or mock backend was used.
  final List<double>? allClassProbabilities;

  WoundAnalysisResult({
    required this.confidenceScore,
    required this.woundType,
    required this.woundName,
    required this.severity,
    this.estimatedSize,
    required this.characteristics,
    required this.management,
    this.segmentationMapUrl,
    this.allClassProbabilities,
  });

  Map<String, dynamic> toJson() {
    return {
      'confidenceScore': confidenceScore,
      'woundType': woundType,
      'woundName': woundName,
      'severity': severity,
      'estimatedSize': estimatedSize,
      'characteristics': characteristics.toJson(),
      'management': management.toJson(),
      'segmentationMapUrl': segmentationMapUrl,
      'allClassProbabilities': allClassProbabilities,
    };
  }

  factory WoundAnalysisResult.fromJson(Map<String, dynamic> json) {
    return WoundAnalysisResult(
      confidenceScore: (json['confidenceScore'] as num).toDouble(),
      woundType: json['woundType'],
      woundName: json['woundName'],
      severity: json['severity'],
      estimatedSize: (json['estimatedSize'] as num?)?.toDouble(),
      characteristics: WoundCharacteristics.fromJson(json['characteristics']),
      management: WoundManagement.fromJson(json['management']),
      segmentationMapUrl: json['segmentationMapUrl'],
      allClassProbabilities: json['allClassProbabilities'] != null
          ? List<double>.from(
              (json['allClassProbabilities'] as List).map(
                (e) => (e as num).toDouble(),
              ),
            )
          : null,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class WoundCharacteristics {
  final String necroticTissue;
  final String infection;
  final String exudateLevel;
  final List<String> tissueClassification;

  WoundCharacteristics({
    required this.necroticTissue,
    required this.infection,
    required this.exudateLevel,
    required this.tissueClassification,
  });

  Map<String, dynamic> toJson() => {
    'necroticTissue': necroticTissue,
    'infection': infection,
    'exudateLevel': exudateLevel,
    'tissueClassification': tissueClassification,
  };

  factory WoundCharacteristics.fromJson(Map<String, dynamic> json) =>
      WoundCharacteristics(
        necroticTissue: json['necroticTissue'],
        infection: json['infection'],
        exudateLevel: json['exudateLevel'],
        tissueClassification: List<String>.from(json['tissueClassification']),
      );
}

// ──────────────────────────────────────────────────────────────────────────────

class WoundManagement {
  final List<String> dressingMaterials;
  final String antibioticRecommendation;
  final List<String> surgicalProcedures;
  final String? additionalNotes;

  WoundManagement({
    required this.dressingMaterials,
    required this.antibioticRecommendation,
    required this.surgicalProcedures,
    this.additionalNotes,
  });

  Map<String, dynamic> toJson() => {
    'dressingMaterials': dressingMaterials,
    'antibioticRecommendation': antibioticRecommendation,
    'surgicalProcedures': surgicalProcedures,
    'additionalNotes': additionalNotes,
  };

  factory WoundManagement.fromJson(Map<String, dynamic> json) =>
      WoundManagement(
        dressingMaterials: List<String>.from(json['dressingMaterials']),
        antibioticRecommendation: json['antibioticRecommendation'],
        surgicalProcedures: List<String>.from(json['surgicalProcedures']),
        additionalNotes: json['additionalNotes'],
      );
}
