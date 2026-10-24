import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../widgets/patient_avatar.dart';
import '../models/patient.dart';
import '../models/wound_assessment.dart';
import '../services/firestore_service.dart';
import 'capture_wound_screen.dart';
import 'analysis_results_screen.dart';
import 'add_edit_patient_screen.dart';

class PatientProfileScreen extends StatefulWidget {
  final Patient patient;

  const PatientProfileScreen({super.key, required this.patient});

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<WoundAssessment> _assessments = [];
  bool _isLoading = true;
  bool _isDeleting = false;
  int _activeTab = 0;
  late Patient _patient;

  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
    _loadAssessments();
  }

  Future<void> _loadAssessments() async {
    try {
      final assessments = await _firestoreService.getWoundAssessments(
        _patient.id,
      );
      setState(() {
        _assessments = assessments;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading assessments: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmDeleteAssessment(WoundAssessment assessment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete assessment?'),
          content: const Text('This will remove the assessment permanently.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _firestoreService.deleteWoundAssessment(
        assessmentId: assessment.id,
        patientId: _patient.id,
      );
      setState(() {
        _assessments.removeWhere((a) => a.id == assessment.id);
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Assessment deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _confirmDeletePatient() async {
    if (_isDeleting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text('Remove patient?', style: kH3),
          content: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, color: kInk2, height: 1.5),
              children: [
                const TextSpan(text: 'Remove '),
                TextSpan(
                  text: _patient.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(
                  text:
                      ' from your care list? Their hospital record will be kept.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(foregroundColor: kMuted1),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kDanger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      await _firestoreService.deletePatientAndAssessments(_patient.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient removed from NurseAssist')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to remove patient: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _navigateToCaptureWound() {
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(
            builder: (_) => CaptureWoundScreen(patient: _patient),
          ),
        )
        .then((result) {
          if (result == true) {
            _loadAssessments();
          }
        });
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMMM d, yyyy').format(date);
  }

  String _formatDateTime(DateTime date) {
    return DateFormat('MMM d, yyyy, h:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgCanvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Patient Profile',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          _buildTopActionButton(
            icon: Icons.edit,
            color: kMuted1,
            onTap: () async {
              final updated = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => AddEditPatientScreen(patient: _patient),
                ),
              );

              if (updated == true) {
                final refreshed = await _firestoreService.getPatient(
                  _patient.id,
                );
                if (refreshed != null && mounted) {
                  setState(() {
                    _patient = refreshed;
                  });
                }
              }
            },
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.delete_outline,
            color: kDanger,
            onTap: _confirmDeletePatient,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: _buildPatientHeroCard(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildProfileTabs(),
            ),
            const SizedBox(height: 14),
            _buildActiveTabContent(),
            const SizedBox(height: 18),
            _buildWoundAssessmentSection(),
            const SizedBox(height: 90),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToCaptureWound,
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text(
          'Capture Wound',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildProfileTabs() {
    const labels = ['Info', 'History', 'Vitals', 'Contact'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(labels.length, (index) {
          final isActive = _activeTab == index;
          return Padding(
            padding: EdgeInsets.only(right: index == labels.length - 1 ? 0 : 8),
            child: ChoiceChip(
              label: Text(labels[index]),
              selected: isActive,
              onSelected: (_) => setState(() => _activeTab = index),
              selectedColor: kPrimary,
              backgroundColor: const Color(0xFFF0F2F7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: isActive ? kPrimary : const Color(0xFFE1E6EF),
                ),
              ),
              labelStyle: TextStyle(
                color: isActive ? Colors.white : const Color(0xFF4F5D70),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_activeTab) {
      case 0:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: _buildPatientDetailsCard(),
        );
      case 1:
        return _buildHistoryTab();
      case 2:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: _patient.vitalSigns.isEmpty
              ? _buildPlaceholderCard('No vital signs recorded yet')
              : _buildVitalsCard(),
        );
      case 3:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: _buildContactTab(),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildWoundAssessmentSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Wound Assessments',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: kInk2,
                ),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFDDE4EC),
                ),
                alignment: Alignment.center,
                child: Text(
                  _assessments.length.toString(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5D6C7D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE1E7F0)),
            ),
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _assessments.isEmpty
                ? _buildPlaceholderCard('No wound assessments yet')
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _assessments.length,
                    itemBuilder: (context, index) {
                      final assessment = _assessments[index];
                      return _buildAssessmentTile(assessment);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _buildMedicalHistoryCard(),
    );
  }

  Widget _buildMedicalHistoryCard() {
    final conditions = _patient.chronicConditions;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE2EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Medical History',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2A38),
            ),
          ),
          const SizedBox(height: 10),
          if (conditions.isEmpty)
            Text(
              'No comorbidities recorded',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            )
          else
            Column(
              children: conditions
                  .map(
                    (condition) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFDDE2EB)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.medical_information_outlined,
                            size: 16,
                            color: kPrimary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  condition.name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1F2A38),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  condition.diagnosedDate == null
                                      ? 'Diagnosis date unknown'
                                      : 'Since ${condition.diagnosedLabel} · ${condition.durationLabel()}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF7A8696),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildContactTab() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE2EB)),
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.call_outlined, 'Contact', _patient.contact),
          const SizedBox(height: 10),
          _buildInfoRow(
            Icons.person_outline,
            'Emergency Contact',
            (_patient.emergencyContactName ?? '').trim().isEmpty
                ? 'Not provided'
                : _patient.emergencyContactName!.trim(),
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            Icons.group_outlined,
            'Relationship',
            (_patient.emergencyContactRelationship ?? '').trim().isEmpty
                ? 'Not provided'
                : _patient.emergencyContactRelationship!.trim(),
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            Icons.phone_outlined,
            'Emergency Phone',
            (_patient.emergencyContactPhone ?? '').trim().isEmpty
                ? 'Not provided'
                : _patient.emergencyContactPhone!.trim(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
      ),
    );
  }

  Widget _buildTopActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Color(0xFFF0F3F8),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 19, color: color),
      ),
    );
  }

  Widget _buildPatientHeroCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: kHeroGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: kShadowHero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PatientAvatar(name: _patient.name, size: 40, onGradient: true),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _patient.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    height: 1.08,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${_patient.age} years | ${_patient.gender}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today, size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  DateFormat('EEE, d MMM').format(_patient.registeredDate),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientDetailsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE2EB)),
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.badge_outlined, 'Medical Record #', _patient.mrn),
          const SizedBox(height: 10),
          _buildInfoRow(Icons.call_outlined, 'Contact', _patient.contact),
          if ((_patient.addressRoom ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildInfoRow(
              Icons.apartment_outlined,
              'Facilities / Room / Ward',
              _patient.addressRoom!.trim(),
            ),
          ],
          const SizedBox(height: 10),
          _buildInfoRow(
            Icons.calendar_today_outlined,
            'Registered',
            _formatDate(_patient.registeredDate),
          ),
        ],
      ),
    );
  }

  Widget _buildAssessmentTile(WoundAssessment assessment) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (assessment.analysisResult != null) {
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (_) => AnalysisResultsScreen(
                    patient: _patient,
                    assessment: assessment,
                  ),
                ),
              )
              .then((_) => _loadAssessments());
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 56,
                height: 56,
                color: const Color(0xFFE6EBF2),
                child: assessment.imageUrl.startsWith('http')
                    ? Image.network(
                        assessment.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.image_outlined,
                              size: 26,
                              color: Color(0xFF617287),
                            ),
                      )
                    : Image.file(
                        File(assessment.imageUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.image_outlined,
                              size: 26,
                              color: Color(0xFF617287),
                            ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2A317),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Type ${assessment.displayWoundType}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          assessment.analysisResult != null
                              ? assessment.displayWoundName
                              : 'Analyzing...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2B3A),
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _formatDateTime(assessment.assessmentDate),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF7A8696),
                    ),
                  ),
                  if (assessment.hasSupervisorFeedback) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: kPurple600.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: kPurple600.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.feedback_outlined,
                            size: 13,
                            color: kPurple600,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              assessment.supervisorCorrectedType != null
                                  ? 'Reassigned to Type ${assessment.supervisorCorrectedType}'
                                        '${assessment.supervisorFeedback != null ? ' — ${assessment.supervisorFeedback}' : ''}'
                                  : (assessment.supervisorFeedback ??
                                        'Supervisor left feedback'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: kPurple600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: kDanger),
                  onPressed: () => _confirmDeleteAssessment(assessment),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF778698)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVitalsCard() {
    const specs = [
      _VitalDisplaySpec('bp', 'BP', 'mmHg', Icons.monitor_heart_outlined),
      _VitalDisplaySpec('hr', 'HR', 'bpm', Icons.favorite_outline),
      _VitalDisplaySpec('spo2', 'SpO2', '%', Icons.bloodtype_outlined),
      _VitalDisplaySpec('temp', 'TEMP', '°C', Icons.thermostat_outlined),
      _VitalDisplaySpec('rbs', 'RBS', 'mg/dL', Icons.science_outlined),
      _VitalDisplaySpec('pain', 'PAIN', '/10', Icons.healing_outlined),
    ];

    final known = specs
        .where((s) => (_patient.vitalSigns[s.key] ?? '').trim().isNotEmpty)
        .toList();
    final unknown = _patient.vitalSigns.entries
        .where(
          (e) => !specs.any((s) => s.key == e.key) && e.value.trim().isNotEmpty,
        )
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E7F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vital Signs',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2A38),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: known.map((s) {
              final value = _patient.vitalSigns[s.key]!.trim();
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3F3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFDADA)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        s.icon,
                        color: const Color(0xFFEF4444),
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.label,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF9A6A6A),
                            letterSpacing: 0.3,
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              value,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFEF4444),
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              s.unit,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9A6A6A),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          if (unknown.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: unknown
                  .map(
                    (e) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFFCAC8)),
                      ),
                      child: Text(
                        '${e.key.toUpperCase()}: ${e.value}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB42318),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFE6ECF6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: kPrimary),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF8894A4)),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF1F2A38),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VitalDisplaySpec {
  final String key;
  final String label;
  final String unit;
  final IconData icon;

  const _VitalDisplaySpec(this.key, this.label, this.unit, this.icon);
}
