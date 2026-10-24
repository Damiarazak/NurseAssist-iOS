import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:uuid/uuid.dart';
import '../theme.dart';
import '../models/chronic_condition.dart';
import '../models/chronic_conditions_database.dart';
import '../models/patient.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';

class AddEditPatientScreen extends StatefulWidget {
  final Patient? patient;

  const AddEditPatientScreen({super.key, this.patient});

  @override
  State<AddEditPatientScreen> createState() => _AddEditPatientScreenState();
}

class _AddEditPatientScreenState extends State<AddEditPatientScreen>
    with SingleTickerProviderStateMixin {
  final _formKeys = [
    GlobalKey<FormState>(),
    GlobalKey<FormState>(),
    GlobalKey<FormState>(),
    GlobalKey<FormState>(),
  ];

  final _firestoreService = FirestoreService();
  final _nameController = TextEditingController();
  final _mrnController = TextEditingController();
  final _ageController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressRoomController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _medicationsController = TextEditingController();
  final _conditionInputController = TextEditingController();
  List<ChronicCondition> _chronicConditions = [];
  final Map<String, String> _vitalSigns = {};
  final _emergencyContactNameController = TextEditingController();
  final _emergencyContactRelationshipController = TextEditingController();
  final _emergencyContactPhoneController = TextEditingController();

  static const List<_VitalFieldSpec> _vitalSpecs = [
    _VitalFieldSpec(
      key: 'bp',
      label: 'BP (mmHg)',
      icon: Icons.monitor_heart_outlined,
      options: ['90/60', '100/70', '110/70', '120/80', '130/85', '140/90'],
    ),
    _VitalFieldSpec(
      key: 'hr',
      label: 'HR (bpm)',
      icon: Icons.favorite_outline,
      options: ['60', '72', '80', '90', '100', '110'],
    ),
    _VitalFieldSpec(
      key: 'spo2',
      label: 'SpO2 (%)',
      icon: Icons.bloodtype_outlined,
      options: ['88', '90', '92', '95', '98', '100'],
    ),
    _VitalFieldSpec(
      key: 'temp',
      label: 'Temp (°C)',
      icon: Icons.thermostat_outlined,
      options: ['36.0', '36.5', '36.8', '37.2', '38.0', '38.5'],
    ),
    _VitalFieldSpec(
      key: 'rbs',
      label: 'RBS (mg/dL)',
      icon: Icons.science_outlined,
      options: ['80', '90', '110', '140', '180', '200'],
    ),
    _VitalFieldSpec(
      key: 'pain',
      label: 'Pain Score (0-10)',
      icon: Icons.healing_outlined,
      options: ['0', '2', '4', '6', '8', '10'],
    ),
  ];

  static const List<String> _quickConditionOptions = [
    'Diabetes',
    'Hypertension',
    'Asthma',
    'Heart disease',
    'Thyroid',
    'Kidney disease',
    'Allergy',
  ];

  String _gender = 'Female';
  bool _isSaving = false;
  int _currentStep = 0;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _animController.forward();

    if (widget.patient != null) {
      final p = widget.patient!;
      _nameController.text = p.name;
      _mrnController.text = p.mrn;
      _ageController.text = p.age.toString();
      _contactController.text = p.contact;
      _gender = p.gender;
      _addressRoomController.text = p.addressRoom ?? '';
      _allergiesController.text = p.allergies ?? '';
      _medicationsController.text = p.medications ?? '';
      _chronicConditions = List<ChronicCondition>.from(p.chronicConditions);
      _vitalSigns
        ..clear()
        ..addAll(p.vitalSigns);
      _emergencyContactNameController.text = p.emergencyContactName ?? '';
      _emergencyContactRelationshipController.text =
          p.emergencyContactRelationship ?? '';
      _emergencyContactPhoneController.text = p.emergencyContactPhone ?? '';
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameController.dispose();
    _mrnController.dispose();
    _ageController.dispose();
    _contactController.dispose();
    _addressRoomController.dispose();
    _allergiesController.dispose();
    _medicationsController.dispose();
    _conditionInputController.dispose();
    _emergencyContactNameController.dispose();
    _emergencyContactRelationshipController.dispose();
    _emergencyContactPhoneController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _animController.forward(from: 0);
  }

  void _nextStep() {
    if (!_formKeys[_currentStep].currentState!.validate()) return;
    if (_currentStep < 3) _goToStep(_currentStep + 1);
  }

  void _prevStep() {
    if (_currentStep > 0) _goToStep(_currentStep - 1);
  }

  Future<void> _save() async {
    if (!_formKeys[_currentStep].currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final currentStaff = await AuthService().getCurrentStaff();
      final staffId = currentStaff?.staffId ?? '';
      final id = widget.patient?.id ?? const Uuid().v4();

      final patient = Patient(
        id: id,
        mrn: _mrnController.text.trim(),
        name: _nameController.text.trim(),
        age: int.parse(_ageController.text.trim()),
        gender: _gender,
        contact: _contactController.text.trim(),
        registeredDate: widget.patient?.registeredDate ?? DateTime.now(),
        woundAssessmentIds: widget.patient?.woundAssessmentIds ?? const [],
        staffIdAssignedTo: widget.patient?.staffIdAssignedTo ?? staffId,
        addressRoom: _addressRoomController.text.trim().isEmpty
            ? null
            : _addressRoomController.text.trim(),
        allergies: _allergiesController.text.trim().isEmpty
            ? null
            : _allergiesController.text.trim(),
        medications: _medicationsController.text.trim().isEmpty
            ? null
            : _medicationsController.text.trim(),
        chronicConditions: _chronicConditions,
        vitalSigns: _nonEmptyVitalSigns(),
        emergencyContactName:
            _emergencyContactNameController.text.trim().isEmpty
            ? null
            : _emergencyContactNameController.text.trim(),
        emergencyContactRelationship:
            _emergencyContactRelationshipController.text.trim().isEmpty
            ? null
            : _emergencyContactRelationshipController.text.trim(),
        emergencyContactPhone:
            _emergencyContactPhoneController.text.trim().isEmpty
            ? null
            : _emergencyContactPhoneController.text.trim(),
      );

      if (widget.patient == null) {
        await _firestoreService.addPatient(patient);
      } else {
        await _firestoreService.updatePatient(patient);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save patient: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.patient != null;

    return Scaffold(
      backgroundColor: kBgCanvas,
      body: Stack(
        children: [
          // ── Scrollable content ──────────────────────────────────────────
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHero(isEdit),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStepBar(),
                      const SizedBox(height: 24),
                      SlideTransition(
                        position: _slideAnim,
                        child: FadeTransition(
                          opacity: _fadeAnim,
                          child: Form(
                            key: _formKeys[_currentStep],
                            child: _buildCurrentStepCard(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Sticky bottom bar ────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomBar(isEdit),
          ),
        ],
      ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────

  Widget _buildHero(bool isEdit) {
    const stepTitles = [
      'Personal Details',
      'Medical History',
      'Vital Signs',
      'Emergency Contact',
    ];
    const stepSubtitles = [
      'Name, MRN, age and contact information.',
      'Allergies, medications and comorbidities.',
      'Choose baseline observations or add custom values.',
      'Who to contact in case of emergency.',
    ];
    return Container(
      decoration: BoxDecoration(
        gradient: kHeroGradient,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(kRadius3xl),
          bottomRight: Radius.circular(kRadius3xl),
        ),
        boxShadow: kShadowHero,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Glass back button
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Back',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Eyebrows row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEdit
                        ? 'EDIT PATIENT · MANUAL ENTRY'
                        : 'NEW PATIENT · MANUAL ENTRY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.3,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  Text(
                    'STEP ${_currentStep + 1} OF 4',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                stepTitles[_currentStep],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                stepSubtitles[_currentStep],
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 16),
              // Progress bar — 4 segments
              Row(
                children: List.generate(4, (i) {
                  final filled = i < _currentStep + 1;
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                      decoration: BoxDecoration(
                        color: filled
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step bar ─────────────────────────────────────────────────────────────

  Widget _buildStepBar() {
    const labels = ['PERSONAL', 'HISTORY', 'VITALS', 'EMERGENCY'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(labels.length * 2 - 1, (i) {
        if (i.isOdd) {
          // Connector line
          final stepIndex = i ~/ 2;
          final isComplete = _currentStep > stepIndex;
          return Expanded(
            child: Container(height: 2, color: isComplete ? kPrimary : kLine),
          );
        }
        // Circle step
        final step = i ~/ 2;
        final isActive = _currentStep == step;
        final isDone = _currentStep > step;
        return Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isActive || isDone) ? kPrimary : Colors.white,
                border: Border.all(
                  color: (isActive || isDone) ? kPrimary : kLine,
                  width: 2,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: kPrimary.withValues(alpha: 0.28),
                          blurRadius: 0,
                          spreadRadius: 4,
                        ),
                      ]
                    : null,
              ),
              child: isDone
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    )
                  : Center(
                      child: Text(
                        '${step + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isActive ? Colors.white : kMuted3,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 5),
            Text(
              labels[step],
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: (isActive || isDone) ? kPrimary : kMuted3,
              ),
            ),
          ],
        );
      }),
    );
  }

  // ── Step Cards ─────────────────────────────────────────────────
  Widget _buildCurrentStepCard() {
    switch (_currentStep) {
      case 0:
        return _buildPersonalStep();
      case 1:
        return _buildHistoryStep();
      case 2:
        return _buildVitalsStep();
      case 3:
        return _buildClinicalStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildStepCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kRadiusXl),
        boxShadow: kShadowMd,
      ),
      child: child,
    );
  }

  // Step 1 — Personal Details
  Widget _buildPersonalStep() {
    return _buildStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('FULL PATIENT NAME'),
          _buildField(
            controller: _nameController,
            hint: 'e.g. Robert J. Sterling',
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Name is required' : null,
          ),
          const SizedBox(height: 16),
          _buildLabel('PATIENT ID / MRN'),
          _buildField(
            controller: _mrnController,
            hint: 'e.g. MRN-001237',
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'MRN is required' : null,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('AGE'),
                    _buildField(
                      controller: _ageController,
                      hint: 'Years',
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Required';
                        }
                        final age = int.tryParse(v.trim());
                        if (age == null || age <= 0) return 'Invalid';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('GENDER'),
                    DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration: _inputDecoration('Select'),
                      items: const [
                        DropdownMenuItem(
                          value: 'Female',
                          child: Text('Female'),
                        ),
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _gender = v);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildLabel('CONTACT NUMBER'),
          _buildField(
            controller: _contactController,
            hint: 'e.g. +60 12-345 6789',
            keyboardType: TextInputType.phone,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Contact is required' : null,
          ),
          const SizedBox(height: 16),
          _buildLabel('FACILITIES / ROOM / WARD'),
          _buildField(
            controller: _addressRoomController,
            hint: 'Facility, room number, or ward',
          ),
        ],
      ),
    );
  }

  // Step 2 — Medical History
  Widget _buildHistoryStep() {
    return _buildStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Comorbidities',
            style: TextStyle(
              fontSize: 33,
              fontWeight: FontWeight.w700,
              color: kInk2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a condition and we\'ll ask when it started right after — skip if unknown.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          _buildComorbiditiesPanel(),
          if (_chronicConditions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Tap a condition to edit its name or date.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _conditionInputController,
                  decoration: _inputDecoration('e.g., Diabetes'),
                  onSubmitted: (_) => _addConditionFromInput(),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _addConditionFromInput,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'Add',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Quick add',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickConditionOptions.map((option) {
              final exists = _hasCondition(option);
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: exists ? null : () => _addConditionByName(option),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: exists ? const Color(0xFFE6F0FF) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: exists ? kBlue400 : const Color(0xFFD8E0EA),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        exists ? Icons.check_rounded : Icons.add_rounded,
                        size: 16,
                        color: kPrimary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        option,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Divider(color: Colors.grey.shade200, height: 1),
          const SizedBox(height: 18),
          const Text(
            'Additional notes',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: kInk2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Allergies, surgeries, medications, family history...',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _allergiesController,
            maxLines: 3,
            decoration: _inputDecoration('Optional notes'),
          ),
        ],
      ),
    );
  }

  Widget _buildComorbiditiesPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE4EE)),
      ),
      child: _chronicConditions.isEmpty
          ? Column(
              children: [
                Icon(
                  Icons.monitor_heart_outlined,
                  color: Colors.grey.shade500,
                  size: 24,
                ),
                const SizedBox(height: 8),
                Text(
                  'No comorbidities added yet',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _chronicConditions
                  .map((c) => _conditionBadge(c))
                  .toList(),
            ),
    );
  }

  Widget _conditionBadge(ChronicCondition c) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => _showAddConditionSheet(editing: c),
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 8, top: 8, bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFD7E0EA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.circle, size: 7, color: kPrimary),
            const SizedBox(width: 8),
            Text(
              c.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: kInk2,
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(
                () => _chronicConditions.removeWhere((x) => x.id == c.id),
              ),
              child: const Icon(Icons.close_rounded, size: 16, color: kMuted2),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasCondition(String name) {
    final needle = name.trim().toLowerCase();
    return _chronicConditions.any((c) => c.name.trim().toLowerCase() == needle);
  }

  void _addConditionFromInput() {
    final name = _conditionInputController.text.trim();
    if (name.isEmpty) return;
    _addConditionByName(name);
    _conditionInputController.clear();
  }

  Future<void> _addConditionByName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (_hasCondition(trimmed)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$trimmed is already added')));
      return;
    }
    final newCondition = ChronicCondition(id: const Uuid().v4(), name: trimmed);
    setState(() => _chronicConditions.add(newCondition));

    // Immediately ask when it started, instead of silently leaving the date
    // blank and relying on the nurse to realize they can tap the badge
    // afterward to set it.
    await _showAddConditionSheet(editing: newCondition);
  }

  Future<void> _showAddConditionSheet({ChronicCondition? editing}) async {
    final result = await showModalBottomSheet<ChronicCondition>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusXl)),
      ),
      builder: (ctx) => _AddConditionSheet(existing: editing),
    );

    if (result == null || !mounted) return;
    setState(() {
      if (editing != null) {
        final i = _chronicConditions.indexWhere((x) => x.id == editing.id);
        if (i != -1) {
          _chronicConditions[i] = result;
        } else {
          _chronicConditions.add(result);
        }
      } else {
        _chronicConditions.add(result);
      }
    });
  }

  // Step 3 — Vital Signs
  Widget _buildVitalsStep() {
    return _buildStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('VITAL SIGNS'),
          Text(
            'Pick a value for each observation. Use Other if you need a custom entry.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _vitalSpecs
                .map((spec) => _buildVitalSelectorCard(spec))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildVitalSelectorCard(_VitalFieldSpec spec) {
    final selected = _vitalSigns[spec.key]?.trim();
    final hasValue = selected != null && selected.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showVitalPicker(spec),
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasValue ? kPrimary.withValues(alpha: 0.5) : kLine,
          ),
          boxShadow: hasValue
              ? [
                  BoxShadow(
                    color: kPrimary.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDF3FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(spec.icon, size: 13, color: kPrimary),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    spec.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: kMuted1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              hasValue ? selected : 'Select',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: hasValue ? kPrimaryDark : kMuted3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showVitalPicker(_VitalFieldSpec spec) async {
    final current = (_vitalSigns[spec.key] ?? '').trim();
    String? selectedOption = spec.options.contains(current) ? current : null;
    bool useOther = current.isNotEmpty && !spec.options.contains(current);
    final otherController = TextEditingController(
      text: useOther ? current : '',
    );

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusXl)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spec.label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: kInk2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in spec.options)
                        ChoiceChip(
                          label: Text(option),
                          selected: selectedOption == option && !useOther,
                          onSelected: (_) {
                            setModalState(() {
                              useOther = false;
                              selectedOption = option;
                            });
                          },
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.edit_rounded, size: 16),
                        label: const Text('Other'),
                        onPressed: () {
                          setModalState(() {
                            useOther = true;
                            selectedOption = null;
                          });
                        },
                      ),
                    ],
                  ),
                  if (useOther) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: otherController,
                      decoration: _inputDecoration('Type custom value'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(''),
                        child: const Text('Clear'),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final value = useOther
                              ? otherController.text.trim()
                              : (selectedOption ?? '').trim();
                          if (value.isEmpty) return;
                          Navigator.of(ctx).pop(value);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Use value'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    otherController.dispose();
    if (!mounted || picked == null) return;
    setState(() {
      if (picked.trim().isEmpty) {
        _vitalSigns.remove(spec.key);
      } else {
        _vitalSigns[spec.key] = picked.trim();
      }
    });
  }

  Map<String, String> _nonEmptyVitalSigns() {
    final out = <String, String>{};
    for (final entry in _vitalSigns.entries) {
      final v = entry.value.trim();
      if (v.isNotEmpty) out[entry.key] = v;
    }
    return out;
  }

  // Step 4 — Emergency Contact
  Widget _buildClinicalStep() {
    return _buildStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('CONTACT NAME'),
          _buildField(
            controller: _emergencyContactNameController,
            hint: 'Full name of emergency contact',
          ),
          const SizedBox(height: 16),
          _buildLabel('RELATIONSHIP'),
          _buildField(
            controller: _emergencyContactRelationshipController,
            hint: 'e.g. Spouse, Parent, Sibling',
          ),
          const SizedBox(height: 16),
          _buildLabel('PHONE NUMBER'),
          _buildField(
            controller: _emergencyContactPhoneController,
            hint: 'Emergency contact phone',
            keyboardType: TextInputType.phone,
          ),
        ],
      ),
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────────
  Widget _buildBottomBar(bool isEdit) {
    final isLastStep = _currentStep == 3;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: kLine, width: 1)),
      ),
      child: Row(
        children: [
          // Cancel / Back
          Expanded(
            child: OutlinedButton(
              onPressed: _isSaving
                  ? null
                  : (_currentStep == 0
                        ? () => Navigator.of(context).pop()
                        : _prevStep),
              style: OutlinedButton.styleFrom(
                foregroundColor: kInk2,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                side: const BorderSide(color: kLine, width: 1.5),
              ),
              child: Text(
                _currentStep == 0 ? 'Cancel' : 'Back',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Continue / Save
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : (isLastStep ? _save : _nextStep),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: kPrimary.withValues(alpha: 0.45),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(
                      isLastStep
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded,
                      size: 18,
                    ),
              label: Text(
                isLastStep
                    ? (isEdit ? 'Save changes' : 'Save patient')
                    : 'Continue',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: kMuted2,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: _inputDecoration(hint),
      validator: validator,
    );
  }
}

// Shared by the form fields above and _AddConditionSheet below, so both
// keep the same input styling without duplicating it.
InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: kMuted3, fontSize: 14),
    filled: true,
    fillColor: kBgInput,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kBlue400, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kDanger),
    ),
  );
}

