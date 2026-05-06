import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceService {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(enableContours: true,enableClassification: true,enableTracking: true),
  );

  Future<Face?> detectSingleFace(String path) async {

    final inputImage = InputImage.fromFilePath(path);
    final faces = await _detector.processImage(inputImage);
    if (faces.isEmpty) return null;
    return faces.first;
  }

  List<double> extractFeatures(Face face) {
    return [
      face.headEulerAngleY ?? 0,
      face.headEulerAngleZ ?? 0,
      face.boundingBox.width,
      face.boundingBox.height,
    ];
  }

  double compare(List<double> f1, List<double> f2) {
    double sum = 0;
    for (int i = 0; i < f1.length; i++) {
      sum += (f1[i] - f2[i]) * (f1[i] - f2[i]);
    }
    return sum;
  }

  // Future<img.Image?> cropFace(String path, Face face) async {
  //   final image = img.decodeImage(await File(path).readAsBytes());
  //
  //   if (image == null) return null;
  //
  //   final rect = face.boundingBox;
  //
  //   final x = rect.left.toInt().clamp(0, image.width - 1);
  //   final y = rect.top.toInt().clamp(0, image.height - 1);
  //   final w = rect.width.toInt().clamp(0, image.width - x);
  //   final h = rect.height.toInt().clamp(0, image.height - y);
  //
  //   return img.copyCrop(
  //     image,
  //     x: x,
  //     y: y,
  //     width: w,
  //     height: h,
  //   );
  // }

  Future<img.Image?> cropFace(String path, Face face) async {
    final imageBytes = await File(path).readAsBytes();
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      debugPrint('❌ cropFace: could not decode image');
      return null;
    }

    final rect = face.boundingBox;

    // ── Debug: print raw bounding box values ──────────────────────
    debugPrint('📦 BoundingBox → '
        'left: ${rect.left}, '
        'top: ${rect.top}, '
        'width: ${rect.width}, '
        'height: ${rect.height}');
    debugPrint('🖼️ Image size → width: ${image.width}, height: ${image.height}');
    // ──────────────────────────────────────────────────────────────

    // Guard: bounding box must be valid before doing any math
    if (rect.width <= 0 || rect.height <= 0) {
      debugPrint('❌ cropFace: invalid bounding box size');
      return null;
    }

    if (rect.left < 0 || rect.top < 0) {
      debugPrint('❌ cropFace: bounding box has negative origin');
      return null;
    }

    // Safe padding calculation — use integer math only
    final int rawX = rect.left.toInt();
    final int rawY = rect.top.toInt();
    final int rawW = rect.width.toInt();
    final int rawH = rect.height.toInt();

    final int padding = (rawW * 0.20).toInt(); // 20% of width

    // Clamp everything to image bounds
    final int x = (rawX - padding).clamp(0, image.width - 1);
    final int y = (rawY - padding).clamp(0, image.height - 1);

    // Width and height must not exceed image boundary from x/y
    final int w = (rawW + padding * 2).clamp(1, image.width - x);
    final int h = (rawH + padding * 2).clamp(1, image.height - y);

    debugPrint('✂️ Crop → x: $x, y: $y, w: $w, h: $h');

    // Guard: final crop dimensions must be positive
    if (w <= 0 || h <= 0) {
      debugPrint('❌ cropFace: calculated crop dimensions are invalid');
      return null;
    }

    try {
      return img.copyCrop(image, x: x, y: y, width: w, height: h);
    } catch (e) {
      debugPrint('❌ cropFace: copyCrop threw → $e');
      return null;
    }
  }

  // ✅ Always close when done
  void dispose() {
    _detector.close();
  }
}