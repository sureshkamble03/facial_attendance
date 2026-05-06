// lib/screens/test/embedding_test_screen.dart

import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../core/embedding_service.dart';
import '../../core/face_service.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../core/embeding_test_utility.dart';
import '../local_database/app_database.dart';

class EmbeddingTestScreen extends StatefulWidget {
  final AppDatabase db;

  const EmbeddingTestScreen({super.key, required this.db});

  @override
  State<EmbeddingTestScreen> createState() => _EmbeddingTestScreenState();
}

class _EmbeddingTestScreenState extends State<EmbeddingTestScreen> {
  final _urlController = TextEditingController(
    // Paste any test image URL here
    text: 'https://frs.pspl.world/uploads/faces/staff/123456791778051163.jpg',
  );
  final _userIdController = TextEditingController(text: '1');

  late final EmbeddingTestUtility _utility;

  bool _isLoading = false;
  final List<String> _logs = [];
  EmbeddingFromUrlResult? _result;

  @override
  void initState() {
    super.initState();
    _utility = EmbeddingTestUtility(
      db: widget.db,
      embeddingService: FaceEmbeddingService(),
      faceService: FaceService(),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userIdController.dispose();
    super.dispose();
  }

  void _addLog(String msg) {
    setState(() => _logs.add('[${DateTime.now().toString().substring(11, 19)}] $msg'));
  }

  Future<void> _run() async {
    final url    = _urlController.text.trim();
    final userId = int.tryParse(_userIdController.text.trim());

    if (url.isEmpty) {
      _addLog('❌ Please enter an image URL');
      return;
    }
    if (userId == null) {
      _addLog('❌ Please enter a valid user ID');
      return;
    }

    setState(() {
      _isLoading = true;
      _logs.clear();
      _result = null;
    });

    _addLog('🔄 Starting...');
    _addLog('🌐 URL: $url');
    _addLog('👤 userId: $userId');

    final result = await _utility.createEmbeddingFromUrl(
      imageUrl: url,
      userId: userId,
    );

    setState(() {
      _isLoading = false;
      _result = result;
    });

    _addLog(result.success
        ? '✅ Done → ${result.message}'
        : '❌ Failed → ${result.message}');

    if (result.success && result.embedding != null) {
      _addLog('📊 Embedding[0..4]: '
          '${result.embedding!.take(4).map((e) => e.toStringAsFixed(4)).join(', ')}...');

      // context.read<AuthBloc>().add(
      //   RegisterEvent(
      //     'Megha',
      //     'devpspl@gmail.com',
      //     '',
      //     result.embedding!,
      //     compressedPath??'',
      //     role: 'student',
      //     rollNumber: '101',
      //     employeeId: '',
      //     department: '',
      //     phone: '',
      //   ),
      // );
    }
  }

  // ── Bulk test with hardcoded user → url map ───────────────────────────────
  Future<void> _runBulk() async {
    setState(() { _isLoading = true; _logs.clear(); });

    // Replace with real userId → imageUrl pairs from your API
    final testData = <int, String>{
      1: 'https://frs.pspl.world/uploads/faces/staff/123456791778046879.jpg',
      2: 'https://frs.pspl.world/uploads/faces/staff/123456791775024922.jpg',
      3: 'https://frs.pspl.world/uploads/faces/staff/10102441770028990.jpg',
    };

    _addLog('🔄 Bulk processing ${testData.length} users...');

    await _utility.bulkCreateEmbeddings(
      testData,
      onEach: (userId, result) {
        _addLog(result.success
            ? '✅ userId $userId → ${result.userName}'
            : '❌ userId $userId → ${result.message}');
      },
    );

    setState(() => _isLoading = false);
    _addLog('✅ Bulk complete');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Embedding Test Utility')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── Input fields ────────────────────────────────────────────────
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Image URL (JPG/PNG)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userIdController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'User ID (from DB)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),

            // ── Buttons ─────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _run,
                    icon: const Icon(Icons.face_retouching_natural),
                    label: const Text('Generate & Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                // const SizedBox(width: 8),
                // Expanded(
                //   child: OutlinedButton.icon(
                //     onPressed: _isLoading ? null : _runBulk,
                //     icon: const Icon(Icons.group),
                //     label: const Text('Bulk Test'),
                //     style: OutlinedButton.styleFrom(
                //       padding: const EdgeInsets.symmetric(vertical: 14),
                //     ),
                //   ),
                // ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Result card ─────────────────────────────────────────────────
            if (_result != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _result!.success
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _result!.success ? Colors.green : Colors.red,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _result!.success ? Icons.check_circle : Icons.error,
                      color: _result!.success ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _result!.message,
                        style: TextStyle(
                          color: _result!.success
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // ── Log console ─────────────────────────────────────────────────
            // Expanded(
            //   child: Container(
            //     padding: const EdgeInsets.all(10),
            //     decoration: BoxDecoration(
            //       color: Colors.grey.shade900,
            //       borderRadius: BorderRadius.circular(10),
            //     ),
            //     child: _isLoading && _logs.isEmpty
            //         ? const Center(
            //       child: CircularProgressIndicator(color: Colors.white),
            //     )
            //         : ListView.builder(
            //       itemCount: _logs.length,
            //       itemBuilder: (_, i) => Text(
            //         _logs[i],
            //         style: TextStyle(
            //           color: _logs[i].startsWith('❌')
            //               ? Colors.red.shade300
            //               : _logs[i].startsWith('✅')
            //               ? Colors.green.shade300
            //               : Colors.white70,
            //           fontSize: 12,
            //           fontFamily: 'monospace',
            //         ),
            //       ),
            //     ),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}