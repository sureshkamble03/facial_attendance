import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/*
class FaceEmbeddingService {
  late Interpreter _interpreter;
  bool _isLoaded = false;

  Future<void> loadModel() async {
    _interpreter = await Interpreter.fromAsset('assets/model/mobilefacenet.tflite');
    _isLoaded = true;
  }

  /// Convert image → embedding vector
  // Future<List<double>> getEmbedding(img.Image image) async {
  //   if (!_isLoaded) {
  //     throw Exception("Model not loaded");
  //   }
  //   final resized = img.copyResize(image, width: 112, height: 112);
  //
  //   final input = Float32List(1 * 112 * 112 * 3);
  //
  //   int index = 0;
  //   for (int y = 0; y < 112; y++) {
  //     for (int x = 0; x < 112; x++) {
  //       final pixel = resized.getPixel(x, y);
  //
  //       input[index++] = (pixel.r - 128) / 128;
  //       input[index++] = (pixel.g - 128) / 128;
  //       input[index++] = (pixel.b - 128) / 128;
  //     }
  //   }
  //
  //   final output = List.generate(1, (_) => List.filled(192, 0.0));
  //
  //   _interpreter.run(
  //     input.reshape([1, 112, 112, 3]),
  //     output,
  //   );
  //
  //   return output[0];
  // }
  Future<List<double>> getEmbedding(img.Image image) async {
    if (!_isLoaded) throw loadModel();

    final resized = img.copyResize(image, width: 112, height: 112);

    final input = Float32List(1 * 112 * 112 * 3);

    int index = 0;
    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        final pixel = resized.getPixel(x, y);

        input[index++] = (pixel.r - 128) / 128;
        input[index++] = (pixel.g - 128) / 128;
        input[index++] = (pixel.b - 128) / 128;
      }
    }

    final output = List.generate(1, (_) => List.filled(192, 0.0));
    _interpreter.run(input.reshape([1, 112, 112, 3]), output);

    // ✅ L2 normalize the output vector
    return _l2Normalize(output[0]);
  }

  List<double> _l2Normalize(List<double> vector) {
    final norm = sqrt(vector.fold(0.0, (sum, v) => sum + v * v));
    if (norm == 0) return vector;
    return vector.map((v) => v / norm).toList();
  }

  /// Cosine similarity
  double cosineSimilarity(List<double> vec1, List<double> vec2) {
    if (vec1.length != vec2.length || vec1.isEmpty) {
      throw Exception('Embedding size mismatch: ${vec1.length} vs ${vec2.length}');
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < vec1.length; i++) {
      dotProduct += vec1[i] * vec2[i];
      normA += vec1[i] * vec1[i];
      normB += vec2[i] * vec2[i];
    }

    if (normA == 0 || normB == 0) return 0.0;

    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

 */
/* Future<void> processGroupPhotoForAttendance(File groupPhoto) async {
    final inputImage = InputImage.fromFile(groupPhoto);

    // Step 1: Detect all faces
    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: false,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    final List<Face> faces = await faceDetector.processImage(inputImage);
    faceDetector.close();

    if (faces.isEmpty) {
      print("No faces detected");
      return;
    }

    final recognitionService = FaceEmbeddingService();
    await recognitionService.loadModel();

    List<AttendanceRecord> markedRecords = [];

    for (Face face in faces) {
      final Rect box = face.boundingBox;

      // Step 2: Crop face from original image
      final croppedImage = await cropFaceFromImage(groupPhoto, box);

      // Step 3: Get embedding
      final embedding = await recognitionService.getEmbedding(croppedImage as img.Image);

      // Step 4: Find best match from registered users
      final match = await findBestMatch(embedding);

      if (match != null && match.distance < 0.6) {  // Threshold tuning needed
        // Mark attendance
        await markAttendance(
          userId: match.userId,
          method: 'face',
          similarityScore: 1 - match.distance,
        );

        markedRecords.add(...);
      }
    }

    print("${markedRecords.length} users marked present from group photo");
  }

  Future<MatchResult?> findBestMatch(List<double> newEmbedding) async {
    final db = context.read<AppDatabase>(); // or inject your database

    final allUsers = await db.usersDao.getAllUsersWithEmbeddings();

    double minDistance = double.infinity;
    User? bestUser;

    for (var user in allUsers) {
      final distance = euclideanDistance(newEmbedding, user.embedding);
      if (distance < minDistance) {
        minDistance = distance;
        bestUser = user;
      }
    }

    return minDistance < threshold ? MatchResult(bestUser!, minDistance) : null;
  }*//*
}*/