class _VitalFieldSpec {
  final String key;
  final String label;
  final IconData icon;
  final List<String> options;

  const _VitalFieldSpec({
    required this.key,
    required this.label,
    required this.icon,
    required this.options,
  });
}

// ── Add / edit condition bottom sheet ─────────────────────────────────────
//
// Two steps: "pick" a condition name (search the common list, or "Other"
// free text), then "onset" — either an exact month/year, or a quick range
// when the exact date isn't known.
class _AddConditionSheet extends StatefulWidget {
  final ChronicCondition? existing;

  const _AddConditionSheet({this.existing});

  @override
  State<_AddConditionSheet> createState() => _AddConditionSheetState();
}

class _AddConditionSheetState extends State<_AddConditionSheet> {
  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _rangeLabels = ['< 1 yr', '1–5 yrs', '5–10 yrs', '10+ yrs'];

  late String _step; // 'pick' or 'onset'
  final _searchController = TextEditingController();
  final _otherController = TextEditingController();
  bool _showOtherField = false;
  String? _selectedName;

  late int _pickedMonth;
  late int _pickedYear;
  late final List<int> _years;
  late final FixedExtentScrollController _monthScrollController;
  late final FixedExtentScrollController _yearScrollController;

  bool _useRange = false;
  int? _selectedRangeIndex;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _years = List.generate(101, (i) => now.year - i);

