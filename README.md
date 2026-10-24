# NurseAssist – iOS Wound Management Application

## Overview

This repository contains my individual iOS implementation of NurseAssist, a
Flutter-based wound assessment and clinical management application.

NurseAssist helps healthcare staff capture wound images, analyse wound type
and severity, manage patient records, and save assessment results for later
review. The Android implementation is maintained separately and is not
included in this repository.

## Problem addressed

Wound assessment can be time-consuming and difficult to standardise when it
depends on manual observation and documentation. NurseAssist supports the
clinical workflow by combining image-based wound classification with patient
records, wound characteristics, and management guidance in one mobile
application.

The application is intended to support healthcare staff in assessment and
documentation. It does not replace professional clinical judgement.

#### **b. Project Scope**

NurseAssist is developed as a mobile application with shared Flutter
application code and separate platform implementations. This repository is
the general project workspace; platform-specific work may be maintained in
separate repositories.

## Main features

- Staff authentication and role-based access
- Patient registration, search, and profile management
- Wound image capture from an iOS device
- On-device wound image analysis
- Wound type, confidence, severity, and characteristics display
- Wound location and clinical notes
- Wound management and dressing recommendations
- Assessment history linked to a patient
- Clinician verification and correction of AI predictions
- Supervisor or lecturer review workflows
- Firebase persistence for authenticated staff and clinical records
- Local image fallback when Firebase Storage quota is unavailable

## How the application works

1. A staff member signs in with a Staff ID and password.
2. Firebase Authentication verifies the account and email status.
3. The app loads the staff role and available patient records from Firestore.
4. The staff member selects a patient and captures a wound image.
5. The image passes through the AI analysis pipeline.
6. The app displays the predicted wound type, confidence, severity,
   characteristics, and management guidance.
7. The compressed image and assessment record are saved to Firebase.
8. The assessment can later be reviewed, edited, clinically corrected, or
   approved for training by an authorised reviewer.

## AI and machine-learning pipeline

### 1. Image input

The iOS app receives an image from the camera or image picker. Before cloud
upload, the image is compressed to reduce file size and network usage.

### 2. Skin and subject detection gate

The app uses Google ML Kit Selfie Segmentation through
`google_mlkit_selfie_segmentation`. This is an on-device pre-check that
estimates whether the image contains visible human tissue or a person-like
subject.

Images that do not pass the configured skin-pixel threshold can be rejected
with a request to retake the photo. If the segmentation service itself fails,
the app allows the image through so a real wound is not blocked by a
pre-processing error.

### 3. Wound classification

The primary classifier uses TensorFlow Lite through `tflite_flutter`.
The model is bundled in the application assets and runs locally on the
device, so the wound classification step does not require an AI cloud API.

The current inference configuration is:

- Model family: EfficientNetB0-based TensorFlow Lite classifier
- Input tensor: `224 x 224 x 3`
- Input values: RGB pixel values
- Output: eight class probabilities
- Classes: `Type_1` through `Type_8`
- Result: highest-probability wound type and confidence score

The model is loaded once and reused during the session. Inference results are
converted into a `WoundAnalysisResult`, which also contains wound severity,
estimated size, characteristics, management information, and class
probabilities where available.

### 4. Fallback analysis

If the TensorFlow Lite model cannot be loaded or inference fails, the service
uses the configured rule-based fallback analysis. This keeps the application
usable while clearly separating the primary model path from the fallback
path.

The active analysis method is configured in:

```text
lib/services/ai_config.dart
```

## Technology and integrations

### Flutter and iOS

- Flutter and Dart for the application layer
- Xcode and CocoaPods for the iOS build
- Camera and image-picker plugins for image capture
- Local application storage for the image fallback path

### Firebase

- Firebase Authentication for staff login
- Cloud Firestore for staff, roles, patients, and wound assessments
- Firebase Storage for wound image uploads
- Firestore and Storage security rules for access control

