import 'dart:convert';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/local_storage.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../local_database/app_database.dart';



Future<bool> verifyFace(
    String imagePath,
    FaceEmbeddingService embeddingService,
    ) async {
  try {
    // Step 1 — detect face
    final face = await FaceService().detectSingleFace(imagePath);
    if (face == null) {
      debugPrint('❌ No face detected');
      return false;
    }

    // Step 2 — crop face
    final cropped = await FaceService().cropFace(imagePath, face);
    if (cropped == null) {
      debugPrint('❌ Face crop failed');
      return false;
    }

    // Step 3 — get new embedding
    // ✅ ensureLoaded() inside getEmbedding — never throws "Model not loaded"
    final newEmbedding = await embeddingService.getEmbedding(cropped);
    debugPrint('✅ New embedding length: ${newEmbedding!.length}');

    // Step 4 — load stored embedding from ONE source only
    // ✅ Removed duplicate SharedPreferences read — LocalStorage handles it
    final storedEmbedding = await LocalStorage().getEmbedding();
    if (storedEmbedding == null) {
      debugPrint('❌ No valid embedding in storage');
      return false;
    }

    // Step 5 — compare
    final similarity = embeddingService.cosineSimilarity(
      newEmbedding,
      storedEmbedding,
    );
    debugPrint('📊 Similarity score: $similarity');

    const double normalThreshold = 0.65;
    return similarity > normalThreshold;

  } catch (e) {
    // ✅ Catch any unexpected error — never crash the attendance screen
    debugPrint('❌ verifyFace error: $e');
    return false;
  }
}