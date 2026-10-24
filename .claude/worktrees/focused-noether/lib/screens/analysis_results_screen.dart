import 'dart:io';
import 'package:flutter/material.dart';
import '../models/patient.dart';
import '../models/wound_assessment.dart';
import '../services/firestore_service.dart';

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
  final TextEditingController _estimatedSizeController = TextEditingController();
  final TextEditingController _dressingController = TextEditingController();
  final TextEditingController _antibioticController = TextEditingController();
  final TextEditingController _surgicalController = TextEditingController();
  final TextEditingController _managementNotesController = TextEditingController();
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
    // Only require specialist confirmation if the wound type requires it (types 3, 4, 6)
    if (_assessment.requiresSpecialistConfirmation && !_specialistConfirmed) {
      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text(
              'Confirmation Required',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            content: const Text(
              'Please tick the "Confirm Specialist Notified" checkbox before saving the assessment.',
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return;
    }

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Assessment saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
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
    switch (severity.toLowerCase()) {
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

  void _initEditableFields() {
    final result = _assessment.analysisResult;
    if (result == null) return;

    _woundType = result.woundType;
    _severity = result.severity;
    _woundNameController.text = result.woundName;
    _estimatedSizeController.text = result.estimatedSize.toStringAsFixed(1);
    _dressingController.text = result.management.dressingMaterials.join(', ');
    _antibioticController.text = result.management.antibioticRecommendation;
    _surgicalController.text = result.management.surgicalProcedures.join(', ');
    _managementNotesController.text = result.management.additionalNotes ?? '';
  }

  WoundAssessment _buildUpdatedAssessment({
    WoundAnalysisResult? analysisResult,
    String? notes,
    bool? specialistConfirmed,
  }) {
    return WoundAssessment(
      id: _assessment.id,
      patientId: _assessment.patientId,
      imageUrl: _assessment.imageUrl,
      assessmentDate: _assessment.assessmentDate,
      analysisResult: analysisResult ?? _assessment.analysisResult,
      additionalNotes: notes ?? _assessment.additionalNotes,
      requiresSpecialistConfirmation: _assessment.requiresSpecialistConfirmation,
      specialistConfirmed: specialistConfirmed ?? _assessment.specialistConfirmed,
    );
  }

  List<String> _parseList(String value, List<String> fallback) {
    final parts = value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? fallback : parts;
  }

  // ─── Hardcoded management data per wound type ─────────────────
  Map<String, dynamic> _getManagementInfo(int woundType) {
    switch (woundType) {
      case 1:
        return {
          'dressing': ['Foam', 'Polymeric membrane', 'Island dressing'],
          'dressingNotes': null,
          'antibiotic': 'No',
          'surgical': [
            'Ready for secondary wound closure',
            'If wound is small, continue dressing till wound heals by secondary intention',
            'Frequency of dressing varies depending on wound type and dressing material used',
          ],
          'requiresSpecialistConfirmation': false,
        };
      case 2:
        return {
          'dressing': ['Foam', 'Alginate', 'Hydrofiber', 'Polymeric membrane'],
          'dressingNotes': null,
          'antibiotic': 'May or may not, based on underlying cause',
          'surgical': [
            'Find underlying cause',
            'Treat underlying cause if necessary',
          ],
          'requiresSpecialistConfirmation': false,
        };
      case 3:
        return {
          'dressing': [
            'Tulle*',
            'Hydrogel*',
            'Hydrocolloid*',
            'Silver dressing*',
            'Iodine base dressing*',
            'Any secondary dressing**',
          ],
          'dressingNotes':
              '*May require secondary dressing\n**Options: Gamgee, gauze, foam, island dressing, etc.',
          'antibiotic': 'Yes, based on C&S report of infected tissue',
          'surgical': ['Debridement may be needed'],
          'requiresSpecialistConfirmation': true,
        };
      case 4:
        return {
          'dressing': [
            'Alginate*',
            'Foam',
            'Silver*',
            'Hydrofiber*',
            'Polymeric membrane',
            'Iodine base dressing*',
          ],
          'dressingNotes': '*May require secondary dressing',
          'antibiotic': 'Yes, based on C&S report of infected tissue',
          'surgical': ['Debridement may be needed'],
          'requiresSpecialistConfirmation': true,
        };
      case 5:
        return {
          'dressing': [
            'Hydrogel*',
            'Hydrocolloid',
            'Polymeric membrane',
            'Composite medical grade honey*',
          ],
          'dressingNotes': '*May require secondary dressing',
          'antibiotic': 'No',
          'surgical': ['Debridement is needed'],
          'requiresSpecialistConfirmation': false,
        };
      case 6:
        return {
          'dressing': ['Alginate*', 'Foam', 'Polymeric membrane', 'Hydrofiber*'],
          'dressingNotes': '*May require secondary dressing',
          'antibiotic': 'May or may not, based on underlying cause',
          'surgical': [
            'Surgical/mechanical debridement is recommended',
            'May need repeated debridement',
          ],
          'requiresSpecialistConfirmation': true,
        };
      case 7:
        return {
          'dressing': [
            'Silver*',
            'Hydrogel*',
            'Hydrocolloid',
            'Iodine based dressing*',
            'Polymeric membrane',
            'Composite medical grade honey*',
          ],
          'dressingNotes': null,
          'antibiotic': 'Yes, based on C&S report of infected tissue',
          'surgical': ['Surgical debridement is strongly recommended'],
          'requiresSpecialistConfirmation': false,
        };
      case 8:
      default:
        return {
          'dressing': [
            'Alginate*',
            'Hydrofiber*',
            'Foam*',
            'Polymeric membrane*',
            'Iodine base dressing*',
            'Silver*',
            'Charcoal*',
          ],
          'dressingNotes':
              '*Require combination or composite antimicrobial dressing (exudate control + antimicrobial)\nCharcoal can be used for odour management',
          'antibiotic': 'Yes, based on C&S report of infected tissue',
          'surgical': ['Surgical debridement is strongly recommended'],
          'requiresSpecialistConfirmation': false,
        };
    }
  }

  Future<void> _openEditAssessment() async {
    final current = _assessment.analysisResult;
    if (current == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No analysis data to edit')),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Edit Assessment',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _woundNameController,
                        decoration: const InputDecoration(
                          labelText: 'Wound Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Wound name is required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _woundType,
                              decoration: const InputDecoration(
                                labelText: 'Wound Type',
                                border: OutlineInputBorder(),
                              ),
                              items: List.generate(
                                8,
                                (index) => DropdownMenuItem(
                                  value: index + 1,
                                  child: Text('Type ${index + 1}'),
                                ),
                              ),
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() => _woundType = val);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _severity,
                              decoration: const InputDecoration(
                                labelText: 'Severity',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Critical', child: Text('Critical')),
                                DropdownMenuItem(value: 'Moderate', child: Text('Moderate')),
                                DropdownMenuItem(value: 'Mild', child: Text('Mild')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() => _severity = val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _estimatedSizeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Estimated Size (cm²)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final d = double.tryParse(v.trim());
                          if (d == null || d <= 0) return 'Enter a valid number';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;

                            final updatedResult = WoundAnalysisResult(
                              confidenceScore: current.confidenceScore,
                              woundType: _woundType,
                              woundName: _woundNameController.text.trim(),
                              severity: _severity,
                              estimatedSize:
                                  double.tryParse(_estimatedSizeController.text.trim()) ??
                                      current.estimatedSize,
                              characteristics: current.characteristics,
                              management: WoundManagement(
                                dressingMaterials: _parseList(
                                  _dressingController.text,
                                  current.management.dressingMaterials,
                                ),
                                antibioticRecommendation:
                                    _antibioticController.text.trim().isEmpty
                                        ? current.management.antibioticRecommendation
                                        : _antibioticController.text.trim(),
                                surgicalProcedures: _parseList(
                                  _surgicalController.text,
                                  current.management.surgicalProcedures,
                                ),
                                additionalNotes:
                                    _managementNotesController.text.trim().isEmpty
                                        ? null
                                        : _managementNotesController.text.trim(),
                              ),
                              segmentationMapUrl: current.segmentationMapUrl,
                            );

                            final updatedAssessment = _buildUpdatedAssessment(
                              analysisResult: updatedResult,
                              notes: _notesController.text,
                              specialistConfirmed: _specialistConfirmed,
                            );

                            await _firestoreService
                                .updateWoundAssessment(updatedAssessment);

                            if (mounted) {
                              setState(() {
                                _assessment = updatedAssessment;
                              });
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Assessment updated')),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Save Changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

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

    final mgmt = _getManagementInfo(result.woundType);

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
              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 16),
            ),
            Text(
              '${widget.patient.name}  •  ${widget.patient.age}y ${widget.patient.gender}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w400),
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

            // ── 2. Wound Photo ────────────────────────────────────
            _buildWoundPhoto(),

            // ── 3. Classification + Severity + Patient ────────────
            _buildInfoRow(result),

            const SizedBox(height: 14),

            // ── 4. Wound Characteristics ──────────────────────────
            _buildAccordionSection(
              number: 1,
              title: 'Wound Characteristics',
              child: _buildCharacteristicsContent(result),
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
            child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 26),
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
    return Stack(
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
                    child: const Icon(Icons.image_not_supported,
                        size: 60, color: Colors.grey),
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
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.zoom_out_map_rounded, color: Colors.white, size: 14),
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
                  'Wound Type ${result.woundType}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  result.woundName,
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
                Text(
                  '${result.estimatedSize.toStringAsFixed(1)} cm²',
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
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                    Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: child,
                    ),
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
  Widget _buildCharacteristicsContent(WoundAnalysisResult result) {
    final necroticIsHigh = result.characteristics.necroticTissue.contains('> 25%');
    final necroticColor = necroticIsHigh ? Colors.red.shade600 : Colors.orange.shade700;

    final hasInfection =
        result.characteristics.infection.toLowerCase().contains('presence');
    final infectionColor = hasInfection ? Colors.red.shade600 : Colors.green.shade700;
    final infectionIcon =
        hasInfection ? Icons.error_rounded : Icons.check_circle_rounded;

    final isDry = result.characteristics.exudateLevel.toLowerCase().contains('dry');
    final exudateColor = isDry ? Colors.green.shade700 : Colors.orange.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Necrotic Tissue / Slough
        _buildCharRow(
          label: 'Necrotic Tissue / Slough',
          child: _buildChip(result.characteristics.necroticTissue, necroticColor),
        ),
        const SizedBox(height: 10),

        // Exudate
        _buildCharRow(
          label: 'Exudate',
          child: Wrap(
            spacing: 6,
            children: [
              _buildChip(isDry ? 'Dry / Minimal' : 'Moderate', exudateColor),
              _buildChip(isDry ? 'Dry' : 'Wet', exudateColor),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Infection
        _buildCharRow(
          label: 'Infection',
          child: Row(
            children: [
              Icon(infectionIcon, color: infectionColor, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  result.characteristics.infection,
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

        // Tissue classification
        if (result.characteristics.tissueClassification.isNotEmpty) ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 12),
          Text(
            'Tissue Classification',
            style: TextStyle(
                fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: result.characteristics.tissueClassification
                .map((t) => _buildChip(t, Colors.blue.shade700))
                .toList(),
          ),
        ],
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
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  SECTION 2 — WOUND MANAGEMENT
  // ════════════════════════════════════════════════════════════════
  Widget _buildWoundManagementContent(
      WoundAnalysisResult result, Map<String, dynamic> mgmt) {
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
        _buildMgmtHeader(Icons.medical_services_outlined, 'Dressing Recommended',
            Colors.blue.shade700),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: dressing.map((d) => _buildChip(d, Colors.blue.shade700)).toList(),
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
              style: TextStyle(fontSize: 11, color: Colors.amber.shade900, height: 1.5),
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
                      Icons.medication_outlined, 'Antibiotics', antibioticColor),
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
                  if (antibioticIsYes || antibioticIsMaybe) ...[
                    const SizedBox(height: 4),
                    Text(
                      antibiotic.contains(',')
                          ? antibiotic.substring(antibiotic.indexOf(',') + 1).trim()
                          : antibiotic,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
                  _buildMgmtHeader(Icons.local_hospital_outlined, 'Surgical',
                      Colors.purple.shade700),
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
            onTap: () => setState(() => _specialistConfirmed = !_specialistConfirmed),
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
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
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
        hintText: 'Enter clinical observations...',
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
    return Container(
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
              onPressed: _saveAssessment,
              icon: const Icon(Icons.save),
              label: const Text('Save Assessment'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
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
                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
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
