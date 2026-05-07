// lib/utils/embedding_test_utility.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../core/embedding_service.dart';
import '../core/face_service.dart';
import '../local_database/app_database.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Result model
// ─────────────────────────────────────────────────────────────────────────────
class EmbeddingFromUrlResult {
  final bool success;
  final String message;
  final List<double>? embedding;
  final int? userId;
  final String? userName;
  final String? imageFile;

  const EmbeddingFromUrlResult({
    required this.success,
    required this.message,
    this.embedding,
    this.userId,
    this.userName,
    this.imageFile,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Utility class
// ─────────────────────────────────────────────────────────────────────────────
class EmbeddingTestUtility {
  final AppDatabase db;
  final FaceEmbeddingService embeddingService;
  final FaceService faceService;

  EmbeddingTestUtility({
    required this.db,
    required this.embeddingService,
    required this.faceService,
  });

  /// Full pipeline:
  /// URL → download jpg → decode → detect face → crop → embed → save to DB
  Future<EmbeddingFromUrlResult> createEmbeddingFromUrl({
    required String imageUrl,
    required int userId,
  }) async {
    File? tempFile;

    try {
      debugPrint('🔄 Starting embedding creation from URL...');
      debugPrint('🌐 URL: $imageUrl');
      debugPrint('👤 userId: $userId');

      // ── Step 1: check user exists in DB ───────────────────────────────────
      final user = await db.getUserById(userId);
      if (user == null) {
        return EmbeddingFromUrlResult(
          success: false,
          message: 'User with id $userId not found in database.',
        );
      }
      debugPrint('✅ User found: ${user.name}');

      // ── Step 2: download image from URL ───────────────────────────────────
      debugPrint('⬇️ Downloading image...');
      final response = await http.get(
        Uri.parse(imageUrl),
        headers: {'Accept': 'image/jpeg, image/png, image/*'},
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Download timeout after 30s'),
      );

      if (response.statusCode != 200) {
        return EmbeddingFromUrlResult(
          success: false,
          message: 'Download failed: HTTP ${response.statusCode}',
        );
      }

      debugPrint('✅ Downloaded ${response.bodyBytes.length} bytes');

      // ── Step 3: save to temp file (FaceService needs a file path) ──────────
      final tempDir = await getTemporaryDirectory();
      final fileName = 'test_face_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(response.bodyBytes);
      debugPrint('✅ Saved to temp: ${tempFile.path}');

      // ── Step 4: verify image is decodable ─────────────────────────────────
      final rawImage = img.decodeImage(response.bodyBytes);
      if (rawImage == null) {
        return EmbeddingFromUrlResult(
          success: false,
          message: 'Could not decode image. Make sure it is a valid JPG/PNG.',
        );
      }
      debugPrint('✅ Image decoded: ${rawImage.width}x${rawImage.height}');

      // ── Step 5: detect face ───────────────────────────────────────────────
      debugPrint('🔍 Detecting face...');
      final face = await faceService.detectSingleFace(tempFile.path);
      if (face == null) {
        return EmbeddingFromUrlResult(
          success: false,
          message: 'No face detected in image.\n'
              'Make sure the image has a clear frontal face.',
        );
      }

      debugPrint('✅ Face detected → '
          'box: ${face.boundingBox.left.toInt()},'
          '${face.boundingBox.top.toInt()} '
          '${face.boundingBox.width.toInt()}x${face.boundingBox.height.toInt()}');

      // ── Step 6: crop face with padding ────────────────────────────────────
      final cropped = await faceService.cropFace(tempFile.path, face);
      if (cropped == null) {
        return EmbeddingFromUrlResult(
          success: false,
          message: 'Face crop failed.',
        );
      }
      debugPrint('✅ Face cropped: ${cropped.width}x${cropped.height}');

      // ── Step 7: generate embedding ────────────────────────────────────────
      debugPrint('🧠 Generating embedding...');
      await embeddingService.loadModel(); // safe — skips if already loaded
      final embedding = await embeddingService.getEmbedding(cropped);
      debugPrint('✅ Embedding generated → length: ${embedding!.length}');

      if (embedding.length != 192) {
        return EmbeddingFromUrlResult(
          success: false,
          message: 'Invalid embedding size: ${embedding.length}. Expected 192.',
        );
      }
      final compressedPath = await compressImageFromUrl(imageUrl);

      if (compressedPath != null) {
        final file = File(compressedPath);
        final bytes = await file.readAsBytes();
      }
      // ── Step 8: save to DB ────────────────────────────────────────────────
      await db.saveUserEmbedding(userId, jsonEncode(embedding),compressedPath??'');
      debugPrint('✅ Embedding saved to DB for user: ${user.name}');

      // ── Step 9: verify save was successful ────────────────────────────────
      final saved = await db.getUserEmbedding(userId);
      if (saved == null) {
        return EmbeddingFromUrlResult(
          success: false,
          message: 'Embedding save verification failed.',
        );
      }

      final verifyDecoded = jsonDecode(saved) as List;
      debugPrint('✅ Verified saved embedding length: ${verifyDecoded.length}');

      return EmbeddingFromUrlResult(
        success: true,
        message: 'Embedding created and saved for ${user.name}',
        embedding: embedding,
        userId: userId,
        userName: user.name,
      );
    } catch (e, stack) {
      debugPrint('❌ createEmbeddingFromUrl error: $e\n$stack');
      return EmbeddingFromUrlResult(
        success: false,
        message: 'Error: $e',
      );
    } finally {
      // Always clean up temp file
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
          debugPrint('🗑️ Temp file deleted');
        }
      } catch (_) {}
    }
  }

  Future<String?> compressImageFromUrl(String imageUrl) async {
    try {
      // 1. Download image
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) return null;

      final bytes = response.bodyBytes;

      // 2. Save original temp file
      final dir = await getApplicationDocumentsDirectory();
      final originalPath = '${dir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final originalFile = File(originalPath);
      await originalFile.writeAsBytes(bytes);

      // 3. Compress image
      final compressedPath = '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        originalFile.path,
        compressedPath,
        quality: 60,
        minWidth: 300,
        minHeight: 300,
      );

      // 4. (Optional) delete original temp file
      await originalFile.delete();

      return compressedFile?.path;
    } catch (e) {
      print("Error: $e");
      return null;
    }
  }

  /// Bulk process — convert multiple users from URL map at once
  /// Map format: { userId: imageUrl }
  Future<void> bulkCreateEmbeddings(
      Map<int, String> userImageMap, {
        void Function(int userId, EmbeddingFromUrlResult result)? onEach,
      }) async {
    debugPrint('🔄 Bulk processing ${userImageMap.length} users...');

    int success = 0;
    int failed = 0;

    for (final entry in userImageMap.entries) {
      final userId   = entry.key;
      final imageUrl = entry.value;

      debugPrint('\n──────────────────────────────────');
      debugPrint('Processing userId: $userId');

      final result = await createEmbeddingFromUrl(
        imageUrl: imageUrl,
        userId: userId,
      );

      if (result.success) {
        success++;
        debugPrint('✅ userId $userId → SUCCESS');
      } else {
        failed++;
        debugPrint('❌ userId $userId → FAILED: ${result.message}');
      }

      onEach?.call(userId, result);

      // Small delay between requests — be nice to the image server
      await Future.delayed(const Duration(milliseconds: 500));
    }

    debugPrint('\n══════════════════════════════════');
    debugPrint('✅ Bulk done → success: $success, failed: $failed');
    debugPrint('══════════════════════════════════');
  }
}