class FaceEmbeddingService {
  Interpreter? _interpreter;
  bool _isLoaded = false;

  Future<void> loadModel() async {
    if (_isLoaded) return;

    try {
      final options = InterpreterOptions()
        ..threads = 4
        ..useNnApiForAndroid = true;

      _interpreter = await Interpreter.fromAsset(
        'assets/model/mobilefacenet.tflite',
        options: options,
      );

      _isLoaded = true;
      debugPrint('✅ FaceEmbeddingService: MobileFaceNet model loaded successfully');
    } catch (e) {
      debugPrint('❌ Failed to load model: $e');
      rethrow;
    }
  }

  /// Generate embedding from cropped face image
  Future<List<double>> getEmbedding(img.Image image) async {
    if (!_isLoaded) await loadModel();

    // ✅ Step 1: Always resize to exactly 112x112
    final resized = img.copyResize(
      image,
      width: 112,
      height: 112,
      interpolation: img.Interpolation.linear, // ✅ consistent interpolation
    );

    // ✅ Step 2: Normalize using EXACTLY the same formula every time
    // MobileFaceNet expects: (pixel - 127.5) / 128.0
    // NOT (pixel - 128) / 128 — tiny difference, big impact
    final input = Float32List(1 * 112 * 112 * 3);
    int index = 0;

    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        final pixel = resized.getPixel(x, y);
        input[index++] = (pixel.r.toDouble() - 127.5) / 128.0; // ✅ 127.5 not 128
        input[index++] = (pixel.g.toDouble() - 127.5) / 128.0;
        input[index++] = (pixel.b.toDouble() - 127.5) / 128.0;
      }
    }

    final output = List.generate(1, (_) => List.filled(192, 0.0));
    _interpreter?.run(input.reshape([1, 112, 112, 3]), output);

    // ✅ Step 3: ALWAYS L2 normalize output
    return _l2Normalize(output[0]);
  }

  /// L2 Normalization
  List<double> _l2Normalize(List<double> vector) {
    double norm = 0.0;
    for (final v in vector) norm += v * v;
    norm = sqrt(norm);
    if (norm < 1e-10) return vector; // ✅ safer zero check
    return vector.map((v) => v / norm).toList();
  }

  /// Cosine Similarity (Best for face recognition)
  double cosineSimilarity(List<double> vec1, List<double> vec2) {
    if (vec1.length != vec2.length || vec1.isEmpty) {
      debugPrint('⚠️ Embedding size mismatch');
      return 0.0;
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < vec1.length; i++) {
      dotProduct += vec1[i] * vec2[i];
      normA += vec1[i] * vec1[i];
      normB += vec2[i] * vec2[i];
    }

    if (normA == 0 || normB == 0) return 0.0;

    final cosine = dotProduct / (sqrt(normA) * sqrt(normB));

    // Convert from [-1, 1] to [0, 1] range for easier threshold handling
    return (cosine + 1.0) / 2.0;
  }

  /// Optional: Get embedding directly from file path
  Future<List<double>?> getEmbeddingFromPath(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      return await getEmbedding(image);
    } catch (e) {
      debugPrint('❌ getEmbeddingFromPath error: $e');
      return null;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
    debugPrint('🗑️ FaceEmbeddingService disposed');
  }
}