# NurseAssist Technical Handover Guide

This guide is for the students who will continue developing and running
NurseAssist. It describes the current implementation in this repository, not
only the original project proposal.

## 1. What the system is

NurseAssist is a Flutter mobile application for wound documentation:

1. A staff member signs in with a Staff ID and password.
2. The app loads shared patient records from Firebase Firestore.
3. A nurse captures or selects a wound image.
4. The app checks that the image contains skin, then runs an on-device
   TensorFlow Lite wound classifier.
5. The image is uploaded to Firebase Storage only after it passes the analysis
   guard and privacy confirmation.
6. The result and wound metadata are saved in Firestore.
7. A clinician can correct the predicted type.
8. A lecturer/supervisor can review the correction and approve the image for
   future model training.
9. A Firebase Cloud Function copies approved images into the training-data
   Storage area.

The main runtime components are:

| Component | Technology | Location |
| --- | --- | --- |
| Mobile UI and application logic | Flutter/Dart | `lib/` |
| Login and identity | Firebase Authentication | `lib/services/auth_service.dart` |
| Structured records | Cloud Firestore | `lib/services/firestore_service.dart` |
| Wound image files | Firebase Storage | `lib/services/firestore_service.dart` |
| On-device prediction | TensorFlow Lite | `lib/services/wound_analysis_service.dart` |
| Skin pre-check | Google ML Kit | `lib/services/skin_detection_service.dart` |
| Approval automation | Firebase Cloud Functions/Node.js | `functions/index.js` |
| Training notebooks | Python/Jupyter | `ml/` |

## 2. Important security warning

Never share, upload, or commit:

- `serviceAccountKey.json`
- `.env`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- Firebase passwords, administrator accounts, or private patient data

`serviceAccountKey.json` is a server administrator credential. It must not be
used in the Flutter app. If this key has ever been pushed to a public or
shared Git repository, the Firebase service-account key should be revoked and
replaced in the Firebase Console.

The mobile app uses Firebase client configuration and Firestore/Storage rules.
The Cloud Function uses the Firebase Admin SDK on the server. Keep those two
credential types separate.

## 3. Repository map

### Flutter application

- [`lib/main.dart`](lib/main.dart): loads `.env`, initializes Firebase, and
  starts the app.
- [`lib/theme.dart`](lib/theme.dart): shared colors, typography, button styles,
  and theme helpers.
- [`lib/screens/`](lib/screens/): complete pages and user flows.
  - `login_screen.dart`: Staff ID login and password reset.
  - `user_registration_screen.dart`: new nurse registration.
  - `dashboard_screen.dart`: counts, shortcuts, role-specific actions.
  - `patient_list_screen.dart`: shared patient list.
  - `add_edit_patient_screen.dart`: create/update patient records.
  - `add_patient_lookup_screen.dart`: find and add an existing patient.
  - `patient_profile_screen.dart`: patient details and wound history.
  - `capture_wound_screen.dart`: camera/gallery selection and analysis start.
  - `analysis_results_screen.dart`: prediction, metadata, correction, and save.
  - `lecturer_approval_screen.dart`: approval/rejection and supervisor review.
  - `nurse_feedback_screen.dart`: feedback returned to nurses.
  - `splash_screen.dart`: initial loading screen.
- [`lib/models/`](lib/models/): typed application data objects and
  serialization/deserialization.
- [`lib/services/auth_service.dart`](lib/services/auth_service.dart):
  authentication and staff profile operations.
- [`lib/services/firestore_service.dart`](lib/services/firestore_service.dart):
  patient, assessment, upload, approval, and feedback operations.
- [`lib/services/wound_analysis_service.dart`](lib/services/wound_analysis_service.dart):
  TFLite inference and fallback analysis.
- [`lib/services/ai_config.dart`](lib/services/ai_config.dart): model path,
  input size, confidence thresholds, and analysis method.
- [`lib/services/skin_detection_service.dart`](lib/services/skin_detection_service.dart):
  ML Kit skin/person gate.
- [`lib/services/local_storage_service.dart`](lib/services/local_storage_service.dart):
  local image fallback when Storage quota/errors prevent upload.
- [`lib/widgets/`](lib/widgets/): reusable UI components.
- [`assets/models/`](assets/models/): `wound_classifier.tflite` and
  `wound_labels.txt`.

### Firebase and server code

- [`firebase.json`](firebase.json): tells Firebase CLI where rules, indexes,
  and Functions live.
- [`firestore.rules`](firestore.rules): Firestore authorization by signed-in
  user and role.
