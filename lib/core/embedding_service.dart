import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

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
    if (!_isLoaded) throw Exception('Model not loaded');

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
}