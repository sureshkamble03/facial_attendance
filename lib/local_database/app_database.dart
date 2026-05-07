import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:facial_attendance/core/user_with_embedding.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Table;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/embedding_service.dart';
import '../core/face_service.dart';
import 'drift_tables/drift_tables.dart';

part 'app_database.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Result model returned after a face scan attendance attempt
// ─────────────────────────────────────────────────────────────────────────────
class FaceScanAttendanceResult {
  final bool success;
  final String message;

  // Populated on success
  final User? user;
  final AttendanceRecord? record;

  // Similarity score for logging/debugging
  final double similarity;

  const FaceScanAttendanceResult({
    required this.success,
    required this.message,
    this.user,
    this.record,
    this.similarity = 0.0,
  });

  @override
  String toString() =>
      'FaceScanAttendanceResult(success: $success, message: $message, '
      'user: ${user?.name}, similarity: $similarity)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Database
// ─────────────────────────────────────────────────────────────────────────────
@DriftDatabase(tables: [
  Users,
  Subjects,
  Enrollments,
  AttendanceSessions,
  AttendanceRecords,
  FaceLogs,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // ── Users ─────────────────────────────────────────────────────────────────

  Future<int> insertUser(UsersCompanion user) => into(users).insert(user);

  Future<void> deleteUser(int userId) async {
    final count = await (delete(users)
      ..where((u) => u.id.equals(userId)))
        .go();

    debugPrint('🗑️ Deleted $count user(s) with ID: $userId');
  }

  Future<User?> getUserByEmail(String email) =>
      (select(users)..where((u) => u.email.equals(email))).getSingleOrNull();

  Future<User?> getUserById(int id) =>
      (select(users)..where((u) => u.id.equals(id))).getSingleOrNull();

  Future<List<User>> getAllStudents() =>
      (select(users)..where((u) => u.role.equals('student'))).get();

  Future<List<User>> getAllTeachers() =>
      (select(users)..where((u) => u.role.equals('teacher'))).get();

  Future<List<User>> getUsersPaginated({
    required int limit,
    required int offset,
  }) =>
      (select(users)
            ..limit(limit, offset: offset)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Future<void> saveUserEmbedding(int userId, String embeddingJson,String imagePath) async {
    await (update(users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        faceImagePath: Value(imagePath),
        embedding: Value(embeddingJson),
        isFaceRegistered: const Value(true),
      ),
    );
  }

  Future<String?> getUserEmbedding(int userId) async {
    final user = await getUserById(userId);
    return user?.embedding;
  }

  // ── Face matching ─────────────────────────────────────────────────────────

  /// Scans ALL users with registered embeddings and returns the best match.
  /// Only returns a user if similarity exceeds [threshold].
  /// Also logs the similarity score for every candidate for debugging.
  Future<({User? user, double similarity})> findBestMatch(
    List<double> inputEmbedding,
    FaceEmbeddingService embeddingService, {
    double threshold = 0.75,
  }) async {
    // Only load users who have registered their face — saves loop iterations
    final registeredUsers = await (select(users)
          ..where((u) => u.isFaceRegistered.equals(true)))
        .get();

    if (registeredUsers.isEmpty) {
      debugPrint('⚠️ No users with registered faces found');
      return (user: null, similarity: 0.0);
    }

    double maxSimilarity = 0.0;
    User? matchedUser;

    for (final user in registeredUsers) {
      if (user.embedding == null) continue;

      // Safe JSON decode — skip corrupted entries
      List<double> storedEmbedding;
      try {
        storedEmbedding = (jsonDecode(user.embedding!) as List)
            .map((e) => (e as num).toDouble())
            .toList();
      } catch (e) {
        debugPrint('⚠️ Skipping user ${user.id} — bad embedding JSON: $e');
        continue;
      }

      if (storedEmbedding.length != 192) {
        debugPrint('⚠️ Skipping user ${user.id} — invalid length ${storedEmbedding.length}');
        continue;
      }

      final similarity = embeddingService.cosineSimilarity(
        inputEmbedding,
        storedEmbedding,
      );

      debugPrint('👤 ${user.name} (id:${user.id}) → similarity: ${similarity.toStringAsFixed(4)}');

      if (similarity > maxSimilarity) {
        maxSimilarity = similarity;
        matchedUser = user;
      }
    }

    if (maxSimilarity >= threshold) {
      debugPrint('✅ Best match: ${matchedUser?.name} → $maxSimilarity');
      return (user: matchedUser, similarity: maxSimilarity);
    }

    debugPrint('❌ No match above threshold ($threshold). Best: $maxSimilarity');
    return (user: null, similarity: maxSimilarity);
  }

  // ── CORE: Scan face → identify user → mark attendance ────────────────────

  /// Full pipeline:
  /// 1. Get new embedding from [imagePath]
  /// 2. Compare against ALL registered users in DB
  /// 3. If matched → check already marked → insert attendance record
  /// 4. Return [FaceScanAttendanceResult] with user details + status
  Future<FaceScanAttendanceResult> markAttendanceByFaceScan({
    required String imagePath,
    required FaceEmbeddingService embeddingService,
    required FaceService faceService,
    double threshold = 0.75,
  }) async {
    try {
      debugPrint('🔄 Starting face scan attendance...');

      // ── Step 1: Detect face ──────────────────────────────────────────────
      final face = await faceService.detectSingleFace(imagePath);
      if (face == null) {
        debugPrint('❌ No face detected in image');
        return const FaceScanAttendanceResult(
          success: false,
          message: 'No face detected. Please try again.',
        );
      }

      // ── Step 2: Crop face ────────────────────────────────────────────────
      final cropped = await faceService.cropFace(imagePath, face);
      if (cropped == null) {
        debugPrint('❌ Face crop failed');
        return const FaceScanAttendanceResult(
          success: false,
          message: 'Face crop failed. Please try again.',
        );
      }

      // ── Step 3: Get embedding ────────────────────────────────────────────
      final newEmbedding = await embeddingService.getEmbedding(cropped);
      debugPrint('✅ New embedding length: ${newEmbedding!.length}');

      if (newEmbedding.length != 192) {
        return const FaceScanAttendanceResult(
          success: false,
          message: 'Invalid face scan. Please try again.',
        );
      }

      // ── Step 4: Find matching user ───────────────────────────────────────
      final matchResult = await findBestMatch(
        newEmbedding,
        embeddingService,
        threshold: threshold,
      );

      final matchedUser = matchResult.user;
      final similarity = matchResult.similarity;

      if (matchedUser == null) {
        debugPrint('❌ No matching user found (best similarity: $similarity)');
        return FaceScanAttendanceResult(
          success: false,
          message: 'Face not recognised.\n'
              'Score: ${(similarity * 100).toStringAsFixed(1)}%',
          similarity: similarity,
        );
      }

      debugPrint('✅ Matched user: ${matchedUser.name} (id: ${matchedUser.id})');

      // ── Step 5: Check if already marked today (Optional but recommended) ─
      final alreadyMarkedToday = await isAlreadyMarked(matchedUser.id);
      if (alreadyMarkedToday) {
        debugPrint('ℹ️ Attendance already marked today for: ${matchedUser.name}');
        return FaceScanAttendanceResult(
          success: false,
          message: 'Attendance already marked today for ${matchedUser.name}.',
          user: matchedUser,
          similarity: similarity,
        );
      }

      // ── Step 6: Mark Attendance ──────────────────────────────────────────
      final now = DateTime.now();
      final markedAt = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      final recordId = await markAttendance(
        AttendanceRecordsCompanion.insert(
          // sessionId removed
          userId: matchedUser.id,
          role: matchedUser.role,
          markedAt: markedAt,
          markedDate: now,           // Important: Add date
          method: const Value('face'),
          status: const Value('present'),
          similarityScore: Value(similarity),
        ),
      );

      // ── Step 7: Log the face scan ────────────────────────────────────────
      await insertFaceLog(
        FaceLogsCompanion.insert(
          userId: matchedUser.id,
          // sessionId removed
          isMatch: true,
          similarity: similarity,
          imagePath: Value(imagePath),
          scannedAt: Value(now),
        ),
      );

      // ── Step 8: Fetch inserted record ────────────────────────────────────
      final record = await (select(attendanceRecords)
        ..where((r) => r.id.equals(recordId)))
          .getSingleOrNull();

      debugPrint('✅ Attendance marked successfully → ${matchedUser.name} at $markedAt');

      return FaceScanAttendanceResult(
        success: true,
        message: 'Attendance marked for ${matchedUser.name}!',
        user: matchedUser,
        record: record,
        similarity: similarity,
      );
    } catch (e, stack) {
      debugPrint('❌ markAttendanceByFaceScan error: $e\n$stack');
      return FaceScanAttendanceResult(
        success: false,
        message: 'Unexpected error occurred. Please try again.',
      );
    }
  }

  // ====================== GROUP ATTENDANCE ======================

  // Future<List<FaceScanAttendanceResult>> markGroupAttendanceByFaceScan({
  //   required String imagePath,
  //   required FaceEmbeddingService embeddingService,
  //   required FaceService faceService,
  //   double threshold = 0.75,
  // }) async {
  //   final results = <FaceScanAttendanceResult>[];
  //
  //   try {
  //     debugPrint('🔄 Starting Group Attendance Scan...');
  //
  //     // Step 1: Detect all faces in the image
  //     final faces = await faceService.detectMultipleFaces(imagePath);
  //
  //     if (faces.isEmpty) {
  //       return [
  //         const FaceScanAttendanceResult(
  //           success: false,
  //           message: 'No faces detected in the image',
  //         )
  //       ];
  //     }
  //
  //     debugPrint('👥 Detected ${faces.length} faces');
  //
  //     // Step 2: Process each face
  //     for (int i = 0; i < faces.length; i++) {
  //       final face = faces[i];
  //       debugPrint('Processing face ${i + 1}/${faces.length}');
  //
  //       try {
  //         // Crop face
  //         final croppedPath = await faceService.cropFace(imagePath, face);
  //         if (croppedPath == null) {
  //           results.add(FaceScanAttendanceResult(
  //             success: false,
  //             message: 'Failed to crop face ${i + 1}',
  //           ));
  //           continue;
  //         }
  //
  //         // Get embedding
  //         final embedding = await embeddingService.getEmbedding(croppedPath);
  //         if (embedding.length != 192) {
  //           results.add(const FaceScanAttendanceResult(
  //             success: false,
  //             message: 'Invalid embedding',
  //           ));
  //           continue;
  //         }
  //
  //         // Find best match
  //         final matchResult = await findBestMatch(
  //           embedding,
  //           embeddingService,
  //           threshold: threshold,
  //         );
  //
  //         final matchedUser = matchResult.user;
  //         final similarity = matchResult.similarity;
  //
  //         if (matchedUser == null) {
  //           results.add(FaceScanAttendanceResult(
  //             success: false,
  //             message: 'Face not recognized',
  //             similarity: similarity,
  //           ));
  //           continue;
  //         }
  //
  //         // Check if already marked today
  //         final alreadyMarked = await isAlreadyMarked(matchedUser.id);
  //         if (alreadyMarked) {
  //           results.add(FaceScanAttendanceResult(
  //             success: false,
  //             message: 'Already marked today',
  //             user: matchedUser,
  //             similarity: similarity,
  //           ));
  //           continue;
  //         }
  //
  //         // Mark Attendance
  //         final now = DateTime.now();
  //         final normalizedDate = DateTime(now.year, now.month, now.day);
  //         final markedAtTime = '${now.hour.toString().padLeft(2, '0')}:'
  //             '${now.minute.toString().padLeft(2, '0')}:'
  //             '${now.second.toString().padLeft(2, '0')}';
  //
  //         final recordId = await markAttendance(
  //           AttendanceRecordsCompanion.insert(
  //             userId: matchedUser.id,
  //             role: matchedUser.role,
  //             markedAt: markedAtTime,
  //             markedDate: normalizedDate,
  //             method: const Value('face_group'),
  //             status: const Value('present'),
  //             similarityScore: Value(similarity),
  //           ),
  //         );
  //
  //         // Log face scan
  //         await insertFaceLog(
  //           FaceLogsCompanion.insert(
  //             userId: matchedUser.id,
  //             isMatch: true,
  //             similarity: similarity,
  //             imagePath: Value(imagePath),
  //             scannedAt: Value(now),
  //           ),
  //         );
  //
  //         // Fetch record
  //         final record = await (select(attendanceRecords)
  //           ..where((r) => r.id.equals(recordId)))
  //             .getSingleOrNull();
  //
  //         results.add(FaceScanAttendanceResult(
  //           success: true,
  //           message: 'Attendance marked',
  //           user: matchedUser,
  //           record: record,
  //           similarity: similarity,
  //         ));
  //
  //         debugPrint('✅ Marked: ${matchedUser.name}');
  //       } catch (e) {
  //         debugPrint('❌ Error processing face ${i + 1}: $e');
  //         results.add(FaceScanAttendanceResult(
  //           success: false,
  //           message: 'Error processing face',
  //         ));
  //       }
  //     }
  //
  //     return results;
  //   } catch (e, stack) {
  //     debugPrint('❌ Group attendance error: $e\n$stack');
  //     return [
  //       FaceScanAttendanceResult(
  //         success: false,
  //         message: 'Group attendance failed: $e',
  //       )
  //     ];
  //   }
  // }

// ==================== MAIN METHOD ====================
  // ── app_database.dart additions ──────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Mark multiple attendance by face scan
// ─────────────────────────────────────────────────────────────────────────────
// ====================== GROUP ATTENDANCE ======================

  Future<List<FaceScanAttendanceResult>> markMultipleAttendanceByFaceScan({
    required String imagePath,
    required FaceEmbeddingService embeddingService,
    required FaceService faceService,
    double threshold = 0.75,
  }) async {
    final results = <FaceScanAttendanceResult>[];

    try {
      debugPrint('🔄 Starting Group Attendance Scan...');

      // Step 1: Detect all faces in the image
      final faces = await faceService.detectFaces(imagePath);

      if (faces.isEmpty) {
        return [
          const FaceScanAttendanceResult(
            success: false,
            message: 'No faces detected in the image',
          )
        ];
      }

      debugPrint('👥 Detected ${faces.length} faces');

      // Step 2: Process each face
      for (int i = 0; i < faces.length; i++) {
        final face = faces[i];
        debugPrint('Processing face ${i + 1}/${faces.length}');

        try {
          // Crop face
          final croppedPath = await faceService.cropFace(imagePath, face);
          if (croppedPath == null) {
            results.add(FaceScanAttendanceResult(
              success: false,
              message: 'Failed to crop face ${i + 1}',
            ));
            continue;
          }

          // Get embedding
          final embedding = await embeddingService.getEmbedding(croppedPath);
          if (embedding.length != 192) {
            results.add(const FaceScanAttendanceResult(
              success: false,
              message: 'Invalid embedding',
            ));
            continue;
          }

          // Find best match
          final matchResult = await findBestMatch(
            embedding,
            embeddingService,
            threshold: threshold,
          );

          final matchedUser = matchResult.user;
          final similarity = matchResult.similarity;

          if (matchedUser == null) {
            results.add(FaceScanAttendanceResult(
              success: false,
              message: 'Face not recognized',
              similarity: similarity,
            ));
            continue;
          }

          // Check if already marked today
          final alreadyMarked = await isAlreadyMarked(matchedUser.id);
          if (alreadyMarked) {
            results.add(FaceScanAttendanceResult(
              success: false,
              message: 'Already marked today',
              user: matchedUser,
              similarity: similarity,
            ));
            continue;
          }

          // Mark Attendance
          final now = DateTime.now();
          final normalizedDate = DateTime(now.year, now.month, now.day);
          final markedAtTime = '${now.hour.toString().padLeft(2, '0')}:'
              '${now.minute.toString().padLeft(2, '0')}:'
              '${now.second.toString().padLeft(2, '0')}';

          final recordId = await markAttendance(
            AttendanceRecordsCompanion.insert(
              userId: matchedUser.id,
              role: matchedUser.role,
              markedAt: markedAtTime,
              markedDate: normalizedDate,
              method: const Value('face_group'),
              status: const Value('present'),
              similarityScore: Value(similarity),
            ),
          );

          // Log face scan
          await insertFaceLog(
            FaceLogsCompanion.insert(
              userId: matchedUser.id,
              isMatch: true,
              similarity: similarity,
              imagePath: Value(imagePath),
              scannedAt: Value(now),
            ),
          );

          // Fetch record
          final record = await (select(attendanceRecords)
            ..where((r) => r.id.equals(recordId)))
              .getSingleOrNull();

          results.add(FaceScanAttendanceResult(
            success: true,
            message: 'Attendance marked',
            user: matchedUser,
            record: record,
            similarity: similarity,
          ));

          debugPrint('✅ Marked: ${matchedUser.name}');
        } catch (e) {
          debugPrint('❌ Error processing face ${i + 1}: $e');
          results.add(FaceScanAttendanceResult(
            success: false,
            message: 'Error processing face',
          ));
        }
      }

      return results;
    } catch (e, stack) {
      debugPrint('❌ Group attendance error: $e\n$stack');
      return [
        FaceScanAttendanceResult(
          success: false,
          message: 'Group attendance failed: $e',
        )
      ];
    }
  }

// ─────────────────────────────────────────────────────────────────────────────
// Process single face — crop → embed → match against all users
// ─────────────────────────────────────────────────────────────────────────────
  Future<FaceScanAttendanceResult> _processSingleFace({
    required String imagePath,
    required Face face,
    required int faceIndex,
    required FaceService faceService,
    required FaceEmbeddingService embeddingService,
    required List<UserWithEmbedding> allUsers,
    required Set<int> matchedUserIds, // ✅ prevents same user matching twice
  }) async {
    try {
      // ── Step 1: crop face with padding ──────────────────────────────────────
      debugPrint('   ├─ Cropping face ${faceIndex + 1}...');
      final cropped = await faceService.cropFace(imagePath, face);
      if (cropped == null) {
        debugPrint('   ❌ Crop failed');
        return const FaceScanAttendanceResult(
          success: false,
          similarity: 0.0,
          message: 'Failed to crop face',
        );
      }
      debugPrint('   ├─ Cropped size: ${cropped.width}x${cropped.height}');

      // ── Step 2: generate embedding directly from cropped image ──────────────
      // ✅ No re-detection — pass img.Image directly to getEmbedding()
      debugPrint('   ├─ Generating embedding...');
      final embedding = await embeddingService.getEmbedding(cropped);

      if (embedding.length != 192) {
        debugPrint('   ❌ Invalid embedding length: ${embedding.length}');
        return const FaceScanAttendanceResult(
          success: false,
          similarity: 0.0,
          message: 'Failed to generate embedding',
        );
      }

      // Debug: check embedding norm — should be ~1.0 if L2 normalized
      final norm = sqrt(embedding.fold(0.0, (s, v) => s + v * v));
      debugPrint('   ├─ Embedding norm: ${norm.toStringAsFixed(4)} '
          '${(norm - 1.0).abs() < 0.05 ? "✅ normalized" : "⚠️ NOT normalized"}');

      // ── Step 3: match against all registered users ───────────────────────────
      debugPrint('   ├─ Matching against ${allUsers.length} users...');

      double bestSimilarity = 0.0;
      User? matchedUser;
      String bestUserName = 'none';

      for (final userWithEmb in allUsers) {
        // Skip already matched users in this group scan
        if (matchedUserIds.contains(userWithEmb.user.id)) {
          debugPrint('   │  ⏭️ Skipping ${userWithEmb.user.name} (already matched)');
          continue;
        }

        final stored = userWithEmb.embedding;

        // ✅ Safe cast — handles both int and double in JSON
        if (stored == null || stored.length != 192) {
          continue;
        }

        final similarity = embeddingService.cosineSimilarity(
          embedding,
          stored,
        );

        debugPrint('   │  👤 ${userWithEmb.user.name} → '
            '${similarity.toStringAsFixed(4)}');

        if (similarity > bestSimilarity) {
          bestSimilarity = similarity;
          matchedUser    = userWithEmb.user;
          bestUserName   = userWithEmb.user.name;
        }
      }

      debugPrint('   └─ Best match: $bestUserName → '
          '${bestSimilarity.toStringAsFixed(4)}');

      // ── Step 4: threshold check ──────────────────────────────────────────────
      const double threshold = 0.70; // ✅ slightly lower for group/angle variation

      if (bestSimilarity >= threshold && matchedUser != null) {
        debugPrint('   ✅ MATCH → ${matchedUser.name} '
            '(${(bestSimilarity * 100).toStringAsFixed(1)}%)');
        return FaceScanAttendanceResult(
          success: true,
          user: matchedUser,
          similarity: bestSimilarity,
          message: 'Attendance marked',
        );
      }

      debugPrint('   ❌ No match | best: '
          '${(bestSimilarity * 100).toStringAsFixed(1)}% < '
          '${(threshold * 100).toStringAsFixed(0)}%');
      return FaceScanAttendanceResult(
        success: false,
        similarity: bestSimilarity,
        message: 'Face not recognised '
            '(${(bestSimilarity * 100).toStringAsFixed(1)}%)',
      );
    } catch (e, stack) {
      debugPrint('   ❌ _processSingleFace error: $e\n$stack');
      return FaceScanAttendanceResult(
        success: false,
        similarity: 0.0,
        message: 'Processing error: $e',
      );
    }
  }

  Future<List<UserWithEmbedding>> getAllUsersWithEmbeddings() async {
    try {
      final usersList = await select(users).get();

      final List<UserWithEmbedding> result = [];

      for (final user in usersList) {
        final embedding = _parseEmbedding(user.embedding);
        result.add(UserWithEmbedding(
          user: user,
          embedding: embedding,
        ));
      }

      debugPrint('✅ Loaded ${result.length} users with embeddings');
      return result;
    } catch (e) {
      debugPrint('❌ getAllUsersWithEmbeddings error: $e');
      return [];
    }
  }

  List<double>? _parseEmbedding(String? embeddingJson) {
    if (embeddingJson == null || embeddingJson.isEmpty) return null;

    try {
      final list = embeddingJson
          .replaceAll('[', '')
          .replaceAll(']', '')
          .split(',')
          .map((e) => double.tryParse(e.trim()) ?? 0.0)
          .toList();

      return list;
    } catch (e) {
      debugPrint('❌ Failed to parse embedding: $e');
      return null;
    }
  }
  // ── Subjects ──────────────────────────────────────────────────────────────

  Future<int> insertSubject(SubjectsCompanion subject) =>
      into(subjects).insert(subject);

  Future<List<Subject>> getAllSubjects() => select(subjects).get();

  Future<List<Subject>> getSubjectsByTeacher(int teacherId) =>
      (select(subjects)..where((s) => s.teacherId.equals(teacherId))).get();

  // ── Enrollments ───────────────────────────────────────────────────────────

  Future<int> enrollStudent(int studentId, int subjectId) =>
      into(enrollments).insert(
        EnrollmentsCompanion.insert(
          studentId: studentId,
          subjectId: subjectId,
        ),
      );

  Future<List<User>> getStudentsInSubject(int subjectId) async {
    final query = select(enrollments).join([
      innerJoin(users, users.id.equalsExp(enrollments.studentId)),
    ])..where(enrollments.subjectId.equals(subjectId));

    final rows = await query.get();
    return rows.map((r) => r.readTable(users)).toList();
  }

  // ── Attendance Records ────────────────────────────────────────────────────

  Future<int> markAttendance(AttendanceRecordsCompanion record) =>
      into(attendanceRecords).insert(
        record,
        mode: InsertMode.insertOrIgnore,
      );

  Future<bool> isAlreadyMarked(int userId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final count = await (select(attendanceRecords)
      ..where((r) =>
      r.userId.equals(userId) &
      r.markedDate.equals(startOfDay)))
        .get();

    return count.isNotEmpty;
  }

  // Future<List<AttendanceRecord>> getSessionAttendance(int sessionId) =>
  //     (select(attendanceRecords)
  //           ..where((r) => r.sessionId.equals(sessionId)))
  //         .get();
  //
  // /// Returns attendance with full user details joined
  // Future<List<({User user, AttendanceRecord record})>>
  //     getSessionAttendanceWithUsers(int sessionId) async {
  //   final query = select(attendanceRecords).join([
  //     innerJoin(users, users.id.equalsExp(attendanceRecords.userId)),
  //   ])..where(attendanceRecords.sessionId.equals(sessionId));

  //   final rows = await query.get();
  //   return rows
  //       .map((r) => (
  //             user: r.readTable(users),
  //             record: r.readTable(attendanceRecords),
  //           ))
  //       .toList();
  // }

  Future<List<AttendanceRecord>> getStudentAttendance(
    int userId,
    int subjectId,
  ) async {
    // final sessions = await getSessionsBySubject(subjectId);
    // final sessionIds = sessions.map((s) => s.id).toList();

    return (select(attendanceRecords)
          ..where((r) =>
              r.userId.equals(userId)))
        .get();
  }

  // ── Face Logs ─────────────────────────────────────────────────────────────

  Future<int> insertFaceLog(FaceLogsCompanion log) =>
      into(faceLogs).insert(log);

  Future<List<FaceLog>> getFaceLogsByUser(int userId) =>
      (select(faceLogs)..where((l) => l.userId.equals(userId))).get();
}

// ── DB connection ─────────────────────────────────────────────────────────────

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'frs.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
