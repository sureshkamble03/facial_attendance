import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'embeding_encryption_service.dart';
/*
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
}*/



class FaceService {

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      enableTracking: true,
      enableLandmarks: true,        // Good for better cropping
    ),
  );

  // ─────────────────────────────────────────────────────────────
  // NEW: Detect Multiple Faces (Most Important for Group Scan)
  // ─────────────────────────────────────────────────────────────
  Future<List<Face>> detectFaces(String path) async {
    try {
      final inputImage = InputImage.fromFilePath(path);

      // Use more accurate settings for group photos
      final options = FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
        enableClassification: true,
        performanceMode: FaceDetectorMode.accurate,   // Better for multiple faces
        minFaceSize: 0.1,  // Lower this to detect smaller faces
      );

      final detector = FaceDetector(options: options);
      final faces = await detector.processImage(inputImage);
      detector.close();

      debugPrint('👥 FaceDetector found ${faces.length} faces');
      for (int i = 0; i < faces.length; i++) {
        final box = faces[i].boundingBox;
        debugPrint('   Face ${i+1}: ${box.width.toInt()}x${box.height.toInt()} at (${box.left.toInt()}, ${box.top.toInt()})');
      }

      return faces;
    } catch (e) {
      debugPrint('❌ Face detection error: $e');
      return [];
    }
  }

  // Keep your existing single face method for backward compatibility
  Future<Face?> detectSingleFace(String path) async {
    final faces = await detectFaces(path);
    return faces.isNotEmpty ? faces.first : null;
  }

  // ─────────────────────────────────────────────────────────────
  // Crop Single Face (Your current method - Improved slightly)
  // ─────────────────────────────────────────────────────────────
 /* Future<img.Image?> cropFace(String path, Face face) async {
    try {
      final imageBytes = await File(path).readAsBytes();
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        debugPrint('❌ cropFace: could not decode image');
        return null;
      }

      final rect = face.boundingBox;

      if (rect.width <= 0 || rect.height <= 0) {
        debugPrint('❌ cropFace: invalid bounding box');
        return null;
      }

      final int padding = (rect.width * 0.20).toInt(); // 20% padding

      final int x = (rect.left.toInt() - padding).clamp(0, image.width - 1);
      final int y = (rect.top.toInt() - padding).clamp(0, image.height - 1);
      final int w = (rect.width.toInt() + padding * 2).clamp(1, image.width - x);
      final int h = (rect.height.toInt() + padding * 2).clamp(1, image.height - y);

      if (w <= 0 || h <= 0) return null;

      debugPrint('✂️ Cropping face → x:$x y:$y w:$w h:$h');

      return img.copyCrop(image, x: x, y: y, width: w, height: h);
    } catch (e) {
      debugPrint('❌ cropFace exception: $e');
      return null;
    }
  }*/

  Future<img.Image?> cropFace(String path, Face face) async {
    try {
      final imageBytes = await File(path).readAsBytes();
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      final rect = face.boundingBox;

      // Increased padding for better context
      final int padding = (rect.width * 0.25).toInt();

      int x = (rect.left.toInt() - padding).clamp(0, image.width);
      int y = (rect.top.toInt() - padding).clamp(0, image.height);
      int w = (rect.width.toInt() + padding * 2).clamp(1, image.width - x);
      int h = (rect.height.toInt() + padding * 2).clamp(1, image.height - y);

      // Optional: Use landmarks for better alignment (if available)
      if (face.landmarks.isNotEmpty) {
        // You can rotate/crop more accurately using eyes/nose
      }

      return img.copyCrop(image, x: x, y: y, width: w, height: h);
    } catch (e) {
      debugPrint('❌ cropFace error: $e');
      return null;
    }
  }
  // ─────────────────────────────────────────────────────────────
  // NEW: Crop Multiple Faces (Very useful for group mode)
  // ─────────────────────────────────────────────────────────────
  Future<List<img.Image>> cropMultipleFaces(
      String imagePath, List<Face> faces) async {
    final List<img.Image> croppedFaces = [];

    for (int i = 0; i < faces.length; i++) {
      final cropped = await cropFace(imagePath, faces[i]);
      if (cropped != null) {
        croppedFaces.add(cropped);
        debugPrint('✅ Cropped face ${i + 1}/${faces.length}');
      }
    }

    return croppedFaces;
  }

  // ─────────────────────────────────────────────────────────────
  // Optional: Save cropped face to temporary file (Useful for embedding)
  // ─────────────────────────────────────────────────────────────
  Future<String?> saveCroppedFace(img.Image croppedImage, String originalPath) async {
    try {
      final tempDir = await Directory.systemTemp.createTemp('face_crop_');
      final fileName = 'crop_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${tempDir.path}/$fileName');

      final jpgBytes = img.encodeJpg(croppedImage, quality: 95);
      await file.writeAsBytes(jpgBytes);

      return file.path;
    } catch (e) {
      debugPrint('❌ saveCroppedFace error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Cleanup
  // ─────────────────────────────────────────────────────────────
  void dispose() {
    _detector.close();
  }
}