    final existing = widget.existing;
    if (existing != null) {
      _step = 'onset';
      _selectedName = existing.name;
      final d = existing.diagnosedDate ?? now;
      _pickedMonth = d.month;
      _pickedYear = d.year;
      _useRange = existing.isApproximate;
    } else {
      _step = 'pick';
      _pickedMonth = now.month;
      _pickedYear = now.year;
    }

    final yearIndex = _years.indexOf(_pickedYear);
    _monthScrollController = FixedExtentScrollController(
      initialItem: _pickedMonth - 1,
    );
    _yearScrollController = FixedExtentScrollController(
      initialItem: yearIndex >= 0 ? yearIndex : 0,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _otherController.dispose();
    _monthScrollController.dispose();
    _yearScrollController.dispose();
    super.dispose();
  }

  List<String> get _filteredConditions {
    final query = _searchController.text.trim().toLowerCase();
    final all = ChronicConditionsDatabase.getAllConditions();
    if (query.isEmpty) return all;
    return all.where((c) => c.toLowerCase().contains(query)).toList();
  }

  void _pickName(String name) {
    setState(() {
      _selectedName = name;
      _step = 'onset';
    });
  }

  void _confirmOther() {
    final text = _otherController.text.trim();
    if (text.isEmpty) return;
    _pickName(text);
  }