- [`storage.rules`](storage.rules): image read/write authorization.
- [`firestore.indexes.json`](firestore.indexes.json): composite query indexes.
- [`functions/index.js`](functions/index.js): copies approved images to
  `training-data/approved/type_X/`.
- [`functions/package.json`](functions/package.json): Node dependency manifest.
- [`ml/`](ml/): model preprocessing, training, and retraining notebooks.
- [`docs/`](docs/): focused implementation notes, including authentication and
  the no-wound guard.

## 4. First-time setup

### Required tools

- Flutter SDK compatible with the Dart constraint in [`pubspec.yaml`](pubspec.yaml)
- Android Studio and/or Xcode
- Node.js 22 for Firebase Functions
- Firebase CLI
- Access to the Firebase project used by the team

Check installations:

```bash
flutter --version
dart --version
node --version
firebase --version
```

### Install Flutter packages

From the repository root:

```bash
flutter pub get
```

Install Functions packages:

```bash
cd functions
npm install
cd ..
```

### Configure Firebase

The app currently calls `Firebase.initializeApp()` without explicit options.
Each developer/device therefore needs the platform Firebase configuration:

- Android: `android/app/google-services.json`
- iOS: `ios/Runner/GoogleService-Info.plist`

Obtain these from the Firebase project owner or register the platform apps in
Firebase Console. Do not copy them into public repositories.

Confirm the Firebase project selected by the CLI:

```bash
firebase login
firebase use nurseassist-b8242
```

Deploy rules and indexes only when the Firebase owner has approved the change:

```bash
firebase deploy --only firestore
```

Deploy the Cloud Function from the repository root:

```bash
firebase deploy --only functions
```

The existing Windows deployment scripts contain machine-specific paths and
should be updated before another computer relies on them:

- [`deploy_firestore.ps1`](deploy_firestore.ps1)
- [`deploy_firestore.bat`](deploy_firestore.bat)

### Run the application

```bash
flutter devices
flutter run
```

For a clean dependency/build troubleshooting pass:

```bash
flutter clean
flutter pub get
flutter run
```

The first run must be on a real phone or an emulator with camera support if
testing wound capture. Camera and photo permissions are platform-specific.

## 5. Backend data model

### Firebase Authentication

Firebase Auth stores the real email/password credential. The UI accepts a
Staff ID. [`AuthService`](lib/services/auth_service.dart) resolves:

```text
Staff ID
  -> staffLookup/{STAFF_ID}
  -> email
  -> Firebase Auth signInWithEmailAndPassword
  -> staff profile in staff/
```

New registrations create:

- a Firebase Auth account;
- a `staff/{documentId}` profile;
- a `roles/{firebaseUid}` document with role `nurse`;
- a `staffLookup/{STAFF_ID}` lookup document.

Email verification is required before login completes.

### Firestore collections

| Collection | Purpose | Main fields |
| --- | --- | --- |
| `staff` | Staff profile | `staffId`, `name`, `department`, `email`, `role` |
| `staffLookup` | Staff ID to email lookup | `email`, `uid` |
| `roles` | Security-rule role lookup | `role`, `staffId` |
| `patients` | Shared patient records | `mrn`, `name`, `age`, `vitalSigns`, `chronicConditions` |
| `woundAssessments` | Wound image/result/history | `patientId`, `imageUrl`, `analysisResult`, audit fields |

The original model prediction is intentionally preserved. Corrections are
stored separately in `clinicianCorrectedType`, and supervisor decisions are
stored in `supervisorCorrectedType`. Do not overwrite the original prediction
when adding review features; the difference between model and clinician is
needed for retraining and audit.

### Storage paths

Client-uploaded images use:

```text
wound_images/{firebase-auth-uid}/{filename}
```

Approved training images are copied by the server function to:

```text
training-data/approved/type_{1..8}/{filename}
```

Clients cannot directly write to the training-data path.

## 6. Security rules and roles

Roles currently recognized by the rules are:

- `nurse`: clinical reading, patient creation/update, assessment work;
- `supervisor` / `lecturer`: review and training approval;
- `admin`: administrative updates/deletion.

Read [`firestore.rules`](firestore.rules) before changing permissions. A role
is read from `roles/{uid}`, because Firestore rules cannot safely perform an
arbitrary query to discover a user's role.

Important behavior:

- all authenticated staff can read patients and wound assessments;
- only authorized roles can create/update patient records;
- only supervisor/lecturer/admin can approve training data;
- nurse updates cannot set `approvedForTraining` to true;
- Storage writes are restricted to the authenticated user's own
  `wound_images/{uid}/` directory.

