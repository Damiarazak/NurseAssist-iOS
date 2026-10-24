import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import '../models/patient.dart';
import '../models/wound_assessment.dart';
import '../models/wound_types_database.dart';
import 'local_storage_service.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Patient operations
  Future<List<Patient>> getPatients() async {
    try {
      final querySnapshot = await _firestore
          .collection('patients')
          .orderBy('registeredDate', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => Patient.fromJson({'id': doc.id, ...doc.data()}))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Shared patient list for all staff members
  Future<List<Patient>> getPatientsByStaffId(String staffId) async {
    try {
      final querySnapshot = await _firestore
          .collection('patients')
          .orderBy('registeredDate', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => Patient.fromJson({'id': doc.id, ...doc.data()}))
          .toList();
    } catch (_) {
      return getPatients();
    }
  }

  Future<Patient?> getPatient(String patientId) async {
    try {
      final doc = await _firestore.collection('patients').doc(patientId).get();
      if (!doc.exists) return null;
      return Patient.fromJson({'id': doc.id, ...doc.data()!});
    } catch (_) {
      return null;
    }
  }

  Future<void> addPatient(Patient patient) async {
    await _firestore
        .collection('patients')
        .doc(patient.id)
        .set(patient.toJson());
  }

  Future<void> updatePatient(Patient patient) async {
    await _firestore
        .collection('patients')
        .doc(patient.id)
        .update(patient.toJson());
  }

  Future<Patient?> getPatientByMrn(String mrn) async {
    try {
      final query = await _firestore
          .collection('patients')
          .where('mrn', isEqualTo: mrn)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return null;

      final doc = query.docs.first;
      return Patient.fromJson({'id': doc.id, ...doc.data()});
    } catch (_) {
      return null;
    }
  }

  Future<void> deletePatientAndAssessments(String patientId) async {
    // Delete related wound assessments first
    final assessmentsSnapshot = await _firestore
        .collection('woundAssessments')
        .where('patientId', isEqualTo: patientId)
        .get();

    for (final doc in assessmentsSnapshot.docs) {
      await _firestore.collection('woundAssessments').doc(doc.id).delete();
    }

    // Delete patient recorda
    await _firestore.collection('patients').doc(patientId).delete();
  }

  // Wound Assessment operations
  Future<List<WoundAssessment>> getWoundAssessments(String patientId) async {
    try {
      final querySnapshot = await _firestore
          .collection('woundAssessments')
          .where('patientId', isEqualTo: patientId)
          .get();

      final items = querySnapshot.docs
          .map((doc) => WoundAssessment.fromJson({'id': doc.id, ...doc.data()}))
          .toList();

      items.sort((a, b) => b.assessmentDate.compareTo(a.assessmentDate));
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<WoundAssessment?> getWoundAssessment(String assessmentId) async {
    try {
      final doc = await _firestore
          .collection('woundAssessments')
          .doc(assessmentId)
          .get();
      if (!doc.exists) return null;
      return WoundAssessment.fromJson({'id': doc.id, ...doc.data()!});
    } catch (_) {
      return null;
    }
  }

  Future<void> addWoundAssessment(WoundAssessment assessment) async {
    await _firestore
        .collection('woundAssessments')
        .doc(assessment.id)
        .set(assessment.toJson());

    // The assessment collection is the source of truth. This denormalized
    // index is optional, so a legacy patient document or older deployed rule
    // must not make a successfully-created assessment appear to fail.
    try {
      await _firestore.collection('patients').doc(assessment.patientId).update({
        'woundAssessmentIds': FieldValue.arrayUnion([assessment.id]),
      });
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied' && e.code != 'not-found') rethrow;
    }
  }

  Future<void> updateWoundAssessment(WoundAssessment assessment) async {
    // Keep audit/training fields out of this payload. Firestore stores their
    // timestamps as Timestamp values, while WoundAssessment.toJson() is also
    // used for local JSON and emits ISO strings. Sending those fields back
    // would make the security rules see them as changed.
    await _firestore.collection('woundAssessments').doc(assessment.id).update({
      'analysisResult': assessment.analysisResult?.toJson(),
      'woundPosition': assessment.woundPosition,
      'additionalNotes': assessment.additionalNotes,
      'requiresSpecialistConfirmation':
          assessment.requiresSpecialistConfirmation,
      'specialistConfirmed': assessment.specialistConfirmed,
    });
  }

  /// Save a clinician's type correction without touching the original
  /// modelPredictedType / modelConfidence fields.
  ///
  /// Call this instead of [updateWoundAssessment] when a nurse or lecturer
  /// corrects the wound type so the ML training audit trail stays clean.
  ///
  /// [correctedByName] is the staff member's display name, stored alongside
  /// [correctedBy] (their staff ID) so the UI can show "Jane Tan (WRN-001)"
  /// instead of just the ID. It's optional and nullable — pass null when
  /// the caller couldn't resolve a name (e.g. cold auth cache) and the UI
  /// will fall back to showing the ID alone.
  Future<void> saveClinicianCorrection({
    required String assessmentId,
    required int correctedType,
    required String correctedName,
    required String correctedBy,
    String? correctedByName,
  }) async {
    await _firestore.collection('woundAssessments').doc(assessmentId).update({
      'clinicianCorrectedType': correctedType,
      'clinicianCorrectedName': correctedName,
      'correctedBy': correctedBy,
      'correctedByName': correctedByName,
      'correctedAt': FieldValue.serverTimestamp(),
      // Reset training approval whenever the label changes
      'approvedForTraining': false,
      'approvedBy': null,
      'approvedAt': null,
    });
  }

  /// Mark a verified image as approved for the next model training run.
  /// Optionally reassigns the wound type and/or leaves feedback for the
  /// nurse who made the original clinician correction.
  /// Should only be called by users with Lecturer or Admin role.
  Future<void> approveForTraining({
    required String assessmentId,
    required String approvedBy,
    int? supervisorCorrectedType,
    String? supervisorFeedback,
  }) async {
    final data = <String, dynamic>{
      'approvedForTraining': true,
      'approvedBy': approvedBy,
      'approvedAt': FieldValue.serverTimestamp(),
    };

    final hasComment = supervisorFeedback?.trim().isNotEmpty ?? false;

    if (supervisorCorrectedType != null) {
      data['supervisorCorrectedType'] = supervisorCorrectedType;
      data['supervisorCorrectedName'] = WoundTypesDatabase.getWoundTypeName(
        supervisorCorrectedType,
      );
    }
    if (hasComment) {
      data['supervisorFeedback'] = supervisorFeedback!.trim();
    }
    if (hasComment || supervisorCorrectedType != null) {
      data['supervisorFeedbackBy'] = approvedBy;
      data['supervisorFeedbackAt'] = FieldValue.serverTimestamp();
      data['hasSupervisorFeedback'] = true;
    }

    await _firestore
        .collection('woundAssessments')
        .doc(assessmentId)
        .update(data);
  }

  /// Fetch all assessments that have been clinician-verified but not yet
  /// approved or rejected for training.  Used by the Lecturer approval queue.
  Future<List<WoundAssessment>> getPendingApprovalAssessments() async {
    try {
      final snapshot = await _firestore
          .collection('woundAssessments')
          .where('clinicianCorrectedType', isNull: false)
          .where('approvedForTraining', isEqualTo: false)
          .get();

      return snapshot.docs
          .map((doc) => WoundAssessment.fromJson({'id': doc.id, ...doc.data()}))
          .where((a) => !a.rejectedForTraining)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Mark an image as unsuitable for training (e.g. poor quality, wrong angle).
  /// Requires supervisor feedback explaining the rejection, and optionally
  /// reassigns the wound type.
  /// Should only be called by users with Lecturer or Admin role.
  Future<void> rejectFromTraining({
    required String assessmentId,
    required String rejectedBy,
    required String supervisorFeedback,
    int? supervisorCorrectedType,
  }) async {
    final data = <String, dynamic>{
      'rejectedForTraining': true,
      'rejectedBy': rejectedBy,
      'rejectedAt': FieldValue.serverTimestamp(),
      'supervisorFeedback': supervisorFeedback.trim(),
      'supervisorFeedbackBy': rejectedBy,
      'supervisorFeedbackAt': FieldValue.serverTimestamp(),
      'hasSupervisorFeedback': true,
    };

    if (supervisorCorrectedType != null) {
      data['supervisorCorrectedType'] = supervisorCorrectedType;
      data['supervisorCorrectedName'] = WoundTypesDatabase.getWoundTypeName(
        supervisorCorrectedType,
      );
    }

    await _firestore
        .collection('woundAssessments')
        .doc(assessmentId)
        .update(data);
  }

  /// Assessments corrected by [staffId] that a supervisor has since
  /// reassigned and/or commented on. Used for the nurse's dashboard badge
  /// and the nurse feedback list screen.
  Future<List<WoundAssessment>> getAssessmentsNeedingAttention(
    String staffId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('woundAssessments')
          .where('correctedBy', isEqualTo: staffId)
          .where('hasSupervisorFeedback', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => WoundAssessment.fromJson({'id': doc.id, ...doc.data()}))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteWoundAssessment({
    required String assessmentId,
    required String patientId,
  }) async {
    await _firestore.collection('woundAssessments').doc(assessmentId).delete();
    await _firestore.collection('patients').doc(patientId).update({
      'woundAssessmentIds': FieldValue.arrayRemove([assessmentId]),
    });
  }

  /// Upload a wound image to Firebase Storage and return its download URL.
  /// Images are stored under wound_images/{uid}/{fileName} so that
  /// Storage security rules can be scoped per user if needed.
  Future<String> uploadWoundImage(File imageFile, String fileName) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final ref = _storage.ref().child('wound_images').child(uid).child(fileName);

    try {
      final uploadTask = await ref.putFile(
        imageFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return await uploadTask.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      final code = e.code.toLowerCase();
      final isStorageQuotaError =
          code == 'quota-exceeded' || code == 'storage/quota-exceeded';

      if (!isStorageQuotaError) rethrow;

      // Keep the assessment usable on this device while Firebase Storage
      // quota is unavailable. Permission and authentication errors still
      // propagate so they are not mistaken for a quota problem.
      return LocalStorageService().saveWoundImage(imageFile, fileName);
    }
  }

  // Initialize sample data
  Future<void> initializeSampleData() async {
    try {
      // Always try to add sample staff (will update if exists)
      await _firestore.collection('staff').doc('staff1').set({
        'staffId': '22167',
        'name': 'AISHA',
        'department': 'Nursing',
      });

      // Check if patients already exist
      final patientsSnapshot = await _firestore
          .collection('patients')
          .limit(1)
          .get();
      if (patientsSnapshot.docs.isNotEmpty) {
        return; // Sample data already exists
      }

      // Add sample patients
      final patients = [
        Patient(
          id: 'patient1',
          mrn: 'MRN-001234',
          name: 'Sabrina Elyasa',
          age: 29,
          gender: 'Female',
          contact: '0174067606',
          registeredDate: DateTime(2025, 12, 14),
          staffIdAssignedTo: 'WRN-001',
        ),
        Patient(
          id: 'patient2',
          mrn: 'MRN-001235',
          name: 'Abdul Wahab',
          age: 67,
          gender: 'Male',
          contact: '0123456789',
          registeredDate: DateTime(2025, 12, 10),
          staffIdAssignedTo: 'WRN-001',
        ),
        Patient(
          id: 'patient3',
          mrn: 'MRN-001236',
          name: 'Nik Marwaa',
          age: 32,
          gender: 'Female',
          contact: '0198765432',
          registeredDate: DateTime(2025, 12, 5),
          staffIdAssignedTo: 'WRN-002',
        ),
      ];

      for (var patient in patients) {
        await addPatient(patient);
      }
    } catch (_) {
      // Initialization failed silently
    }
  }
}