  DateTime _rangeMidpoint(int index) {
    final now = DateTime.now();
    switch (index) {
      case 0: // < 1 yr
        return DateTime(now.year, now.month - 6, 1);
      case 1: // 1–5 yrs
        return DateTime(now.year - 3, now.month, 1);
      case 2: // 5–10 yrs
        return DateTime(now.year - 7, now.month - 6, 1);
      default: // 10+ yrs — open-ended, anchor at 15 years back
        return DateTime(now.year - 15, now.month, 1);
    }
  }

  void _skipDate() {
    if (_selectedName == null) return;
    Navigator.of(context).pop(
      ChronicCondition(
        id: widget.existing?.id ?? const Uuid().v4(),
        name: _selectedName!,
      ),
    );
  }

  void _confirm() {
    if (_selectedName == null) return;

    final DateTime diagnosedDate;
    final bool isApproximate;
    if (_useRange) {
      if (_selectedRangeIndex == null) return;
      diagnosedDate = _rangeMidpoint(_selectedRangeIndex!);
      isApproximate = true;
    } else {
      diagnosedDate = DateTime(_pickedYear, _pickedMonth, 1);
      isApproximate = false;
    }

    Navigator.of(context).pop(
      ChronicCondition(
        id: widget.existing?.id ?? const Uuid().v4(),
        name: _selectedName!,
        diagnosedDate: diagnosedDate,
        isApproximate: isApproximate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: _step == 'pick' ? _buildPickStep() : _buildOnsetStep(),
        ),
      ),
    );
  }

  Widget _buildPickStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add condition',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: kInk2,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _searchController,
          autofocus: true,
          decoration: _inputDecoration('Search condition…'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final name in _filteredConditions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    name,
                    style: const TextStyle(fontSize: 14, color: kInk2),
                  ),
                  onTap: () => _pickName(name),
                ),
            ],
          ),
        ),
        const Divider(height: 24),
        if (!_showOtherField)
          TextButton.icon(
            onPressed: () => setState(() => _showOtherField = true),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Other — type it in'),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _otherController,
                  autofocus: true,
                  decoration: _inputDecoration('Condition name'),
                  onSubmitted: (_) => _confirmOther(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _confirmOther,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Use this'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildOnsetStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'When did $_selectedName start?',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: kInk2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Optional — skip if you don\'t know.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        if (!_useRange) ...[
          SizedBox(
            height: 150,
            child: Row(
              children: [
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _monthScrollController,
                    itemExtent: 36,
                    onSelectedItemChanged: (i) => _pickedMonth = i + 1,
                    children: _monthNames
                        .map((m) => Center(child: Text(m)))
                        .toList(),
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _yearScrollController,
                    itemExtent: 36,
                    onSelectedItemChanged: (i) => _pickedYear = _years[i],
                    children: _years
                        .map((y) => Center(child: Text('$y')))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _useRange = true),
              child: const Text('Not sure — use a range instead'),
            ),
          ),
        ] else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_rangeLabels.length, (i) {
              final selected = _selectedRangeIndex == i;
              return GestureDetector(
                onTap: () => setState(() => _selectedRangeIndex = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? kPrimary : kBgInput,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _rangeLabels[i],
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : kMuted1,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _useRange = false),
              child: const Text('Use exact date instead'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_useRange && _selectedRangeIndex == null)
                ? null
                : _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              widget.existing != null ? 'Save changes' : 'Add condition',
            ),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: _skipDate,
            child: Text(
              'Skip — I don\'t know the date',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ),
      ],
    );
  }
}
