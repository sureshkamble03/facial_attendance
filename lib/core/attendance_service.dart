// lib/core/attendance_service.dart

import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'face_service.dart';
import '../local_database/app_database.dart';
import 'embedding_service.dart';
import 'face_service.dart';

class AttendanceService {
  final AppDatabase db;
  final FaceEmbeddingService embeddingService;

  AttendanceService({required this.db, required this.embeddingService});

  // ── Register face and save to DB ─────────────────────────────────────────

  Future<bool> registerFace(int userId, String imagePath) async {
    final face = await FaceService().detectSingleFace(imagePath);
    if (face == null) {
      debugPrint('❌ No face detected');
      return false;
    }

    final cropped = await FaceService().cropFace(imagePath, face);
    if (cropped == null) {
      debugPrint('❌ Crop failed');
      return false;
    }

    final embedding = await embeddingService.getEmbedding(cropped);
    if (embedding.length != 192) {
      debugPrint('❌ Invalid embedding size');
      return false;
    }

    // Save embedding directly to DB against the user
    await db.saveUserEmbedding(userId, jsonEncode(embedding));
    debugPrint('✅ Face registered for userId: $userId');
    return true;
  }

  // ── Verify face against DB embedding ─────────────────────────────────────

  Future<bool> verifyFaceFromDb(int userId, String imagePath) async {
    // Load stored embedding from DB
    final embeddingJson = await db.getUserEmbedding(userId);
    if (embeddingJson == null) {
      debugPrint('❌ No embedding found for userId: $userId');
      return false;
    }

    final stored = (jsonDecode(embeddingJson) as List)
        .map((e) => (e as num).toDouble())
        .toList();

    if (stored.length != 192) {
      debugPrint('❌ Invalid stored embedding');
      return false;
    }

    // Get new embedding from camera image
    final face = await FaceService().detectSingleFace(imagePath);
    if (face == null) return false;

    final cropped = await FaceService().cropFace(imagePath, face);
    if (cropped == null) return false;

    final newEmbedding = await embeddingService.getEmbedding(cropped);
    final similarity = embeddingService.cosineSimilarity(newEmbedding, stored);

    debugPrint('📊 Similarity: $similarity');

    // Log every scan attempt
    await db.insertFaceLog(FaceLogsCompanion.insert(
      userId: userId,
      isMatch: similarity > 0.65,
      similarity: similarity,
    ));

    return similarity > 0.65;
  }

  // ── Mark attendance via face ──────────────────────────────────────────────

  Future<String> markAttendanceByFace({
    required int userId,
    required int sessionId,
    required String imagePath,
    required String role,
  }) async {
    // Check already marked
    final alreadyMarked = await db.isAlreadyMarked(sessionId, userId);
    if (alreadyMarked) return 'already_marked';

    // Verify face
    final verified = await verifyFaceFromDb(userId, imagePath);
    if (!verified) return 'face_mismatch';

    final now = TimeOfDay.now();
    final markedAt =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:00';

    // Mark attendance
    await db.markAttendance(
      AttendanceRecordsCompanion.insert(
        sessionId: sessionId,
        userId: userId,
        role: role,
        markedAt: markedAt,
        method: const Value('face'),
        status: const Value('present'),
      ),
    );

    debugPrint('✅ Attendance marked for userId: $userId');
    return 'success';
  }
}