The iOS Firebase configuration is stored in:

```text
ios/Runner/GoogleService-Info.plist
```

### Local AI

- `tflite_flutter` for TensorFlow Lite inference
- `google_mlkit_selfie_segmentation` for the image pre-check
- `image` for image decoding and resizing
- `flutter_image_compress` for upload compression

## Data flow

```text
iOS camera / image picker
          |
          v
Image compression and local preprocessing
          |
          v
ML Kit skin-detection gate
          |
          v
TensorFlow Lite wound classifier
          |
          v
WoundAnalysisResult
          |
          +--> Firebase Storage: wound image
          |
          +--> Cloud Firestore: assessment and patient link
```

The original model prediction is kept as an audit snapshot. Clinician and
supervisor corrections are stored separately so that the original AI result
is not overwritten.

## Repository scope

```text
ios/       iOS and Xcode project files
lib/       Flutter screens, models, services, and widgets
assets/    Application images and machine-learning models
test/      Flutter tests
```

Android platform files are maintained in a separate repository.

### **f. Supported Platforms**

NurseAssist supports Android and iOS through Flutter. The platform
implementations may be maintained separately while sharing the application
models, screens, services, and assets.

## Requirements

- macOS
- Xcode
- Flutter SDK
- CocoaPods
- An iOS device or simulator

## Setup

```bash
git clone https://github.com/Damiarazak/NurseAssist-iOS.git
cd NurseAssist-iOS
flutter pub get
cd ios
pod install
cd ..
```

Open the iOS workspace:

```bash
open ios/Runner.xcworkspace
```

Create a local `.env` file from `.env.example` when required. Do not commit
`.env`, passwords, API tokens, service-account keys, or other private
credentials.

## Run and validate

List available devices:

```bash
flutter devices
```

Run the iOS application:

```bash
flutter run -d <device-id>
```

Run analysis and tests:

```bash
flutter analyze
flutter test
```

Wound management is a critical nursing responsibility. Existing solutions are limited, costly, or not localized. Most apps do not combine:

* AI wound classification
* Tailored treatment recommendations
* Full patient record management
* Healing progress tracking

NurseAssist fills this gap by offering a comprehensive, AI-driven, affordable tool designed specifically for nurses and healthcare workers.

---

# 📊 **2. Requirement Analysis & Planning**

## **2.1 Technical Feasibility**

### **Backend Structure**

* REST API for AI image classification
* Authentication API for secure login
* CRUD operations for:

  * Patient profiles
  * Wound records
  * Healing progress images
  * AI-generated recommendations

---

### **Database Design (CRUD)**

* **Patient**
* **WoundRecord**
* **HealingProgress**
* **Recommendations**

---

### **Data Storage**

* **Firebase Storage** → Image files
* **MySQL / Firebase Firestore** → Patient, wound, and treatment data

---



### **a. Platform Compatibility**

* Android smartphones
* Android tablets used in medical environments
* Future iOS compatibility
* Works with various camera sensors and resolutions

---

# 🎨 **3. Project Design**

## **3.1 User Interface (UI)**

UI principles:

* Clean, minimal, medical-friendly color palette
* Large buttons for ease of use
* Fast access to camera
* Consistent layout and typography
* Mobile-first responsive design

---

## **3.2 User Experience (UX)**

Designed for speed and simplicity:

1. Home
2. Capture Image
3. View AI Result
4. Save to Patient Record

Smooth navigation ensures nurses can work efficiently even under pressure.

---

## **3.3 Consistency**

* Hospital-safe color scheme (blue/white/green)
* Consistent form fields and button styles
* Standard spacing and card components

---

## Firebase rules

The project rules are stored in:

```text
firestore.rules
storage.rules
```

Deploy these rules only when authorised to modify the Firebase project. The
application requires an authenticated, verified staff account and a matching
role document for clinical Firestore access.
