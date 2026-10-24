import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/staff.dart';

class AuthService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Staff? _currentLoggedInStaff;

  // ── Public getters ─────────────────────────────────────────────────────────
  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  Staff? get loggedInStaff => _currentLoggedInStaff;

  // ── Sign in ────────────────────────────────────────────────────────────────
  /// Sign in with [staffId] + [password].
  /// Looks up the staff email from Firestore, then authenticates with Firebase.
  Future<Staff?> signInWithStaffId(String staffId, String password) async {
    _currentLoggedInStaff = null;

    // 1. Resolve the staff ID through the public, single-document lookup.
    final normStaffId = staffId.trim().toUpperCase();
    String email;
    try {
      final lookup = await _firestore
          .collection('staffLookup')
          .doc(normStaffId)
          .get();
      if (!lookup.exists) {
        throw Exception(
          'Staff ID not found. Please check your Staff ID or register first.',
        );
      }
      email = (lookup.data()?['email'] as String?) ?? '';
      if (email.isEmpty) {
        throw Exception(
          'No email on record for this account. Please contact your administrator.',
        );
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw Exception(
          'Login is temporarily unavailable because Firebase is blocking '
          'the staff lookup. Deploy the current Firestore security rules, '
          'then restart the app.',
        );
      }
      rethrow;
    }

    // 2. Sign in with email + password
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          throw Exception('Incorrect password. Please try again.');
        case 'user-not-found':
          throw Exception('No account found for this Staff ID.');
        case 'user-disabled':
          throw Exception(
            'This account has been disabled. Contact your administrator.',
          );
        case 'too-many-requests':
          throw Exception('Too many failed attempts. Please try again later.');
        default:
          throw Exception('Login failed: ${e.message}');
      }
    }

    // 3. Enforce email verification
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null && !firebaseUser.emailVerified) {
      await _auth.signOut();
      throw Exception(
        'Email not verified. Please check your inbox (or spam/junk folder) and click the verification link before logging in.',
      );
    }

    // 4. Load the full profile after authentication.
    final profile = await _firestore
        .collection('staff')
        .where('email', isEqualTo: email.toLowerCase())
        .limit(1)
        .get();
    if (profile.docs.isEmpty) {
      await _auth.signOut();
      throw Exception(
        'Staff profile not found. Please contact your administrator.',
      );
    }
    final staffDoc = profile.docs.first;
    final staff = Staff.fromJson({'id': staffDoc.id, ...staffDoc.data()});

    // Repair accounts created before roles/{uid} was introduced. The
    // Firestore rules require this document for clinical access, and permit a
    // signed-in user to create only their own nurse role.
    final roleRef = _firestore.collection('roles').doc(firebaseUser?.uid);
    final roleSnapshot = await roleRef.get();
    if (!roleSnapshot.exists) {
      await roleRef.set({'role': 'nurse', 'staffId': staff.staffId});
    }

    _currentLoggedInStaff = staff;
    return staff;
  }

  // ── Register ───────────────────────────────────────────────────────────────
  /// Create a new staff account.
  /// - Stores the real [email] and [password] in Firebase Auth.
  /// - Saves staff profile to Firestore with role='nurse'.
  /// - Sends a confirmation / verification email automatically.
  Future<Staff> registerStaff({
    required String staffId,
    required String fullName,
    required String department,
    required String email,
    required String password,
  }) async {
    final normId = staffId.trim().toUpperCase();
    final normName = fullName.trim();
    final normEmail = email.trim().toLowerCase();

    // 1. Ensure Staff ID is not already taken
    final existing = await _firestore
        .collection('staffLookup')
        .doc(normId)
        .get();
    if (existing.exists) {
      throw Exception('Staff ID $normId is already registered.');
    }

    // 2. Create Firebase Auth account with REAL email + password
    UserCredential credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: normEmail,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          throw Exception('An account with this email already exists.');
        case 'invalid-email':
          throw Exception('The email address is not valid.');
        case 'weak-password':
          throw Exception('Password is too weak. Use at least 8 characters.');
        default:
          throw Exception(e.message ?? 'Registration failed.');
      }
    }

    // 3. Save staff profile to Firestore
    try {
      final staffDoc = _firestore.collection('staff').doc();
      await staffDoc.set({
        'staffId': normId,
        'name': normName,
        'department': department.trim(),
        'email': normEmail,
        'role': 'nurse',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 4. Write roles/{uid} so Firestore Security Rules can check the role
      //    without needing a query (rules only support direct document reads).
      await _firestore.collection('roles').doc(credential.user!.uid).set({
        'role': 'nurse',
        'staffId': normId,
      });

      await _firestore.collection('staffLookup').doc(normId).set({
        'email': normEmail,
        'uid': credential.user!.uid,
      });

      // 5. Send confirmation / verification email
      await credential.user?.sendEmailVerification();
      // Verification email sent;

      // 6. Sign out — user must log in manually after verifying
      _currentLoggedInStaff = null;
      await _auth.signOut();

      return Staff(
        id: staffDoc.id,
        staffId: normId,
        name: normName,
        department: department.trim(),
        email: normEmail,
        role: 'nurse',
      );
    } catch (e) {
      // Roll back Auth account if Firestore write fails
      try {
        await credential.user?.delete();
      } catch (_) {}
      await _auth.signOut();
      rethrow;
    }
  }

  // ── Forgot password ────────────────────────────────────────────────────────
  /// Send a password-reset email.
  /// Accepts either a Staff ID (looks up their email) or a direct email address.
  Future<void> sendPasswordReset(String staffIdOrEmail) async {
    String emailToReset;

    if (staffIdOrEmail.contains('@')) {
      // Direct email supplied
      emailToReset = staffIdOrEmail.trim().toLowerCase();
    } else {
      // Treat as Staff ID — use the public, single-document lookup.
      final lookup = await _firestore
          .collection('staffLookup')
          .doc(staffIdOrEmail.trim().toUpperCase())
          .get();

      if (!lookup.exists) {
        throw Exception('Staff ID not found.');
      }

      final storedEmail = lookup.data()?['email'] as String?;
      if (storedEmail == null || storedEmail.isEmpty) {
        throw Exception('No email on record for this Staff ID.');
      }
      emailToReset = storedEmail;
    }

    await _auth.sendPasswordResetEmail(email: emailToReset);
  }

  // ── Sign out ───────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    _currentLoggedInStaff = null;
    await _auth.signOut();
  }

  // ── Get current staff ──────────────────────────────────────────────────────
  Future<Staff?> getCurrentStaff() async {
    try {
      final user = currentUser;
      if (user == null) {
        _currentLoggedInStaff = null;
        return null;
      }

      final email = user.email;
      if (email == null) {
        _currentLoggedInStaff = null;
        return null;
      }

      // Return cached value if it matches the current user
      if (_currentLoggedInStaff != null &&
          _currentLoggedInStaff!.email?.toLowerCase() == email.toLowerCase()) {
        return _currentLoggedInStaff;
      }

      // Query Firestore by email
      final query = await _firestore
          .collection('staff')
          .where('email', isEqualTo: email.toLowerCase())
          .limit(1)
          .get();

      // Fallback: legacy accounts stored staffId derived from email
      if (query.docs.isEmpty) {
        final staffIdFromEmail = email.split('@')[0].toUpperCase();
        final fallback = await _firestore
            .collection('staff')
            .where('staffId', isEqualTo: staffIdFromEmail)
            .limit(1)
            .get();

        if (fallback.docs.isEmpty) {
          _currentLoggedInStaff = null;
          return null;
        }

        final staff = Staff.fromJson({
          'id': fallback.docs.first.id,
          ...fallback.docs.first.data(),
        });
        _currentLoggedInStaff = staff;
        return staff;
      }

      final staff = Staff.fromJson({
        'id': query.docs.first.id,
        ...query.docs.first.data(),
      });
      _currentLoggedInStaff = staff;
      return staff;
    } catch (_) {
      _currentLoggedInStaff = null;
      return null;
    }
  }
}
