import 'dart:io';
import 'package:flutter/material.dart';
import '../models/patient.dart';
import '../models/wound_assessment.dart';
import '../models/wound_types_database.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme.dart';

class AnalysisResultsScreen extends StatefulWidget {
  final Patient patient;
  final WoundAssessment assessment;

  const AnalysisResultsScreen({
    super.key,
    required this.patient,
    required this.assessment,
  });

  @override
  State<AnalysisResultsScreen> createState() => _AnalysisResultsScreenState();
}

class _AnalysisResultsScreenState extends State<AnalysisResultsScreen> {
  final TextEditingController _notesController = TextEditingController();
  bool _specialistConfirmed = false;
  final FirestoreService _firestoreService = FirestoreService();
  late WoundAssessment _assessment;

  // Accordion expansion state
  final Map<int, bool> _sectionExpanded = {1: true, 2: true, 3: true};

  // Editable assessment fields
  final TextEditingController _woundNameController = TextEditingController();
  final TextEditingController _estimatedSizeController =
      TextEditingController();
  final TextEditingController _dressingController = TextEditingController();
  final TextEditingController _antibioticController = TextEditingController();
  final TextEditingController _surgicalController = TextEditingController();
  final TextEditingController _managementNotesController =
      TextEditingController();
  int _woundType = 1;
  String _severity = 'Moderate';

  @override
  void initState() {
    super.initState();
    _assessment = widget.assessment;
    _notesController.text = _assessment.additionalNotes ?? '';
    _specialistConfirmed = _assessment.specialistConfirmed ?? false;
    _initEditableFields();
  }

