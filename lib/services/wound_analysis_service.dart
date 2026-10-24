import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/wound_assessment.dart';
import '../models/wound_types_database.dart';
import 'ai_config.dart';
import 'skin_detection_service.dart';
import 'skin_detection_service.dart';

/// Thrown by [WoundAnalysisService.analyzeWound] when the model's top-class
/// confidence falls below [AIConfig.noWoundConfidenceThreshold] and the guard
/// is enabled.  Callers should prompt the user to retake the photo rather than
/// displaying analysis results.
class NoWoundDetectedException implements Exception {
  final String message;
  const NoWoundDetectedException(this.message);

  @override
  String toString() => message;
}

/// Wound Analysis Service
///
/// Routes wound-image analysis to one of two back-ends:
///   'tflite'        — on-device EfficientNetB0 (primary, offline-capable)
///   'enhanced_mock' — rule-based fallback (image colour heuristics)
///
/// Switch the active method in lib/services/ai_config.dart → analysisMethod.
class WoundAnalysisService {

  // ──────────────────────────────────────────────────────────────────────────
  // Internal state
  // ──────────────────────────────────────────────────────────────────────────

  Interpreter? _interpreter;
  bool _modelLoaded = false;

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Main entry point.  Resolves method from [AIConfig.analysisMethod] and
  /// falls back to enhanced rules on any error.
  Future<WoundAnalysisResult> analyzeWound(File imageFile) async {
    try {
      // ── Skin detection gate (runs before the wound classifier) ───────────
      if (AIConfig.skinDetectionEnabled) {
        final hasSkin = await SkinDetectionService.containsSkin(imageFile);
        if (!hasSkin) {
          throw const NoWoundDetectedException(
            'No skin detected — please ensure the wound area is clearly visible.',
          );
        }
      }

      final method = AIConfig.analysisMethod;
      print('🔍 Starting wound analysis — method: $method');
      print('📊 Config: ${AIConfig.getConfigurationStatus()}');

      switch (method) {
        case 'tflite':
          return await _analyzeWithTFLite(imageFile);
        case 'enhanced_mock':
          return await _analyzeWithEnhancedRules(imageFile);
        default:
          print('⚠️ Unknown method "$method" — falling back to enhanced rules');
          return await _analyzeWithEnhancedRules(imageFile);
      }
    } catch (e) {
      // Let the no-wound guard propagate — do not swallow it into the fallback.
      if (e is NoWoundDetectedException) rethrow;
      print('❌ Analysis error: $e');
      print('🔄 Falling back to enhanced rule-based analysis');
      return await _analyzeWithEnhancedRules(imageFile);
    }
  }

  /// Release interpreter resources.  Call when the owning widget is disposed.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _modelLoaded = false;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TFLite on-device inference
  // ──────────────────────────────────────────────────────────────────────────

