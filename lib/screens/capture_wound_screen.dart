import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../theme.dart';
import '../widgets/patient_avatar.dart';
import '../models/patient.dart';
import '../models/wound_assessment.dart';
import '../services/firestore_service.dart';
import '../services/wound_analysis_service.dart'
    show WoundAnalysisService, NoWoundDetectedException;
import 'analysis_results_screen.dart';

class CaptureWoundScreen extends StatefulWidget {
  final Patient patient;

  const CaptureWoundScreen({super.key, required this.patient});

  @override
  State<CaptureWoundScreen> createState() => _CaptureWoundScreenState();
}

class _CaptureWoundScreenState extends State<CaptureWoundScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  File? _capturedImage;
  bool _isProcessing = false;
  String _processingStatus = '';
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _otherWoundPositionController =
      TextEditingController();
  String? _selectedWoundPosition;

  static const List<String> _woundPositionOptions = [
    'Sacrum',
    'Left leg',
    'Right leg',
    'Left heel',
    'Right heel',
    'Abdomen',
    'Back',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() => _isCameraInitialized = true);
        }
      }
    } catch (_) {
      // Camera unavailable — user can still use gallery
    }
  }

  Future<void> _takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final XFile image = await _cameraController!.takePicture();
      setState(() {
        _capturedImage = File(image.path);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error taking picture: $e')));
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (image != null) {
        setState(() {
          _capturedImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
      }
    }
  }

  Future<void> _confirmAndAnalyze() async {
    if (_capturedImage == null) return;

    final resolvedPosition = _resolvedWoundPosition();
    if (resolvedPosition == null) {
      showErrorSnack(context, 'Please select wound position before analysis');
      return;
    }

    // ── Privacy confirmation before upload ───────────────────────────────────
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(Icons.privacy_tip_rounded, color: kWarning, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Privacy Check',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Before uploading, please confirm the image does NOT contain:',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 12),
            _PrivacyCheckItem(text: 'Patient name or ID number'),
            _PrivacyCheckItem(text: 'Hospital wristband or ID card'),
            _PrivacyCheckItem(text: 'Any visible paperwork or labels'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Retake Photo'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kSuccess,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Confirmed — Proceed'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      _retakePhoto();
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingStatus = 'Uploading image…';
    });

    try {
      final firestoreService = FirestoreService();
      final analysisService = WoundAnalysisService();

      // Show analyzing dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => Center(
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _processingStatus,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      // Analyze wound FIRST — only upload to Storage if the image passes the gate
      if (mounted) setState(() => _processingStatus = 'Analyzing wound…');
      final analysisResult = await analysisService.analyzeWound(
        _capturedImage!,
      );

      // Gate passed — now compress and upload
      if (mounted) setState(() => _processingStatus = 'Compressing image…');
      final compressedImage = await _compressImageIsolate(_capturedImage!.path);

      if (mounted) setState(() => _processingStatus = 'Uploading image…');
      final fileName = 'wound_${const Uuid().v4()}.jpg';
      final imageUrl = await firestoreService.uploadWoundImage(
        compressedImage,
        fileName,
      );

      final assessment = WoundAssessment(
        id: const Uuid().v4(),
        patientId: widget.patient.id,
        imageUrl: imageUrl,
        assessmentDate: DateTime.now(),
        analysisResult: analysisResult,
        woundPosition: resolvedPosition,
        requiresSpecialistConfirmation: analysisService
            .requiresSpecialistConfirmation(analysisResult.woundType),
        modelPredictedType: analysisResult.woundType,
        modelConfidence: analysisResult.confidenceScore,
      );

      // Save to Firestore
      await firestoreService.addWoundAssessment(assessment);

      if (mounted) {
        Navigator.of(context).pop(); // Close analyzing dialog

        final result = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => AnalysisResultsScreen(
              patient: widget.patient,
              assessment: assessment,
            ),
          ),
        );

        if (mounted) {
          Navigator.of(context).pop(result ?? true);
        }
      }
    } on NoWoundDetectedException catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog
        _retakePhoto();

        // Determine whether it was a skin-gate rejection or a low-confidence
        // wound-classifier rejection so we can show the right message.
        final isSkinRejection = e.message.toLowerCase().contains(
          'no skin detected',
        );

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Row(
              children: [
                Icon(
                  isSkinRejection
                      ? Icons.pan_tool_alt_outlined
                      : Icons.image_search_rounded,
                  color: Colors.orange.shade700,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  isSkinRejection ? 'No Skin Detected' : 'No Wound Detected',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            content: Text(
              isSkinRejection
                  ? 'No skin was detected in the image.\n\n'
                        'Please ensure:\n'
                        '• The wound area is clearly visible\n'
                        '• The camera is close enough to the wound\n'
                        '• The image is well-lit'
                  : 'The image does not appear to contain a wound.\n\n'
                        'Please retake the photo with the wound clearly '
                        'in the centre of the frame.',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Retake Photo'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog
        showErrorSnack(
          context,
          'Error: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _retakePhoto() {
    setState(() => _capturedImage = null);
  }

  String? _resolvedWoundPosition() {
    if (_selectedWoundPosition == null) return null;
    if (_selectedWoundPosition != 'Other') return _selectedWoundPosition;
    final custom = _otherWoundPositionController.text.trim();
    return custom.isEmpty ? null : custom;
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
          'Capture Wound Image',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_capturedImage != null)
            IconButton(icon: const Icon(Icons.close), onPressed: _retakePhoto),
        ],
      ),
      body: Column(
        children: [
          // Patient Info
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                PatientAvatar(name: widget.patient.name, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.patient.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${widget.patient.age} years • ${widget.patient.gender}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Privacy warning banner — shown while camera is active
          if (_capturedImage == null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: kWarningBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: kWarning.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.privacy_tip_outlined, color: kWarning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ensure no patient identification (name tag, wristband, ID card) '
                      'is visible in the frame before capturing.',
                      style: TextStyle(fontSize: 12, color: kInk2),
                    ),
                  ),
                ],
              ),
            ),

          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBlue200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wound Location',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kInk2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select the wound location before analyzing.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _woundPositionOptions.map((option) {
                    final selected = _selectedWoundPosition == option;
                    return ChoiceChip(
                      label: Text(option),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _selectedWoundPosition = option;
                          if (option != 'Other') {
                            _otherWoundPositionController.clear();
                          }
                        });
                      },
                      selectedColor: kPrimary,
                      backgroundColor: kBgInput,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : kMuted1,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    );
                  }).toList(),
                ),
                if (_selectedWoundPosition == 'Other') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _otherWoundPositionController,
                    decoration: InputDecoration(
                      hintText: 'Enter wound location',
                      filled: true,
                      fillColor: kBgInput,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBlue200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBlue200),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Camera or Image Preview
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _capturedImage != null
                    ? _buildImagePreview()
                    : _buildCameraView(),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Action Buttons
          if (_capturedImage == null)
            _buildCaptureButtons()
          else
            _buildConfirmButtons(),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    if (!_isCameraInitialized || _cameraController == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing camera...'),
          ],
        ),
      );
    }

    return CameraPreview(_cameraController!);
  }

  Widget _buildImagePreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(_capturedImage!, fit: BoxFit.contain),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Review Captured Image',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCaptureButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _pickImageFromGallery,
              icon: const Icon(Icons.photo_library),
              label: const Text('Gallery'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _takePicture,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Capture New Wound'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isProcessing ? null : _retakePhoto,
              icon: const Icon(Icons.refresh),
              label: const Text('Capture New Wound'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _confirmAndAnalyze,
              icon: const Icon(Icons.check),
              label: const Text('Confirm & Analyze'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kSuccess,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _otherWoundPositionController.dispose();
    super.dispose();
  }
}

// ── Image compression ──────────────────────────────────────────────────────────
//
// Resizes to max 1024 px on the longest side and re-encodes at 85 % JPEG
// quality.  A typical 4 MB phone photo becomes ~250–400 KB.

Future<File> _compressImageIsolate(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final source = img.decodeImage(bytes);
  if (source == null) return File(imagePath); // fallback: use original

  const maxDim = 1024;
  final img.Image resized;

  if (source.width >= source.height && source.width > maxDim) {
    resized = img.copyResize(source, width: maxDim);
  } else if (source.height > source.width && source.height > maxDim) {
    resized = img.copyResize(source, height: maxDim);
  } else {
    resized = source; // already small enough
  }

  final compressed = img.encodeJpg(resized, quality: 85);

  final tempDir = await getTemporaryDirectory();
  final tempFile = File(
    '${tempDir.path}/wound_compressed_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  await tempFile.writeAsBytes(compressed);
  return tempFile;
}

// ── Privacy check list item ────────────────────────────────────────────────────

class _PrivacyCheckItem extends StatelessWidget {
  final String text;
  const _PrivacyCheckItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cancel_outlined, size: 15, color: Colors.red.shade400),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
