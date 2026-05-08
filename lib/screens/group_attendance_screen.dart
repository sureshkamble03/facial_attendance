import 'package:camera/camera.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/liveness_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../local_database/app_database.dart';

typedef GroupAttendanceResult = List<FaceScanAttendanceResult>;

class GroupScanCameraScreen extends StatefulWidget {
  final int sessionId;
  final AppDatabase db;

  const GroupScanCameraScreen({
    super.key,
    required this.sessionId,
    required this.db,
  });

  @override
  State<GroupScanCameraScreen> createState() => _GroupScanCameraScreenState();
}

class _GroupScanCameraScreenState extends State<GroupScanCameraScreen> {
  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _controller;
  late CameraDescription _frontCamera;

  // ── Services ──────────────────────────────────────────────────────────────
  final LivenessService _liveness = LivenessService();
  final FaceEmbeddingService _embedding = FaceEmbeddingService();
  final FaceService _faceService = FaceService();

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isProcessing = false;
  bool _isCapturing = false;
  bool _cameraReady = false;
  bool _showResult = false;

  String _instruction = 'Position the group in front of camera';
  List<FaceScanAttendanceResult> _results = [];

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    _faceService.dispose();
    _embedding.dispose();
    super.dispose();
  }

  // ── Camera Initialization ─────────────────────────────────────────────────
  Future<void> _initCamera() async {
    try {
      await _embedding.loadModel();

      final cameras = await availableCameras();
      _frontCamera = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back, // ← Must be front
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        _frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _controller!.initialize();
      if (!mounted) return;

      setState(() => _cameraReady = true);
      _controller!.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrint('❌ Camera init error: $e');
      Navigator.pop(context);
    }
  }

  // ── Camera Frame Processing ───────────────────────────────────────────────
  Future<void> _onCameraFrame(CameraImage image) async {
    if (_isProcessing || _isCapturing) return;
    _isProcessing = true;

    try {
      final faces = await _detectFacesFromFrame(image, _frontCamera);

      if (faces.isEmpty) {
        _setInstruction('No faces detected');
        return;
      }

      _setInstruction('${faces.length} face(s) detected - Hold steady');

      if (faces.length >= 1) {
        _isCapturing = true;
        _setInstruction('Capturing group photo...');

        await _controller!.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 700));

        final file = await _controller!.takePicture();
        debugPrint('📸 Photo captured: ${file.path}');

        await _processGroupPhoto(file.path, faces);
      }
    } catch (e) {
      debugPrint('❌ Frame error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // ── Process Group Photo ───────────────────────────────────────────────────
  Future<void> _processGroupPhoto(String imagePath, List<Face> faces) async {
    debugPrint('📸 _processGroupPhoto started | ${faces.length} faces');

    setState(() => _instruction = 'Processing ${faces.length} faces...');

    try {
      final results = await widget.db.markMultipleAttendanceByFaceScan(
        imagePath: imagePath,
        embeddingService: _embedding,
        faceService: _faceService,
        detectedFaces: faces,
        sessionId: widget.sessionId,
      );

      if (!mounted) return;

      setState(() {
        _showResult = true;
        _results = results;
      });

      debugPrint('✅ Group processing completed. Total results: ${results.length}');

      await Future.delayed(const Duration(seconds: 6));
      if (mounted) _popWithResults();
    } catch (e) {
      debugPrint('❌ Error in _processGroupPhoto: $e');
      _setInstruction('Error processing photo');
    }
  }

  void _popWithResults() {
    if (!mounted) return;
    Navigator.pop(context, _results); // Return full list
  }

  // ── Face Detection from Camera Frame ─────────────────────────────────────
  Future<List<Face>> _detectFacesFromFrame(
      CameraImage image,
      CameraDescription camera,
      ) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }

      final rotation = InputImageRotationValue.fromRawValue(
          camera.sensorOrientation) ??
          InputImageRotation.rotation0deg;

      final inputImage = InputImage.fromBytes(
        bytes: allBytes.done().buffer.asUint8List(),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      return await _faceDetector.processImage(inputImage);
    } catch (e) {
      debugPrint('❌ Detection error: $e');
      return [];
    }
  }

  void _setInstruction(String text) {
    if (!mounted) return;
    setState(() => _instruction = text);
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _cameraReady && _controller != null
          ? _buildCameraView()
          : _buildLoadingView(),
    );
  }

  Widget _buildLoadingView() => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: Colors.white),
        SizedBox(height: 16),
        Text('Starting camera...', style: TextStyle(color: Colors.white)),
      ],
    ),
  );

  Widget _buildCameraView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_controller!),
        Container(color: Colors.black.withOpacity(0.3)),

        // Group guide frame
        Center(
          child: Container(
            width: 340,
            height: 420,
            decoration: BoxDecoration(
              border: Border.all(
                color: _showResult ? Colors.green : Colors.white70,
                width: 4,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),

        // Top Bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'Group Attendance',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
          ),
        ),

        if (!_showResult)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  _instruction,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

        if (_showResult) _buildGroupResultOverlay(),
      ],
    );
  }

  Widget _buildGroupResultOverlay() {
    final successCount = _results.where((r) => r.success).length;

    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$successCount/${_results.length} Marked Successfully',
                style:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 320,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final result = _results[index];
                    return ListTile(
                      leading: Icon(
                        result.success ? Icons.check_circle : Icons.cancel,
                        color: result.success ? Colors.green : Colors.red,
                      ),
                      title: Text(result.user?.name ?? 'Unknown'),
                      subtitle: Text(result.message),
                      trailing: Text(
                        '${(result.similarity * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: result.success ? Colors.green : Colors.red,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _popWithResults,
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}