  /// Load the TFLite interpreter from assets (once; cached for subsequent
  /// calls).
  Future<void> _loadModel() async {
    if (_modelLoaded) return;

    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(
        'assets/${AIConfig.tfliteModelPath}',
        options: options,
      );
      _modelLoaded = true;
      print('✅ TFLite model loaded (${AIConfig.tfliteModelPath})');
    } catch (e) {
      print('❌ Failed to load TFLite model: $e');
      rethrow;
    }
  }

  /// Run inference with the on-device EfficientNetB0 model.
  ///
  /// The model expects:
  ///   Input  : [1, 224, 224, 3]  float32  — pixel values 0–255 (no /255
  ///             normalisation; EfficientNetB0's built-in preprocessing layer
  ///             handles that inside the model graph)
  ///   Output : [1, 8]            float32  — softmax probabilities for Type_1…8
  Future<WoundAnalysisResult> _analyzeWithTFLite(File imageFile) async {
    // ── Skin detection gate (MediaPipe) ──────────────────────────────────────
    // Runs before TFLite inference so non-skin images are rejected cheaply.
    if (AIConfig.skinDetectionEnabled) {
      print('🔬 Running skin detection gate…');
      final hasSkin = await SkinDetectionService.containsSkin(imageFile);
      if (!hasSkin) {
        print('🚫 Skin gate: no skin detected — rejecting image');
        throw NoWoundDetectedException(
          'No skin detected in the image. Please ensure the wound area '
          'is clearly visible and well-lit in the frame.',
        );
      }
      print('✅ Skin gate passed — proceeding to wound classification');
    }

    await _loadModel();

    final interpreter = _interpreter!;
    final h = AIConfig.tfliteInputHeight;   // 224
    final w = AIConfig.tfliteInputWidth;    // 224
    // channels = 3 (RGB) — tensor is built pixel-by-pixel as [r, g, b]
    final numClasses = AIConfig.tfliteNumClasses; // 8

    // ── 1. Preprocess image → [1, 224, 224, 3] float32 ───────────────────
    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Cannot decode image');

    final resized = img.copyResize(decoded, width: w, height: h);

    // Build input tensor: shape [1, h, w, c]
    final input = List.generate(
      1,
      (_) => List.generate(
        h,
        (y) => List.generate(
          w,
          (x) {
            final pixel = resized.getPixel(x, y);
            // Return float values 0–255 (model normalises internally)
            return [
              pixel.r.toDouble(),
              pixel.g.toDouble(),
              pixel.b.toDouble(),
            ];
          },
        ),
      ),
    );

    // ── 2. Run inference ─────────────────────────────────────────────────
    // Output tensor: shape [1, numClasses]
    final output = List.generate(1, (_) => List<double>.filled(numClasses, 0.0));

    interpreter.run(input, output);

    final probabilities = output[0];

    // ── 3. Argmax → wound type ───────────────────────────────────────────
    int maxIdx = 0;
    double maxProb = probabilities[0];
    for (int i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > maxProb) {
        maxProb = probabilities[i];
        maxIdx = i;
      }
    }

    // Model output index 0 → Type_1, index 7 → Type_8
    final typeId = maxIdx + 1;
    final typeName = WoundTypesDatabase.getWoundTypeName(typeId);
    final confidence = maxProb;

    print('🎯 TFLite → $typeName  confidence: ${(confidence * 100).toStringAsFixed(1)}%');

    // ── No-wound guard ────────────────────────────────────────────────────────
    // If the guard is enabled and the model isn't confident enough, the image
    // probably isn't a wound photo.  Toggle via AIConfig.noWoundDetectionEnabled.
    if (AIConfig.noWoundDetectionEnabled &&
        confidence < AIConfig.noWoundConfidenceThreshold) {
      print('🚫 No-wound guard triggered — '
          '${(confidence * 100).toStringAsFixed(1)}% < '
          '${(AIConfig.noWoundConfidenceThreshold * 100).toStringAsFixed(0)}% threshold');
      throw NoWoundDetectedException(
        'No wound detected — model confidence '
        '${(confidence * 100).toStringAsFixed(1)}% is below the '
        '${(AIConfig.noWoundConfidenceThreshold * 100).toStringAsFixed(0)}% threshold.',
      );
    }
    print('   Full probabilities: ${_formatProbabilities(probabilities)}');

    return _generateResultForWoundType(typeName, confidence,
        List<double>.from(probabilities));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Enhanced rule-based fallback
  // ──────────────────────────────────────────────────────────────────────────

  Future<WoundAnalysisResult> _analyzeWithEnhancedRules(
      File imageFile) async {
    try {
      print('🔬 Enhanced rule-based analysis …');
      final chars = await _analyzeImageCharacteristics(imageFile);
      final typeId = _classifyFromCharacteristics(chars);
      final confidence = _calculateConfidence(chars);
      final typeName = WoundTypesDatabase.getWoundTypeName(typeId);

      print('✅ Enhanced rules → $typeName  '
          'confidence: ${(confidence * 100).toStringAsFixed(1)}%');

      return _generateResultForWoundType(typeName, confidence);
    } catch (e) {
      print('Enhanced analysis error: $e');
      // Ultimate fallback — lowest severity type
      return _generateResultForWoundType('Type_1', 0.50);
    }
  }

  Future<Map<String, dynamic>> _analyzeImageCharacteristics(
      File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);

    if (image == null) return {'error': 'Could not decode image'};

    int redTotal = 0, greenTotal = 0, blueTotal = 0;
    int darkPixels = 0, brightPixels = 0;
    final totalPixels = image.width * image.height;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        redTotal += r;
        greenTotal += g;
        blueTotal += b;

        final brightness = (r + g + b) / 3;
        if (brightness < 80) darkPixels++;
        if (brightness > 180) brightPixels++;
      }
    }

    final avgRed = redTotal / totalPixels;
    final avgGreen = greenTotal / totalPixels;
    final avgBlue = blueTotal / totalPixels;
    final redness = avgRed / (avgGreen + avgBlue + 1);
    final darkness = darkPixels / totalPixels;
    final brightness = brightPixels / totalPixels;

    return {
      'redness': redness,
      'darkness': darkness,
      'brightness': brightness,
      'avgRed': avgRed,
      'avgGreen': avgGreen,
      'avgBlue': avgBlue,
      'width': image.width,
      'height': image.height,
    };
  }

  /// Maps colour characteristics to a wound type ID (1–8).
  int _classifyFromCharacteristics(Map<String, dynamic> chars) {
    final redness = chars['redness'] as double;
    final darkness = chars['darkness'] as double;
    final brightness = chars['brightness'] as double;

    // Type_8 — bright, low darkness → healing/granulating
    if (brightness > 0.45 && darkness < 0.2) return 8;

    // Type_1 / Type_2 — superficial, low necrosis
    if (darkness < 0.3) {
      return redness > 1.2 ? 2 : 1;
    }

    // Type_3 — moderate darkness + high redness (infection sign)
    if (darkness >= 0.3 && darkness < 0.45 && redness > 1.3) return 3;

    // Type_4 — moderate darkness, dry (low redness)
    if (darkness >= 0.3 && darkness < 0.5 && redness <= 1.3) return 4;

    // Type_5 — significant darkness, wet (moderate redness)
    if (darkness >= 0.5 && darkness < 0.65 && redness <= 1.3) return 5;

    // Type_6 — significant darkness + high redness
    if (darkness >= 0.5 && darkness < 0.7 && redness > 1.1) return 6;

    // Type_7 / Type_8 at extreme darkness
    if (darkness >= 0.7) return redness > 1.4 ? 7 : 6;

    return 1; // default
  }

  double _calculateConfidence(Map<String, dynamic> chars) {
    double confidence = 0.72;
    final redness = chars['redness'] as double;
    final darkness = chars['darkness'] as double;
    if (redness > 1.5 || redness < 0.8) confidence += 0.08;
    if (darkness > 0.6 || darkness < 0.2) confidence += 0.08;
    return min(confidence, 0.92);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Shared helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// Build a [WoundAnalysisResult] from the wound types database.
  WoundAnalysisResult _generateResultForWoundType(
      String typeName, [double? confidence,
      List<double>? allClassProbabilities]) {
    final woundData = WoundTypesDatabase.getWoundTypeData(typeName);
    final characteristics =
        woundData['characteristics'] as Map<String, dynamic>;
    final management = woundData['management'] as Map<String, dynamic>;

    return WoundAnalysisResult(
      confidenceScore: confidence ?? 0.85,
      woundType: WoundTypesDatabase.getWoundTypeId(typeName),
      woundName: typeName,
      severity: woundData['severity'] as String,
      estimatedSize: null,
      allClassProbabilities: allClassProbabilities,
      characteristics: WoundCharacteristics(
        necroticTissue: characteristics['necroticTissue'] as String,
        infection: characteristics['infection'] as String,
        exudateLevel: characteristics['exudateLevel'] as String,
        tissueClassification:
            List<String>.from(characteristics['tissueClassification']),
      ),
      management: WoundManagement(
        dressingMaterials:
            List<String>.from(management['dressingMaterials']),
        antibioticRecommendation:
            management['antibioticRecommendation'] as String,
        surgicalProcedures:
            List<String>.from(management['surgicalProcedures']),
        additionalNotes: management['additionalNotes'] as String?,
      ),
      segmentationMapUrl: null,
    );
  }

  /// Human-readable probability vector for debug logging.
  String _formatProbabilities(List<double> probs) {
    return probs
        .asMap()
        .entries
        .map((e) =>
            'Type_${e.key + 1}: ${(e.value * 100).toStringAsFixed(1)}%')
        .join(', ');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Utility
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns true for wound types that require a specialist to confirm the
  /// model prediction before the management plan is acted upon.
  bool requiresSpecialistConfirmation(int woundTypeId) {
    final name = WoundTypesDatabase.getWoundTypeName(woundTypeId);
    return WoundTypesDatabase.requiresSpecialistConfirmation(name);
  }
}
