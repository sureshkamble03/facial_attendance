import 'package:flutter/material.dart';
import 'dart:io';
import 'package:facial_attendance/local_database/app_database.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:image_picker/image_picker.dart';

class GroupPhotoAttendanceScreen extends StatefulWidget {
  final AppDatabase db;

  const GroupPhotoAttendanceScreen({super.key, required this.db});

  @override
  State<GroupPhotoAttendanceScreen> createState() => _GroupPhotoAttendanceScreenState();
}

class _GroupPhotoAttendanceScreenState extends State<GroupPhotoAttendanceScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  bool _isProcessing = false;
  List<FaceScanAttendanceResult> _results = [];

  final FaceEmbeddingService _embedding = FaceEmbeddingService();
  final FaceService _faceService = FaceService();

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1280,
    );

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
        _results = [];
      });
      await _processGroupPhoto();
    }
  }

  Future<void> _processGroupPhoto() async {
    if (_selectedImage == null) return;

    setState(() => _isProcessing = true);

    try {
      await _embedding.loadModel();

      final resultList = await widget.db.markMultipleAttendanceByFaceScan(
        imagePath: _selectedImage!.path,
        embeddingService: _embedding,
        faceService: _faceService,
        threshold: 0.70, // Adjustable
      );

      setState(() {
        _results = resultList;
      });
    } catch (e) {
      debugPrint('Error processing group photo: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to process image')),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Photo Attendance'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Image Preview
          Container(
            height: 320,
            width: double.infinity,
            color: Colors.black,
            child: _selectedImage != null
                ? Image.file(_selectedImage!, fit: BoxFit.contain)
                : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 80, color: Colors.white54),
                  SizedBox(height: 16),
                  Text(
                    'No photo selected',
                    style: TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                ],
              ),
            ),
          ),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Take Photo'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Upload from Gallery'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),
                ),
              ],
            ),
          ),

          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Processing group photo...'),
                ],
              ),
            )
          else if (_results.isNotEmpty)
            Expanded(
              child: _buildResultsList(),
            )
          else if (_selectedImage != null)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No faces detected or processed'),
              ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    final successCount = _results.where((r) => r.success).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '$successCount/${_results.length} Persons Marked Present',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final result = _results[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: result.success
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    child: Icon(
                      result.success ? Icons.check_circle : Icons.cancel,
                      color: result.success ? Colors.green : Colors.red,
                    ),
                  ),
                  title: Text(
                    result.user?.name ?? 'Unknown Person',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (result.user != null) ...[
                        Text(result.user!.role.toUpperCase()),
                        if (result.user!.rollNumber != null)
                          Text('Roll No: ${result.user!.rollNumber}'),
                      ],
                      if (result.similarity != null)
                        Text(
                          'Match: ${(result.similarity! * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: result.similarity! > 0.75
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                    ],
                  ),
                  trailing: Text(
                    result.success ? 'Present' : 'Failed',
                    style: TextStyle(
                      color: result.success ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}