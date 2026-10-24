# NurseAssist – iOS Wound Management Application

## About this repository

This repository contains my individual iOS implementation of NurseAssist, a
Flutter-based wound assessment and clinical management application.

The iOS version allows healthcare staff to:

- Manage patient records
- Capture wound images
- Analyse wounds using the integrated wound classification workflow
- Review wound characteristics and severity
- Record wound management information
- Save assessments to Firebase
- Review and update assessment results

The Android implementation is maintained separately by another team member
and is not included in this repository.

## My iOS work

This repository covers the iOS project setup and implementation, including:

- Flutter application code used by the iOS app
- iOS project configuration and Xcode integration
- Firebase integration for iOS
- iOS image capture and image upload workflow
- iOS wound assessment screens and services
- iOS testing and device deployment

## Project structure

```text
ios/       iOS and Xcode project files
lib/       Flutter application code
assets/    Application assets and machine-learning files
test/      Flutter tests
```

## Requirements

- macOS
- Xcode
- Flutter SDK
- CocoaPods
- An iOS device or simulator

## Setup

Clone the repository and install the dependencies:

```bash
git clone https://github.com/Damiarazak/NurseAssist-iOS.git
cd NurseAssist-iOS
flutter pub get
cd ios
pod install
cd ..
```

Open the iOS workspace in Xcode:

```bash
open ios/Runner.xcworkspace
```

Create a local `.env` file from `.env.example` when required. Do not commit
`.env` or any private credentials.

## Run the iOS application

List available devices:

```bash
flutter devices
```

Run the application on a connected iOS device or simulator:

```bash
flutter run -d <device-id>
```

## Validate the project

```bash
flutter analyze
flutter test
```

## Firebase

The iOS Firebase configuration is located at:

```text
ios/Runner/GoogleService-Info.plist
```

Firestore and Storage rules are stored in:

```text
firestore.rules
storage.rules
```

Firebase rules should only be deployed by an authorized project
administrator. Passwords, API tokens, service account keys, `.env`, and other
private credentials must not be committed.