  Future<void> _saveAssessment() async {
    try {
      final updatedAssessment = _buildUpdatedAssessment(
        analysisResult: _assessment.analysisResult,
        notes: _notesController.text,
        specialistConfirmed: _specialistConfirmed,
      );

      await _firestoreService.updateWoundAssessment(updatedAssessment);

      setState(() {
        _assessment = updatedAssessment;
      });

      if (mounted) {
        showSuccessSnack(context, 'Assessment saved successfully');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, 'Error saving: $e');
      }
    }
  }

  Color _getSeverityColor(String severity) {
    switch (_normalizeSeverity(severity).toLowerCase()) {
      case 'critical':
        return const Color(0xFFD32F2F);
      case 'moderate':
        return const Color(0xFFE65100);
      case 'mild':
        return const Color(0xFF2E7D32);
      default:
        return Colors.grey.shade700;
    }
  }

  Color _getSeverityBgColor(String severity) {
    switch (_normalizeSeverity(severity).toLowerCase()) {
      case 'critical':
        return const Color(0xFFFFEBEB);
      case 'moderate':
        return const Color(0xFFFFF3E0);
      case 'mild':
        return const Color(0xFFE8F5E9);
      default:
        return Colors.grey.shade100;
    }
  }

  /// Maps any AI-generated severity string to one of the 3 valid dropdown values.
  /// e.g. "Moderate to Critical", "CRITICAL RISK", "moderately severe" → 'Critical'/'Moderate'/'Mild'
  String _normalizeSeverity(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('critical')) return 'Critical';
    if (lower.contains('mild')) return 'Mild';
    if (lower.contains('moderate')) return 'Moderate';
    return 'Moderate'; // safe fallback
  }

  void _initEditableFields() {
    final result = _assessment.analysisResult;
    if (result == null) return;

    _woundType = result.woundType;
    _severity = result.severity;
    _woundNameController.text = result.woundName;
    _estimatedSizeController.text =
        result.estimatedSize?.toStringAsFixed(1) ?? '';
    _dressingController.text = result.management.dressingMaterials.join(', ');
    _antibioticController.text = result.management.antibioticRecommendation;
    _surgicalController.text = result.management.surgicalProcedures.join(', ');
    _managementNotesController.text = result.management.additionalNotes ?? '';
  }

  /// Rebuilds the assessment preserving ALL fields — including the immutable
  /// AI prediction snapshot and any existing clinician correction.
  /// Uses copyWith so correction fields are never accidentally cleared.
  WoundAssessment _buildUpdatedAssessment({
    WoundAnalysisResult? analysisResult,
    String? notes,
    bool? specialistConfirmed,
  }) {
    return _assessment.copyWith(
      analysisResult: analysisResult,
      additionalNotes: notes,
      specialistConfirmed: specialistConfirmed,
    );
  }

  // ─── Management data per wound type ────────────────────────────
  Map<String, dynamic> _getManagementInfo(int woundType) {
    final typeName = WoundTypesDatabase.getWoundTypeName(woundType);
    final data = WoundTypesDatabase.getWoundTypeData(typeName);
    final management = Map<String, dynamic>.from(
      data['management'] as Map<String, dynamic>,
    );

    return {
      'dressing': List<String>.from(management['dressingMaterials'] as List),
      'dressingNotes': null,
      'antibiotic': management['antibioticRecommendation'] as String,
      'surgical': List<String>.from(management['surgicalProcedures'] as List),
      'requiresSpecialistConfirmation':
          WoundTypesDatabase.requiresSpecialistConfirmation(typeName),
    };
  }

  // ─── Characteristics per wound type, sourced from WoundTypesDatabase ──
  /// Returns the "typical" characteristics (necrotic tissue, infection,
  /// exudate, tissue classification) for [woundType]. Unlike the AI's
  /// frozen `result.characteristics` snapshot, this is looked up live from
  /// the reference table, so it updates whenever the displayed wound type
  /// changes (clinician correction or supervisor reassignment) — the same
  /// way [_getManagementInfo] already does for dressing/antibiotics/surgical.
  Map<String, dynamic> _getCharacteristicsInfo(int woundType) {
    final typeName = WoundTypesDatabase.getWoundTypeName(woundType);
    final data = WoundTypesDatabase.getWoundTypeData(typeName);
    return Map<String, dynamic>.from(
      data['characteristics'] as Map<String, dynamic>,
    );
  }

  Future<void> _openEditAssessment() async {
    final current = _assessment.analysisResult;
    if (current == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No analysis data to edit')));
      return;
    }

    // Local copies so changes only apply on Save
    int localWoundType = _woundType.clamp(1, 8); // guard against out-of-range
    String localSeverity = _normalizeSeverity(_severity); // guard AI free-text
    final localNameCtrl = TextEditingController(
      text: _woundNameController.text,
    );
    final localSizeCtrl = TextEditingController(
      text: _estimatedSizeController.text,
    );
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFEEF2FF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Drag handle ────────────────────────────────
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Header ─────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.edit_outlined,
                            color: Colors.blue.shade700,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Edit Assessment',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.grey.shade500),
                          onPressed: () => Navigator.of(context).pop(),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  Divider(height: 1, color: Colors.grey.shade200),

                  // ── Form body ──────────────────────────────────
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Wound Name
                            _editLabel('Wound Name'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: localNameCtrl,
                              decoration: _editInputDecoration(
                                'e.g. Diabetic Foot Ulcer',
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Wound name is required'
                                  : null,
                            ),

                            const SizedBox(height: 16),

                            // Wound Type + Severity row
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _editLabel('Wound Type'),
                                      const SizedBox(height: 6),
                                      DropdownButtonFormField<int>(
                                        initialValue: localWoundType,
                                        decoration: _editInputDecoration(null),
                                        items: List.generate(
                                          8,
                                          (i) => DropdownMenuItem(
                                            value: i + 1,
                                            child: Text('Type ${i + 1}'),
                                          ),
                                        ),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setModalState(
                                              () => localWoundType = val,
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _editLabel('Severity'),
                                      const SizedBox(height: 6),
                                      DropdownButtonFormField<String>(
                                        initialValue: localSeverity,
                                        decoration: _editInputDecoration(null),
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'Critical',
                                            child: Text('Critical'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'Moderate',
                                            child: Text('Moderate'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'Mild',
                                            child: Text('Mild'),
                                          ),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) {
                                            setModalState(
                                              () => localSeverity = val,
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Estimated Size
                            _editLabel('Estimated Size (cm²)'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: localSizeCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: _editInputDecoration('e.g. 15.0'),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                final d = double.tryParse(v.trim());
                                if (d == null || d <= 0) {
                                  return 'Enter a valid positive number';
                                }
                                return null;
                              },
                            ),

                            // Info note — management auto-updates
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade100),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 14,
                                    color: Colors.blue.shade600,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Wound management recommendations update automatically when wound type changes.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Save button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (!formKey.currentState!.validate()) {
                                    return;
                                  }

                                  final updatedResult = WoundAnalysisResult(
                                    confidenceScore: current.confidenceScore,
                                    woundType: localWoundType,
                                    woundName: localNameCtrl.text.trim(),
                                    severity: localSeverity,
                                    estimatedSize:
                                        localSizeCtrl.text.trim().isEmpty
                                        ? null
                                        : double.tryParse(
                                            localSizeCtrl.text.trim(),
                                          ),
                                    characteristics: current.characteristics,
                                    management: current.management,
                                    segmentationMapUrl:
                                        current.segmentationMapUrl,
                                    // Preserve softmax probabilities so the
                                    // correction sheet still shows bars after edit
                                    allClassProbabilities:
                                        current.allClassProbabilities,
                                  );

                                  final updatedAssessment =
                                      _buildUpdatedAssessment(
                                        analysisResult: updatedResult,
                                        notes: _notesController.text,
                                        specialistConfirmed:
                                            _specialistConfirmed,
                                      );

                                  // Capture before async gap
                                  final nav = Navigator.of(context);

                                  await _firestoreService.updateWoundAssessment(
                                    updatedAssessment,
                                  );

                                  if (mounted) {
                                    setState(() {
                                      _assessment = updatedAssessment;
                                      _woundType = localWoundType;
                                      _severity = localSeverity;
                                      _woundNameController.text =
                                          localNameCtrl.text;
                                      _estimatedSizeController.text =
                                          localSizeCtrl.text;
                                    });
                                    nav.pop();
                                    showSuccessSnack(
                                      context,
                                      'Assessment updated',
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Save Changes',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  CORRECT WOUND TYPE — focused clinician correction sheet
  // ════════════════════════════════════════════════════════════════

  /// Display names shown in the correction picker.
  /// Severity ascends with type number: Type 1 = mildest, Type 8 = Critical.
  static const _typeLabels = {
    1: 'Type 1',
    2: 'Type 2',
    3: 'Type 3 ⚠',
    4: 'Type 4 ⚠',
    5: 'Type 5',
    6: 'Type 6 ⚠',
    7: 'Type 7',
    8: 'Type 8 🚨',
  };

  Future<void> _openCorrectTypeSheet() async {
    final result = _assessment.analysisResult;
    if (result == null) return;

    // Per-type probabilities from TFLite (null if cloud/mock was used)
    final probs = result.allClassProbabilities;

    // Start with whatever is currently displayed
    int selected = _assessment.displayWoundType;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFEEF2FF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.verified_user_outlined,
                      color: Colors.orange.shade700,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Verify / Correct Wound Type',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.grey.shade500),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // AI prediction reminder
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 16,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AI predicted: Type ${result.woundType}  '
                        '(${(result.confidenceScore * 100).toStringAsFixed(0)}% confidence)',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Type selector list
              ...List.generate(8, (i) {
                final typeId = i + 1;
                final isSelected = selected == typeId;
                final isSpecialist =
                    WoundTypesDatabase.requiresSpecialistConfirmation(
                      'Type_$typeId',
                    );
                // Per-type probability from TFLite (index i = Type_typeId)
                final prob = probs != null && i < probs.length
                    ? probs[i]
                    : null;
                final probPct = prob != null
                    ? (prob * 100).toStringAsFixed(1)
                    : null;

                return GestureDetector(
                  onTap: () => setSheet(() => selected = typeId),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue.shade700 : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? Colors.blue.shade700
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.grey.shade400,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _typeLabels[typeId] ?? 'Type $typeId',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            // Probability badge
                            if (probPct != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.25)
                                      : _probColor(
                                          prob!,
                                        ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$probPct%',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? Colors.white
                                        : _probColor(prob!),
                                  ),
                                ),
                              ),
                            if (isSpecialist && !isSelected)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: Colors.orange.shade600,
                                ),
                              ),
                          ],
                        ),
                        // Probability bar (only when probabilities available)
                        if (prob != null) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: prob,
                              minHeight: 4,
                              backgroundColor: isSelected
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : Colors.grey.shade100,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isSelected
                                    ? Colors.white.withValues(alpha: 0.85)
                                    : _probColor(prob),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 16),

              // Confirm button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Confirm Correction'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _submitCorrection(selected);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Persist the clinician correction and update local state.
  Future<void> _submitCorrection(int correctedTypeId) async {
    final correctedName = 'Type_$correctedTypeId';
    final staff = AuthService().loggedInStaff;
    // Use the logged-in staff's ID; fall back to email prefix if cache is cold
    final staffId =
        staff?.staffId ??
        AuthService().currentUser?.email?.split('@')[0].toUpperCase() ??
        'unknown';
    // Full name of the logged-in staff, so the UI can show "Jane Tan (WRN-001)"
    // instead of just the ID. Null for legacy/cold-cache cases, in which
    // case the UI falls back to the ID alone (see correctedByDisplay).
    final staffName = staff?.name;

    try {
      await _firestoreService.saveClinicianCorrection(
        assessmentId: _assessment.id,
        correctedType: correctedTypeId,
        correctedName: correctedName,
        correctedBy: staffId,
        correctedByName: staffName,
      );

      // Rebuild management panel for the corrected type
      setState(() {
        _assessment = _assessment.copyWith(
          clinicianCorrectedType: correctedTypeId,
          clinicianCorrectedName: correctedName,
          correctedBy: staffId,
          correctedByName: staffName,
          correctedAt: DateTime.now(),
          requiresSpecialistConfirmation:
              WoundTypesDatabase.requiresSpecialistConfirmation(correctedName),
          specialistConfirmed: false,
        );
        _woundType = correctedTypeId;
        _woundNameController.text = correctedName;
      });

      if (mounted) {
        showSuccessSnack(
          context,
          correctedTypeId == _assessment.modelPredictedType
              ? '✓ AI result confirmed as $correctedName'
              : '✓ Corrected to $correctedName — saved for training review',
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, 'Error saving correction: $e');
      }
    }
  }

  /// Colour for a probability bar: green ≥ 50%, amber 25–50%, grey < 25%.
  Color _probColor(double prob) {
    if (prob >= 0.50) return Colors.green.shade600;
    if (prob >= 0.25) return Colors.amber.shade700;
    return Colors.grey.shade400;
  }

  // ── Edit sheet helpers ─────────────────────────────────────────
  Widget _editLabel(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.grey.shade600,
      letterSpacing: 0.3,
    ),
  );

  InputDecoration _editInputDecoration(String? hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade200),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade200),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.blue, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.red),
    ),
  );

  // ════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final result = _assessment.analysisResult;
    if (result == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Analysis Results')),
        body: const Center(child: Text('No analysis result available')),
      );
    }

    // Use clinician-corrected type for management if one exists
    final mgmt = _getManagementInfo(_assessment.displayWoundType);
    // Characteristics now follow the displayed type too, so correcting the
    // wound type (clinician or supervisor) updates this section just like
    // it already updates Wound Management below.
    final characteristics = _getCharacteristicsInfo(
      _assessment.displayWoundType,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFEEF2FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Analysis Results',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            Text(
              '${widget.patient.name}  •  ${widget.patient.age}y ${widget.patient.gender}',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _openEditAssessment,
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('Edit'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 1. AI Confidence Banner ───────────────────────────
            _buildConfidenceBanner(result),

            // ── 1b. Clinician Verification Card ──────────────────
            _buildVerificationCard(result),

            // ── 2. Wound Photo ────────────────────────────────────
            _buildWoundPhoto(),

            // ── 3. Classification + Severity + Patient ────────────
            _buildInfoRow(result),

            if ((_assessment.woundPosition ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildWoundPositionCard(_assessment.woundPosition!.trim()),
            ],

            const SizedBox(height: 14),

            // ── 4. Wound Characteristics ──────────────────────────
            _buildAccordionSection(
              number: 1,
              title: 'Wound Characteristics',
              child: _buildCharacteristicsContent(characteristics),
            ),

            const SizedBox(height: 10),

            // ── 5. Wound Management ───────────────────────────────
            _buildAccordionSection(
              number: 2,
              title: 'Wound Management',
              child: _buildWoundManagementContent(result, mgmt),
            ),

            const SizedBox(height: 10),

            // ── 6. Clinical Notes ─────────────────────────────────
            _buildAccordionSection(
              number: 3,
              title: 'Clinical Notes',
              child: _buildClinicalNotesContent(),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildWoundPositionCard(String woundPosition) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE4F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.place_outlined, color: kPrimary, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Wound Location: $woundPosition',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2A3440),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  AI CONFIDENCE BANNER
  // ════════════════════════════════════════════════════════════════
  Widget _buildConfidenceBanner(WoundAnalysisResult result) {
    final pct = (result.confidenceScore * 100).toInt();
    final Color barColor = pct >= 90
        ? const Color(0xFF00C853)
        : pct >= 70
        ? Colors.orange
        : Colors.red;
    final String label = pct >= 90
        ? 'High Confidence'
        : pct >= 70
        ? 'Moderate Confidence'
        : 'Low Confidence';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade800, Colors.blue.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon badge
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.analytics_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          // Label + bar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Analysis Confidence',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: barColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: result.confidenceScore,
                    minHeight: 7,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Based on wound image analysis',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // Large percentage
          Column(
            children: [
              Text(
                '$pct%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'score',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  WOUND PHOTO
  // ════════════════════════════════════════════════════════════════
  Widget _buildWoundPhoto() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            SizedBox(
              height: 220,
              width: double.infinity,
              child: _assessment.imageUrl.startsWith('http')
                  ? Image.network(_assessment.imageUrl, fit: BoxFit.cover)
                  : Image.file(
                      File(_assessment.imageUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey.shade300,
                        child: const Icon(
                          Icons.image_not_supported,
                          size: 60,
                          color: Colors.grey,
                        ),
                      ),
                    ),
            ),
            // Gradient overlay at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 60,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
            ),
            // Full Resolution button
            Positioned(
              bottom: 10,
              left: 12,
              child: GestureDetector(
                onTap: () => _showImageDialog(context, _assessment.imageUrl),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.zoom_out_map_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Full Resolution',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  CLINICIAN VERIFICATION CARD
  // ════════════════════════════════════════════════════════════════
  Widget _buildVerificationCard(WoundAnalysisResult result) {
    final pct = (result.confidenceScore * 100).toInt();
    final isVerified = _assessment.isClinicianVerified;

    // ── Already verified ───────────────────────────────────────────
    if (isVerified) {
      final agreed = _assessment.modelWasCorrect;
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: agreed ? Colors.green.shade50 : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: agreed ? Colors.green.shade200 : Colors.orange.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(
              agreed ? Icons.check_circle : Icons.swap_horiz,
              color: agreed ? Colors.green.shade700 : Colors.orange.shade700,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agreed
                        ? 'AI result confirmed by clinician'
                        : 'Corrected to ${_assessment.clinicianCorrectedName}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: agreed
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                  if (!agreed)
                    Text(
                      'AI predicted: Type ${result.woundType}  '
                      '($pct%)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  // Shows "Jane Tan (WRN-001)" when the staff's name was
                  // captured; falls back to just the ID for legacy records.
                  Text(
                    'Verified by ${_assessment.correctedByDisplay}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            // Allow re-correction
            TextButton(
              onPressed: _openCorrectTypeSheet,
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Change', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    // ── Not yet verified — show action card ────────────────────────
    final isLowConf = pct < 70;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isLowConf ? Colors.red.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLowConf ? Colors.red.shade200 : Colors.amber.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isLowConf ? Icons.warning_rounded : Icons.info_outline,
            color: isLowConf ? Colors.red.shade700 : Colors.amber.shade800,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isLowConf
                  ? 'Low confidence ($pct%) — clinician verification required'
                  : 'Please verify the AI result before saving',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isLowConf ? Colors.red.shade800 : Colors.amber.shade900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _openCorrectTypeSheet,
            style: ElevatedButton.styleFrom(
              backgroundColor: isLowConf
                  ? Colors.red.shade700
                  : Colors.amber.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: const Text('Verify', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  CLASSIFICATION + SEVERITY + PATIENT ROW
  // ════════════════════════════════════════════════════════════════
  Widget _buildInfoRow(WoundAnalysisResult result) {
    final severityBg = _getSeverityBgColor(result.severity);
    final severityFg = _getSeverityColor(result.severity);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Classification — plain text, no border (matches reference)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CLASSIFICATION',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Wound Type ${_assessment.displayWoundType}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _assessment.displayWoundName,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Severity — floating pill badge (matches reference)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: severityBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SEVERITY',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: severityFg.withValues(alpha: 0.75),
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  result.severity,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: severityFg,
                  ),
                ),
                if (result.estimatedSize != null)
                  Text(
                    '${result.estimatedSize!.toStringAsFixed(1)} cm²',
                    style: TextStyle(
                      fontSize: 11,
                      color: severityFg.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  ACCORDION WRAPPER
  // ════════════════════════════════════════════════════════════════
  Widget _buildAccordionSection({
    required int number,
    required String title,
    required Widget child,
  }) {
    final isExpanded = _sectionExpanded[number] ?? true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Numbered circle
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: Color(0xFF1565C0),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Card
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header
                  InkWell(
                    borderRadius: isExpanded
                        ? const BorderRadius.vertical(top: Radius.circular(12))
                        : BorderRadius.circular(12),
                    onTap: () => setState(() {
                      _sectionExpanded[number] = !isExpanded;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: Colors.grey.shade500,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Content
                  if (isExpanded) ...[
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.grey.shade100,
                    ),
                    Padding(padding: const EdgeInsets.all(16), child: child),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  SECTION 1 — WOUND CHARACTERISTICS
  // ════════════════════════════════════════════════════════════════
  /// Renders the Wound Characteristics section from a per-type reference
  /// map (see [_getCharacteristicsInfo]) rather than the AI's one-time
  /// image observation, so it stays in sync with clinician/supervisor
  /// corrections to the wound type.
  Widget _buildCharacteristicsContent(Map<String, dynamic> characteristics) {
    final necroticTissue = characteristics['necroticTissue'] as String? ?? '—';
    final infection = characteristics['infection'] as String? ?? '—';
    final exudateLevel = characteristics['exudateLevel'] as String? ?? '—';
    final tissueClassification =
        (characteristics['tissueClassification'] as List?)?.cast<String>() ??
        const <String>[];

    // Necrotic tissue: the reference table uses '<', '>' and range wording
    // (e.g. '< 10%', '25–50%', '> 50% (extensive)'). Treat any '>' figure
    // as the high/red case; everything else (including ranges without a
    // leading '<' or '>') falls back to the amber "moderate" styling.
    final necroticIsHigh = necroticTissue.contains('>');
    final necroticColor = necroticIsHigh
        ? Colors.red.shade600
        : Colors.orange.shade700;

    // Infection: reference strings are things like 'No infection',
    // 'Infection present (local signs)', 'Severe infection'. Anything that
    // doesn't explicitly start with 'No' counts as infection present.
    final hasInfection = !infection.toLowerCase().trim().startsWith('no');
    final infectionColor = hasInfection
        ? Colors.red.shade600
        : Colors.green.shade700;
    final infectionIcon = hasInfection
        ? Icons.error_rounded
        : Icons.check_circle_rounded;

    // Exudate: colour by severity keyword rather than a crude dry/wet
    // split, since the reference strings range from 'Minimal / Serous' up
    // to 'Heavy / Malodorous / Purulent'.
    final exudateLower = exudateLevel.toLowerCase();
    final Color exudateColor = exudateLower.contains('heavy')
        ? Colors.red.shade600
        : exudateLower.contains('moderate')
        ? Colors.orange.shade700
        : Colors.green.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1) Tissue
        _buildCharRow(
          label: 'Tissue',
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [_buildChip(necroticTissue, necroticColor)],
          ),
        ),
        const SizedBox(height: 10),

        // 2) Infection
        _buildCharRow(
          label: 'Infection',
          child: Row(
            children: [
              Icon(infectionIcon, color: infectionColor, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  infection,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: infectionColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 3) Moisture
        _buildCharRow(
          label: 'Moisture',
          child: _buildChip(exudateLevel, exudateColor),
        ),
        const SizedBox(height: 10),

        // 4) Edges
        _buildCharRow(
          label: 'Edges',
          child: _buildChip(
            'No specific edge findings recorded',
            Colors.indigo.shade600,
          ),
        ),
        const SizedBox(height: 10),

        // 5) Tissue description
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tissue description',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            tissueClassification.isEmpty
                ? _buildChip(
                    'No tissue description recorded',
                    Colors.blue.shade700,
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: tissueClassification
                        .map((t) => _buildChip(t, Colors.blue.shade700))
                        .toList(),
                  ),
          ],
        ),
      ],
    );
  }

  Widget _buildCharRow({required String label, required Widget child}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 135,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  SECTION 2 — WOUND MANAGEMENT
  // ════════════════════════════════════════════════════════════════
  Widget _buildWoundManagementContent(
    WoundAnalysisResult result,
    Map<String, dynamic> mgmt,
  ) {
    final dressing = mgmt['dressing'] as List<String>;
    final dressingNotes = mgmt['dressingNotes'] as String?;
    final antibiotic = mgmt['antibiotic'] as String;
    final surgical = mgmt['surgical'] as List<String>;
    final requiresConfirmation = mgmt['requiresSpecialistConfirmation'] as bool;

    final antibioticIsYes = antibiotic.toLowerCase().startsWith('yes');
    final antibioticIsMaybe = antibiotic.toLowerCase().startsWith('may');
    final antibioticColor = antibioticIsYes
        ? Colors.red.shade700
        : antibioticIsMaybe
        ? Colors.orange.shade700
        : Colors.green.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dressing
        _buildMgmtHeader(
          Icons.medical_services_outlined,
          'Dressing Recommended',
          Colors.blue.shade700,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: dressing
              .map((d) => _buildChip(d, Colors.blue.shade700))
              .toList(),
        ),
        if (dressingNotes != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Text(
              dressingNotes,
              style: TextStyle(
                fontSize: 11,
                color: Colors.amber.shade900,
                height: 1.5,
              ),
            ),
          ),
        ],

        const SizedBox(height: 14),
        Divider(height: 1, color: Colors.grey.shade100),
        const SizedBox(height: 14),

        // Antibiotics + Surgical
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Antibiotics column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMgmtHeader(
                    Icons.medication_outlined,
                    'Antibiotics',
                    antibioticColor,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    antibioticIsYes
                        ? 'Required: Yes'
                        : antibioticIsMaybe
                        ? 'May be required'
                        : 'Not required',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: antibioticColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Based on the tissue C&S and the current guidelines.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  if (antibioticIsYes || antibioticIsMaybe) ...[
                    const SizedBox(height: 4),
                    Text(
                      antibiotic.contains(',')
                          ? antibiotic
                                .substring(antibiotic.indexOf(',') + 1)
                                .trim()
                          : antibiotic,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Surgical column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMgmtHeader(
                    Icons.local_hospital_outlined,
                    'Surgical',
                    Colors.purple.shade700,
                  ),
                  const SizedBox(height: 6),
                  ...surgical.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        s,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // Specialist confirmation checkbox (types 3, 4, 6)
        if (requiresConfirmation) ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () =>
                setState(() => _specialistConfirmed = !_specialistConfirmed),
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _specialistConfirmed,
                    onChanged: (value) =>
                        setState(() => _specialistConfirmed = value ?? false),
                    activeColor: Colors.blue,
                    side: BorderSide(color: Colors.grey.shade400),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Confirm Specialist Notified',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Text(
              'Required before saving — specialist must confirm debridement is needed',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMgmtHeader(IconData icon, String title, Color color) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  SECTION 3 — CLINICAL NOTES
  // ════════════════════════════════════════════════════════════════
  Widget _buildClinicalNotesContent() {
    return TextField(
      controller: _notesController,
      maxLines: 4,
      decoration: InputDecoration(
        hintText:
            'Enter clinical observations:\n- Edges\n- Periwound/surrounding skin',
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.blue),
        ),
        contentPadding: const EdgeInsets.all(12),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  BOTTOM ACTION BAR
  // ════════════════════════════════════════════════════════════════
  Widget _buildBottomBar() {
    final needsGating = WoundTypesDatabase.requiresSpecialistConfirmation(
      WoundTypesDatabase.getWoundTypeName(_assessment.displayWoundType),
    );
    final isSaveBlocked = needsGating && !_specialistConfirmed;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (needsGating)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kWarningBg,
              borderRadius: BorderRadius.circular(kRadiusLg),
              border: Border.all(color: kWarning.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 22,
                      color: kWarning,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Specialist confirmation required',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kWarning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Please notify a specialist before saving this assessment.',
                  style: TextStyle(fontSize: 13, color: kInk2),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  value: _specialistConfirmed,
                  onChanged: (v) =>
                      setState(() => _specialistConfirmed = v ?? false),
                  title: const Text(
                    'I have notified the specialist',
                    style: TextStyle(fontSize: 13),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: kWarning,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: isSaveBlocked ? null : _saveAssessment,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Assessment'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white.withValues(
                      alpha: 0.7,
                    ),
                    disabledBackgroundColor: kPrimary.withValues(alpha: 0.45),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  FULL RESOLUTION IMAGE DIALOG
  // ════════════════════════════════════════════════════════════════
  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                imageUrl.startsWith('http')
                    ? Image.network(imageUrl)
                    : Image.file(
                        File(imageUrl),
                        height: 300,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 300,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.error, size: 100),
                        ),
                      ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    _woundNameController.dispose();
    _estimatedSizeController.dispose();
    _dressingController.dispose();
    _antibioticController.dispose();
    _surgicalController.dispose();
    _managementNotesController.dispose();
    super.dispose();
  }
}
