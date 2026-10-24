import 'dart:io';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/patient.dart';
import '../models/wound_assessment.dart';
import '../models/wound_types_database.dart';

class LecturerApprovalScreen extends StatefulWidget {
  const LecturerApprovalScreen({super.key});

  @override
  State<LecturerApprovalScreen> createState() => _LecturerApprovalScreenState();
}

class _LecturerApprovalScreenState extends State<LecturerApprovalScreen> {
  final _firestoreService = FirestoreService();

  List<WoundAssessment> _assessments = [];
  bool _isLoading = true;
  final Set<String> _approving = {};
  final Set<String> _rejecting = {};

  // patientId -> Patient, so cards can show "Name (MRN)" instead of a raw ID
  final Map<String, Patient> _patients = {};

  // ── Reassign type / feedback (per-card, collapsed by default) ───────────
  final Set<String> _expanded = {};
  final Map<String, int?> _typeOverride = {};
  final Map<String, TextEditingController> _feedbackControllers = {};

  TextEditingController _feedbackControllerFor(String assessmentId) {
    return _feedbackControllers.putIfAbsent(
      assessmentId,
      () => TextEditingController(),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _feedbackControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final list = await _firestoreService.getPendingApprovalAssessments();

      // Fetch the patient record for each assessment so cards can show the
      // patient's name, not just their ID. Dedup first so a patient with
      // several pending assessments is only fetched once.
      final uniquePatientIds = list.map((a) => a.patientId).toSet();
      final missingIds = uniquePatientIds.where(
        (id) => !_patients.containsKey(id),
      );
      final fetched = await Future.wait(
        missingIds.map((id) => _firestoreService.getPatient(id)),
      );
      for (final patient in fetched) {
        if (patient != null) _patients[patient.id] = patient;
      }

      if (mounted) {
        setState(() {
          _assessments = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approve(WoundAssessment assessment) async {
    setState(() => _approving.add(assessment.id));
    try {
      final staffId = AuthService().loggedInStaff?.staffId ?? 'unknown';
      final feedback = _feedbackControllers[assessment.id]?.text.trim();
      await _firestoreService.approveForTraining(
        assessmentId: assessment.id,
        approvedBy: staffId,
        supervisorCorrectedType: _typeOverride[assessment.id],
        supervisorFeedback: (feedback == null || feedback.isEmpty)
            ? null
            : feedback,
      );
      if (mounted) {
        setState(() {
          _assessments.removeWhere((a) => a.id == assessment.id);
          _approving.remove(assessment.id);
          _expanded.remove(assessment.id);
          _typeOverride.remove(assessment.id);
          _feedbackControllers.remove(assessment.id)?.dispose();
        });
        showSuccessSnack(context, 'Approved for model training.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _approving.remove(assessment.id));
        showErrorSnack(
          context,
          'Error: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }
  }

  Future<void> _reject(WoundAssessment assessment) async {
    final feedback = _feedbackControllers[assessment.id]?.text.trim() ?? '';
    if (feedback.isEmpty) {
      setState(() => _expanded.add(assessment.id));
      showErrorSnack(context, 'Add feedback for the nurse before rejecting.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Reject Image?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This image will be removed from the training queue and will not be used to improve the model.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: kDanger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Reject',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _rejecting.add(assessment.id));
    try {
      final staffId = AuthService().loggedInStaff?.staffId ?? 'unknown';
      await _firestoreService.rejectFromTraining(
        assessmentId: assessment.id,
        rejectedBy: staffId,
        supervisorFeedback: feedback,
        supervisorCorrectedType: _typeOverride[assessment.id],
      );
      if (mounted) {
        setState(() {
          _assessments.removeWhere((a) => a.id == assessment.id);
          _rejecting.remove(assessment.id);
          _expanded.remove(assessment.id);
          _typeOverride.remove(assessment.id);
          _feedbackControllers.remove(assessment.id)?.dispose();
        });
        showWarningSnack(context, 'Image removed from training queue.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _rejecting.remove(assessment.id));
        showErrorSnack(
          context,
          'Error: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgCanvas,
      appBar: AppBar(
        title: const Text(
          'Pending Approvals',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // Lecturer role badge + count
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: kPurple600.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: kPurple600.withValues(alpha: 0.30),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.school_rounded, size: 13, color: kPurple600),
                      SizedBox(width: 5),
                      Text(
                        'Lecturer Review',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kPurple600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isLoading) ...[
                  const Spacer(),
                  Text(
                    '${_assessments.length} wound${_assessments.length == 1 ? '' : 's'} awaiting review',
                    style: const TextStyle(fontSize: 12, color: kMuted1),
                  ),
                ],
              ],
            ),
          ),

          // Main content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _assessments.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _assessments.length,
                      itemBuilder: (_, i) => _buildCard(_assessments[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── assessment card ────────────────────────────────────────────────────────

  Widget _buildCard(WoundAssessment a) {
    final correctedAt = a.correctedAt;
    final correctedDateStr = correctedAt != null
        ? '${correctedAt.day}/${correctedAt.month}/${correctedAt.year}'
        : '—';

    final aiType = a.modelPredictedType ?? a.analysisResult?.woundType;
    final clinType = a.clinicianCorrectedType;
    final isSameType = aiType != null && clinType != null && aiType == clinType;

    final isApproving = _approving.contains(a.id);
    final isRejecting = _rejecting.contains(a.id);
    final isBusy = isApproving || isRejecting;

    final confidencePct = a.modelConfidence != null
        ? '${(a.modelConfidence! * 100).toStringAsFixed(0)}%'
        : (a.analysisResult?.confidenceScore != null
              ? '${(a.analysisResult!.confidenceScore * 100).toStringAsFixed(0)}%'
              : null);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Wound image ────────────────────────────────────────────────
          GestureDetector(
            onTap: () => _openFullImage(a),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: Hero(
                  tag: 'assessment-image-${a.id}',
                  child: _woundImage(a, fit: BoxFit.cover),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Patient info card ───────────────────────────────────
                _patientInfoRow(a),

                const SizedBox(height: 12),

                // ── AI prediction vs Clinician correction ──────────────
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 6,
                  children: [
                    _typeChip(
                      label: confidencePct != null
                          ? 'AI: Type ${aiType ?? '—'}  ($confidencePct)'
                          : 'AI: Type ${aiType ?? '—'}',
                      bg: kBgLifted,
                      fg: kPrimary,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                    _typeChip(
                      label: 'Corrected: Type ${clinType ?? '—'}',
                      bg: isSameType ? kSevMildBg : kSevModerateBg,
                      fg: isSameType ? kSevMild : kSevModerate,
                    ),
                    if (_typeOverride[a.id] != null) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: Colors.grey,
                        ),
                      ),
                      _typeChip(
                        label: 'Supervisor: Type ${_typeOverride[a.id]}',
                        bg: kPurple600.withValues(alpha: 0.10),
                        fg: kPurple600,
                      ),
                    ],
                  ],
                ),

                if (isSameType) ...[
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 13,
                        color: kSuccess,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Clinician confirmed the AI result',
                        style: TextStyle(fontSize: 11, color: kSuccess),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 10),

                // ── Corrected by ─────────────────────────────────────
                _correctedByRow(a, correctedDateStr),

                // ── Nurse notes ────────────────────────────────────────
                if (a.additionalNotes != null &&
                    a.additionalNotes!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.notes_outlined,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            a.additionalNotes!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 10),

                // ── Reassign type / feedback toggle ─────────────────────
                InkWell(
                  onTap: () => setState(() {
                    if (_expanded.contains(a.id)) {
                      _expanded.remove(a.id);
                    } else {
                      _expanded.add(a.id);
                    }
                  }),
                  child: Row(
                    children: [
                      Icon(
                        _expanded.contains(a.id)
                            ? Icons.expand_less_rounded
                            : Icons.rate_review_outlined,
                        size: 16,
                        color: kPurple600,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _expanded.contains(a.id)
                            ? 'Hide reassign / feedback'
                            : 'Reassign type / Add feedback',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: kPurple600,
                        ),
                      ),
                    ],
                  ),
                ),

                if (_expanded.contains(a.id)) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Reassign wound type (optional)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int?>(
                    initialValue: _typeOverride[a.id],
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text('No change — keep Type ${clinType ?? '—'}'),
                      ),
                      ...List.generate(
                        8,
                        (i) => DropdownMenuItem<int?>(
                          value: i + 1,
                          child: Text(
                            WoundTypesDatabase.getWoundTypeName(i + 1),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) =>
                        setState(() => _typeOverride[a.id] = val),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Feedback for nurse',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _feedbackControllerFor(a.id),
                    maxLines: 3,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText:
                          'Add a comment for the nurse (required to reject)',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // ── Reject / Approve buttons ───────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isBusy ? null : () => _reject(a),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kDanger,
                          disabledForegroundColor: kDanger.withValues(
                            alpha: 0.4,
                          ),
                          side: BorderSide(
                            color: isBusy
                                ? kDanger.withValues(alpha: 0.25)
                                : kDanger.withValues(alpha: 0.55),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: isRejecting
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: kDanger.withValues(alpha: 0.5),
                                ),
                              )
                            : const Icon(Icons.cancel_outlined, size: 16),
                        label: Text(
                          isRejecting ? 'Rejecting…' : 'Reject',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: isBusy ? null : () => _approve(a),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kSuccess,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: kSuccess.withValues(
                            alpha: 0.4,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        icon: isApproving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 16),
                        label: Text(
                          isApproving ? 'Approving…' : 'Approve for Training',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  /// Rounded "patient" info block: avatar-style initials, name, MRN badge,
  /// and the assessment date — replaces the old plain "Patient ID: xxx" row.
  Widget _patientInfoRow(WoundAssessment a) {
    final patient = _patients[a.patientId];
    final assessedDateStr =
        '${a.assessmentDate.day}/${a.assessmentDate.month}/${a.assessmentDate.year}';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: kBgLifted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Avatar initials
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              _initials(patient?.name),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Name + MRN badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient?.name ?? 'Unknown patient',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kMuted1,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.badge_outlined,
                      size: 11,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        patient?.mrn ?? a.patientId,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Assessment date, right-aligned
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 12,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 2),
              Text(
                assessedDateStr,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Small row showing who made the clinician correction and when, styled
  /// to match [_patientInfoRow] but lighter-weight since it's secondary info.
  Widget _correctedByRow(WoundAssessment a, String correctedDateStr) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.edit_outlined,
            size: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              children: [
                const TextSpan(text: 'Corrected by  '),
                TextSpan(
                  text: a.correctedByDisplay,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kMuted1,
                  ),
                ),
                TextSpan(text: '   •   $correctedDateStr'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Up to 2 initials from a name, for the avatar circle. Falls back to a
  /// generic person glyph when the name isn't loaded yet.
  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  Widget _woundImage(WoundAssessment a, {required BoxFit fit}) {
    final bool isNetworkImage = a.imageUrl.startsWith('http');
    return isNetworkImage
        ? Image.network(
            a.imageUrl,
            fit: fit,
            errorBuilder: (_, __, ___) => _imagePlaceholder(),
          )
        : Image.file(
            File(a.imageUrl),
            fit: fit,
            errorBuilder: (_, __, ___) => _imagePlaceholder(),
          );
  }

  void _openFullImage(WoundAssessment a) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => _FullScreenImageViewer(
          heroTag: 'assessment-image-${a.id}',
          child: _woundImage(a, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _typeChip({
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: Colors.grey.shade100,
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 52,
          color: Colors.grey.shade300,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              size: 80,
              color: kSuccess,
            ),
            const SizedBox(height: 20),
            Text(
              'All caught up!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No wound assessments are pending\nyour review right now.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

// ── full-screen image viewer ──────────────────────────────────────────────────

class _FullScreenImageViewer extends StatelessWidget {
  final String heroTag;
  final Widget child;

  const _FullScreenImageViewer({required this.heroTag, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Center(
                child: Hero(
                  tag: heroTag,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
