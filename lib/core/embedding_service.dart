import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'embeding_encryption_service.dart';

class FaceEmbeddingService {
  final EmbeddingEncryptionService _encryption = EmbeddingEncryptionService();
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

  // When saving embedding to database
  Future<String> getEncryptedEmbedding(List<double> rawEmbedding) async {
    return await _encryption.encryptEmbedding(rawEmbedding);
  }

  // When loading for comparison
  Future<List<double>> getDecryptedEmbedding(String encryptedEmbedding) async {
    return await _encryption.decryptEmbedding(encryptedEmbedding);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
    debugPrint('🗑️ FaceEmbeddingService disposed');
  }
}