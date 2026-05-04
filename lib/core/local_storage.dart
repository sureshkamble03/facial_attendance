import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorage {
  static const String keyEmbedding = "face_embedding";

  /// Save embedding
  Future<void> saveEmbedding(List<double> embedding) async {
    // Validate before saving — never save bad data
    if (embedding.length != 192) {
      debugPrint('❌ saveEmbedding: refusing to save invalid embedding length ${embedding.length}');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyEmbedding, jsonEncode(embedding));
    debugPrint('✅ saveEmbedding: saved → length: ${embedding.length}');
  }

  /// Get embedding
  Future<List<double>?> getEmbedding() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(keyEmbedding);

    // No embedding saved yet
    if (data == null) {
      debugPrint('❌ getEmbedding: no data found for key "$keyEmbedding"');
      return null;
    }

    // Decode JSON
    final List<dynamic> decoded;
    try {
      decoded = jsonDecode(data);
    } catch (e) {
      debugPrint('❌ getEmbedding: JSON decode failed → $e');
      await prefs.remove(keyEmbedding); // clear corrupted data
      return null;
    }

    // Validate length — must be exactly 192
    if (decoded.length != 192) {
      debugPrint('❌ getEmbedding: invalid length ${decoded.length}, expected 192 → clearing');
      await prefs.remove(keyEmbedding); // clear bad data so re-register works cleanly
      return null;
    }

    final embedding = decoded.map((e) => (e as num).toDouble()).toList();

    debugPrint('✅ getEmbedding: loaded successfully → length: ${embedding.length}');
    return embedding;
  }

  /// Optional: clear stored face
  Future<void> clearEmbedding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // await prefs.remove(keyEmbedding);
  }
}