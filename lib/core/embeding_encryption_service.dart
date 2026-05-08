// lib/core/embedding_encryption_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/material.dart' hide Key;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EmbeddingEncryptionService {
  static const String _keyName = 'embedding_master_key';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  late final Encrypter _encrypter;
  late final Key _key;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    String? masterKey = await _secureStorage.read(key: _keyName);

    if (masterKey == null) {
      final keyBytes = SecureRandom(32).bytes;
      // ✅ Use base64Url for key storage (safe for secure storage strings)
      masterKey = base64Url.encode(keyBytes);
      await _secureStorage.write(key: _keyName, value: masterKey);
      debugPrint('🔑 New master key generated and stored');
    } else {
      debugPrint('🔑 Master key loaded from secure storage');
    }

    _key = Key.fromBase64(masterKey);
    _encrypter = Encrypter(AES(_key, mode: AESMode.gcm));
    _initialized = true;
  }

  /// Encrypt — layout: [12-byte IV | ciphertext | 16-byte GCM tag]
  /// Returned as standard base64 (not URL-safe) to preserve + and / chars
  Future<String> encryptEmbedding(List<double> embedding) async {
    await initialize();

    final plainText = jsonEncode(embedding);

    final iv = IV.fromSecureRandom(12);

    final encrypted = _encrypter.encrypt(
      plainText,
      iv: iv,
    );

    final combined = Uint8List.fromList([
      ...iv.bytes,
      ...encrypted.bytes,
    ]);

    // ✅ Use ONLY base64Url
    return base64UrlEncode(combined);
  }

  /// Decrypt — splits [12-byte IV | ciphertext+tag] then decrypts
  Future<List<double>> decryptEmbedding(String? encryptedBase64) async {
    await initialize();

    if (encryptedBase64 == null || encryptedBase64.trim().isEmpty) {
      throw Exception('Embedding data is empty');
    }

    try {
      final cleaned = encryptedBase64
          .trim()
          .replaceAll('"', '');

      // ✅ Use ONLY base64Url
      final combined = base64Url.decode(cleaned);

      if (combined.length < 29) {
        throw Exception('Invalid encrypted data');
      }

      final iv = IV(combined.sublist(0, 12));

      final cipherBytes = combined.sublist(12);

      final decryptedJson = _encrypter.decrypt(
        Encrypted(cipherBytes),
        iv: iv,
      );

      final List<dynamic> decoded = jsonDecode(decryptedJson);

      return decoded.map((e) => (e as num).toDouble()).toList();

    } catch (e) {
      debugPrint('❌ decryptEmbedding failed: $e');
      rethrow;
    }
  }

  /// Call this to wipe & regenerate the master key.
  /// WARNING: all previously encrypted embeddings become unreadable.
  Future<void> rotateMasterKey() async {
    _initialized = false;
    await _secureStorage.delete(key: _keyName);
    debugPrint('🔑 Master key wiped. Will regenerate on next initialize().');
    await initialize();
  }
}