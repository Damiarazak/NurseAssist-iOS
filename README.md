# **NurseAssist – Mobile Wound Management Assistant**

## 📌 **1. Project Ideation & Initiation**

### **1.1 Mobile App Details**

#### **a. Title**

**NurseAssist – Smart Wound Management App**

#### **b. Project Scope**

NurseAssist is developed as a mobile application with shared Flutter
application code and separate platform implementations. This repository is
the general project workspace; platform-specific work may be maintained in
separate repositories.

---

### **c. Background of the Problem**

Nurses handle multiple patients daily, and wound management requires careful attention, accurate assessment, and consistent monitoring. In busy clinical environments, manual documentation and delayed assessments can reduce care quality. Common challenges include:

* Difficulty identifying wound type accurately
* Time-consuming manual documentation
* Lack of standardized treatment suggestions
* Limited ability to track and compare wound healing progress

A mobile app that analyzes wounds and recommends treatments can significantly improve workflow, accuracy, and patient outcomes.

---

### **d. Purpose / Objectives**

NurseAssist aims to:

* Provide **accurate wound classification** using image recognition
* Offer **instant treatment suggestions** such as cleaning steps and dressing materials
* Enable nurses to **track healing progress** with visual history
* Maintain **secure patient and wound records**
* Improve workflow efficiency via reminders and notifications

---

### **e. Target Users**

* Nurses in hospitals and clinics
* Nursing students
* Healthcare assistants involved in wound care
* Medical practitioners needing quick assessments

Typical environments: hospital wards, outpatient clinics, emergency rooms, and home-care visits.

---

### **f. Supported Platforms**

NurseAssist supports Android and iOS through Flutter. The platform
implementations may be maintained separately while sharing the application
models, screens, services, and assets.

---

### **g. Features & Functionalities**

1. **Wound Image Capture**
   Capture or upload wound images for analysis.

2. **Automatic Wound Classification**
   AI identifies wound type and severity.

3. **Treatment Suggestions**
   Recommended cleaning steps and suitable dressing materials.

4. **Healing Progress Monitoring**
   Timeline view and comparison of wound changes over time.

5. **Patient Records System**
   Secure storage of patient profiles and wound histories.

6. **Notifications & Reminders**
   Alerts for dressing changes, follow-up checks, and overdue tasks.

---

## 🌐 **1.2 Justification of the Proposed App**

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