After changing rules or indexes, deploy and test with both a nurse account and
a lecturer/admin account. Do not test security by temporarily deploying
`allow read, write: if true`.

## 7. Wound-analysis flow

The relevant path is:

```text
CaptureWoundScreen
  -> WoundAnalysisService.analyzeWound()
  -> skin detection gate
  -> TFLite model (224 x 224 x 3, 8 classes)
  -> confidence/no-wound guard
  -> AnalysisResultsScreen
  -> FirestoreService upload + save assessment
```

Current settings are in [`lib/services/ai_config.dart`](lib/services/ai_config.dart):

- method: `tflite`;
- model: `assets/models/wound_classifier.tflite`;
- labels: `assets/models/wound_labels.txt`;
- input: 224 x 224 RGB;
- classes: Type_1 through Type_8;
- minimum accepted confidence: `0.60`;
- no-wound guard threshold: `0.35`;
- skin gate minimum ratio: `0.04`.

The service has an `enhanced_mock` fallback for development, but do not present
that fallback as a clinical model result. If the TFLite analysis fails, the
current code falls back to rule-based analysis and logs the error; this should
be considered a development limitation that must be reviewed before
production/clinical use.

## 8. Approval and retraining flow

1. Nurse saves an assessment with the original model prediction.
2. Nurse/clinician can save a correction using
   `saveClinicianCorrection`.
3. Lecturer/supervisor reviews pending corrections.
4. Lecturer/supervisor calls `approveForTraining`.
5. Firestore changes `approvedForTraining` from false to true.
6. [`copyApprovedWoundImage`](functions/index.js) runs in
   `asia-southeast1`.
7. The function chooses the label in this order:
   supervisor correction → clinician correction → model prediction.
8. It copies the original Storage object and writes `trainingImagePath` back
   to the assessment.
9. The notebooks in [`ml/`](ml/) can use the approved training files.

If approval appears stuck, check Cloud Functions logs and verify the source
`imageUrl` is a Firebase Storage download URL that contains `/o/`.

## 9. How to make code changes

Use the existing separation:

- UI and navigation: `lib/screens/`
- reusable visual elements: `lib/widgets/`
- data shape/serialization: `lib/models/`
- Firebase or device integration: `lib/services/`
- constants and styling: `lib/theme.dart`, `lib/services/ai_config.dart`

For a new Firestore field:

1. Add it to the model constructor and `toJson`.
2. Parse it in `fromJson`, including old/missing documents.
3. Update the service payload that writes it.
4. Review `firestore.rules`.
5. Add/adjust an index if the new query requires one.
6. Update the relevant screen.
7. Test with an old document and a newly created document.

Do not put Firebase queries directly into widgets when an existing service
method can own the operation. Do not silently change the meaning of
`modelPredictedType`; it is an audit snapshot.

Before submitting a change:

```bash
dart format lib test
flutter analyze
flutter test
```

For a model or platform change, also test on a real Android/iOS device.

## 10. Common troubleshooting

| Symptom | First checks |
| --- | --- |
| Firebase initialization fails | Platform config files, package ID/bundle ID, Firebase project selection |
| Login says Staff ID not found | `staffLookup/{UPPERCASE_ID}` exists and has an email |
| Login is permission denied | Deploy current `firestore.rules`; confirm user is authenticated where required |
| Images fail to upload | Storage rules, signed-in UID, device network, Storage quota |
| Camera is blank | Device permission, physical camera/emulator support |
| Every image is rejected | Lighting/skin gate, `skinDetectionMinRatio`, no-wound threshold |
| TFLite model cannot load | Asset paths in `pubspec.yaml`, files under `assets/models/`, `flutter pub get` |
| Approval does not copy an image | Function deployed, correct region/project, valid Storage URL, Functions logs |
| Firestore query asks for an index | Add the suggested index to `firestore.indexes.json`, then deploy Firestore indexes |

## 11. Suggested handover demonstration

When explaining the project, demonstrate this sequence instead of opening files
randomly:

1. Show the repository map and `pubspec.yaml`.
2. Run the app and explain splash → login → dashboard.
3. Register a test nurse account and verify the email.
4. Show the Staff ID lookup and role documents in Firestore.
5. Create/select a test patient.
6. Capture a non-identifying wound image and show the analysis guard.
7. Save the assessment and show the Storage path plus Firestore document.
8. Correct the predicted wound type as the clinician.
9. Switch to a lecturer/admin test account and approve it.
10. Show the Cloud Function log and the copied training path.
11. Explain which files students should change for UI, data, Firebase, and ML.
12. Finish with the security warning and backup/credential ownership.

Use synthetic test patients and non-identifying images for demonstrations.
