import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/patient_avatar.dart';
import '../widgets/primary_fab.dart';
import '../models/patient.dart';
import '../models/staff.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import 'patient_profile_screen.dart';
import 'add_edit_patient_screen.dart';

class PatientListScreen extends StatefulWidget {
  final String? initialPatientId;

  const PatientListScreen({super.key, this.initialPatientId});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  Staff? _currentStaff;
  List<Patient> _allPatients = [];
  List<Patient> _filteredPatients = [];
  bool _isLoading = true;
  String _genderFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadPatients();

    if (widget.initialPatientId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToPatient(widget.initialPatientId!);
      });
    }
  }

  Future<void> _loadPatients() async {
    try {
      final currentStaff = await _authService.getCurrentStaff();
      print(
        '👤 Patient list - Current staff: ${currentStaff?.name} (${currentStaff?.staffId})',
      );

      List<Patient> patients = [];

      if (currentStaff != null) {
        patients = await _firestoreService.getPatientsByStaffId(
          currentStaff.staffId,
        );
        print('👥 Patient list - Loaded ${patients.length} shared patients');
      }

      setState(() {
        _currentStaff = currentStaff;
        _allPatients = patients;
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      print('❌ Error loading patients: $e');
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredPatients = _allPatients.where((patient) {
        final matchSearch =
            query.isEmpty ||
            patient.name.toLowerCase().contains(query) ||
            patient.mrn.toLowerCase().contains(query);

        final matchGender =
            _genderFilter == 'All' ||
            patient.gender.toLowerCase() == _genderFilter.toLowerCase();

        return matchSearch && matchGender;
      }).toList();
    });
  }

  void _navigateToPatient(String patientId) {
    final patient = _allPatients.firstWhere((p) => p.id == patientId);
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PatientProfileScreen(patient: patient),
          ),
        )
        .then((_) => _loadPatients());
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
          'Patient List',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome and search section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                  decoration: BoxDecoration(
                    gradient: kHeroGradient,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: kBlue600.withValues(alpha: 0.24),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back,',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _currentStaff?.name ?? 'User',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Search Bar
                TextField(
                  controller: _searchController,
                  onChanged: (_) => _applyFilters(),
                  decoration: InputDecoration(
                    hintText: 'Search by name or MRN',
                    hintStyle: const TextStyle(color: kMuted3, fontSize: 14),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: kMuted1,
                    ),
                    filled: true,
                    fillColor: kBgInput,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kBlue200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kBlue200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kBlue400, width: 1.2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _buildGenderFilterChip('All'),
                    const SizedBox(width: 8),
                    _buildGenderFilterChip('Male'),
                    const SizedBox(width: 8),
                    _buildGenderFilterChip('Female'),
                    const SizedBox(width: 8),
                    _buildGenderFilterChip('Other'),
                  ],
                ),
              ],
            ),
          ),

          // Stats Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.people_alt_rounded,
                    count: _allPatients.length,
                    label: 'Patients',
                    color: kBlue600,
                    bgColor: kBlue100,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.assignment_rounded,
                    count: _allPatients.fold<int>(
                      0,
                      (sum, p) => sum + p.woundAssessmentIds.length,
                    ),
                    label: 'Assessments',
                    color: kTeal600,
                    bgColor: kTeal50,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Patient List Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Patient List',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: kInk2,
                  ),
                ),
                PrimaryFAB(
                  label: 'Add Patient',
                  onPressed: () async {
                    final added = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const AddEditPatientScreen(),
                      ),
                    );
                    if (added == true) _loadPatients();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Patient List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPatients.isEmpty
                ? Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.people_outline_rounded,
                            size: 34,
                            color: kMuted1,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'No patients found',
                            style: TextStyle(
                              color: kInk2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try a different search keyword or add a new patient.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredPatients.length,
                    itemBuilder: (context, index) {
                      final patient = _filteredPatients[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFEDF1F7)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              Navigator.of(context)
                                  .push(
                                    MaterialPageRoute(
                                      builder: (_) => PatientProfileScreen(
                                        patient: patient,
                                      ),
                                    ),
                                  )
                                  .then((_) => _loadPatients());
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: kBlue100,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: PatientAvatar(
                                      name: patient.name,
                                      size: 46,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          patient.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15.5,
                                            color: Color(0xFF1F2B3A),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.badge_outlined,
                                              size: 13,
                                              color: kMuted3,
                                            ),
                                            const SizedBox(width: 3),
                                            Flexible(
                                              child: Text(
                                                '${patient.mrn} • ${patient.age}y • ${patient.gender}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Color(0xFF768497),
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kBlue50,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: kBlue100),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.healing_outlined,
                                          size: 13,
                                          color: kPrimary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${patient.woundAssessmentIds.length}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: kPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0xFF728398),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderFilterChip(String label) {
    final selected = _genderFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        _genderFilter = label;
        _applyFilters();
      },
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: selected ? Colors.white : kMuted1,
      ),
      selectedColor: kPrimary,
      backgroundColor: kBgInput,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: selected ? kPrimary : kBlue200),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required int count,
    required String label,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count.toString(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: kInk2,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: kMuted1),
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
    _searchController.dispose();
    super.dispose();
  }
}
