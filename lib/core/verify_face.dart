import 'dart:convert';

import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/local_storage.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Future<bool> verifyFace(String imagePath, FaceEmbeddingService embeddingService,) async {
//   final face = await FaceService().detectSingleFace(imagePath);
//   if (face == null) return false;
//
//   final cropped = await FaceService().cropFace(imagePath, face);
//   if (cropped == null) return false;
//
//   final newEmbedding =
//   await embeddingService.getEmbedding(cropped);
//   print("New embedding length: ${newEmbedding.length}");
//
//   final saved = await LocalStorage().getEmbedding();
//   if (saved == null) return false;
//   final prefs = await SharedPreferences.getInstance();
//   final jsonString = prefs.getString("face_embedding");
//
//   if (jsonString == null) return false;
//
//   final List<dynamic> decoded = jsonDecode(jsonString);
//
//   final storedEmbedding =
//   decoded.map((e) => (e as num).toDouble()).toList();
//
//   print("Stored embedding length: ${storedEmbedding.length}");
//   if (storedEmbedding.length != 192) {
//     print("❌ Invalid stored embedding → clearing");
//
//     await prefs.remove("embedding");
//     return false;
//   }
//   final similarity =
//   embeddingService.cosineSimilarity(newEmbedding, saved);
//
//   return similarity > 0.7;
// }

Future<bool> verifyFace(
    String imagePath,
    FaceEmbeddingService embeddingService,
    ) async {
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
  final newEmbedding = await embeddingService.getEmbedding(cropped);
  debugPrint('✅ New embedding length: ${newEmbedding.length}');

  // Step 4 — load stored embedding
  final prefs = await SharedPreferences.getInstance();
  final jsonString = prefs.getString('face_embedding');

  if (jsonString == null) {
    debugPrint('❌ No stored embedding found');
    return false;
  }

  final List<dynamic> decoded = jsonDecode(jsonString);
  final storedEmbedding = decoded.map((e) => (e as num).toDouble()).toList();

  debugPrint('✅ Stored embedding length: ${storedEmbedding.length}');

  // Step 5 — validate length
  if (storedEmbedding.length != 192) {
    debugPrint('❌ Invalid stored embedding');
    //await prefs.remove('face_embedding');
    return false;
  }

  // Step 6 — compare
  final similarity = embeddingService.cosineSimilarity(
    newEmbedding,
    storedEmbedding,
  );

  debugPrint('📊 Similarity score: $similarity');

  // ── Threshold — adjust based on your environment ──────────────
  const double strictThreshold  = 0.75; // controlled indoor lighting
  const double normalThreshold  = 0.65; // general use — recommended
  const double relaxedThreshold = 0.55; // outdoor / variable lighting

  return similarity > strictThreshold; // ← change this line to switch modes
  // ──────────────────────────────────────────────────────────────
}