import 'dart:convert';

import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/local_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<bool> verifyFace(String imagePath, FaceEmbeddingService embeddingService,) async {
  final face = await FaceService().detectSingleFace(imagePath);
  if (face == null) return false;

  final cropped = await FaceService().cropFace(imagePath, face);
  if (cropped == null) return false;

  final newEmbedding =
  await embeddingService.getEmbedding(cropped);
  print("New embedding length: ${newEmbedding.length}");

  final saved = await LocalStorage().getEmbedding();
  if (saved == null) return false;
  final prefs = await SharedPreferences.getInstance();
  final jsonString = prefs.getString("face_embedding");

  if (jsonString == null) return false;

  final List<dynamic> decoded = jsonDecode(jsonString);

  final storedEmbedding =
  decoded.map((e) => (e as num).toDouble()).toList();

  print("Stored embedding length: ${storedEmbedding.length}");
  if (storedEmbedding.length != 192) {
    print("❌ Invalid stored embedding → clearing");

    await prefs.remove("embedding");
    return false;
  }
  final similarity =
  embeddingService.cosineSimilarity(newEmbedding, saved);

  return similarity > 0.7;
}