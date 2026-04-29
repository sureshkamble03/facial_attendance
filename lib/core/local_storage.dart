import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorage {
  static const String keyEmbedding = "face_embedding";

  /// Save embedding
  Future<void> saveEmbedding(List<double> embedding) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(embedding);
    print("Saving embedding length: ${embedding.length}");

    await prefs.setString(keyEmbedding, data);
  }

  /// Get embedding
  Future<List<double>?> getEmbedding() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(keyEmbedding);

    if (data == null) return null;

    final List<dynamic> decoded = jsonDecode(data);

    return decoded.map((e) => (e as num).toDouble()).toList();
  }

  /// Optional: clear stored face
  Future<void> clearEmbedding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // await prefs.remove(keyEmbedding);
  }
}