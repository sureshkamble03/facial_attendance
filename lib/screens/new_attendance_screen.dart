import 'package:camera/camera.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/liveness_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../local_database/app_database.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CameraScreen — opens camera, runs liveness, scans face,
// identifies user from DB, marks attendance automatically.
// No userId needed — user is identified purely from the face scan.
// ─────────────────────────────────────────────────────────────────────────────
class ScanCameraScreen extends StatefulWidget {
  final int sessionId;         // active attendance session
  final AppDatabase db;        // injected DB instance

  const ScanCameraScreen({
    super.key,
    required this.sessionId,
    required this.db,
  });

  @override
  State<ScanCameraScreen> createState() => _ScanCameraScreenState();
}

class _ScanCameraScreenState extends State<ScanCameraScreen> {
  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _controller;
  late CameraDescription _frontCamera;

  // ── Services ──────────────────────────────────────────────────────────────
  final LivenessService _liveness       = LivenessService();
  final FaceEmbeddingService _embedding = FaceEmbeddingService(); // singleton
  final FaceService _faceService        = FaceService();

  // ── State flags ───────────────────────────────────────────────────────────
  bool _isProcessing = false;
  bool _isCapturing  = false;
  bool _cameraReady  = false;

  // ── UI state ──────────────────────────────────────────────────────────────
  String _instruction   = 'Look at the camera';
  bool   _showResult    = false;
  bool   _isSuccess     = false;
  FaceScanAttendanceResult? _attendanceResult;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
    ),
  );

  // ── Lifecycle ─────────────────────────────────────────────────────────────

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
    super.dispose();
  }

  // ── Camera init ───────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      // Ensure model is loaded before camera starts
      await _embedding.loadModel();
      debugPrint('✅ Embedding model ready');

      final cameras = await availableCameras();
      _frontCamera = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        _frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _controller!.initialize();
      if (!mounted) return;

      setState(() => _cameraReady = true);
      _controller!.startImageStream(_onCameraFrame);

    } catch (e) {
      debugPrint('❌ Camera init error: $e');
      _popWithResult(null);
    }
  }

  // ── Per-frame liveness processing ─────────────────────────────────────────

  Future<void> _onCameraFrame(CameraImage image) async {
    if (_isProcessing || _isCapturing) return;
    _isProcessing = true;

    try {
      final faces = await _detectFacesFromFrame(image, _frontCamera);

      if (faces.isEmpty) {
        _setInstruction('Position your face in the frame');
        return;
      }
      //
       _liveness.processFace(faces.first);
       _setInstruction(_livenessInstruction());
      //
      // if (_liveness.isLivenessPassed()) {
        _isCapturing = true;
        _setInstruction('Scanning...');

        await _controller!.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 300));

        final file = await _controller!.takePicture();
        debugPrint('📸 Captured: ${file.path}');

        // ── Core: identify user from face + mark attendance ──────────────
        await _runFaceScanAttendance(file.path);
      // }
    } catch (e) {
      debugPrint('❌ Frame error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // ── Face scan → identify → mark attendance ────────────────────────────────

  Future<void> _runFaceScanAttendance(String imagePath) async {
    debugPrint('🔄 Running face scan attendance for session: ${widget.sessionId}');

    // Single DB call does everything:
    // detect → crop → embed → match user → validate session → mark attendance
    final result = await widget.db.markAttendanceByFaceScan(
      imagePath: imagePath,
      embeddingService: _embedding,
      faceService: _faceService,
    );

    debugPrint('📋 Result: $result');

    // Show result overlay
    if (!mounted) return;
    setState(() {
      _showResult       = true;
      _isSuccess        = result.success;
      _attendanceResult = result;
    });

    // Wait so user can read result, then pop
    await Future.delayed(const Duration(seconds: 3));
    _popWithResult(result);
  }

  // ── Face detection from camera frame ──────────────────────────────────────

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

      final format =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21;

      final inputImage = InputImage.fromBytes(
        bytes: allBytes.done().buffer.asUint8List(),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      return await _faceDetector.processImage(inputImage);
    } catch (e) {
      debugPrint('❌ Frame detection error: $e');
      return [];
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _livenessInstruction() {
    if (!_liveness.blinkDetected) return 'Blink your eyes';
    return 'Hold still...';
  }

  void _setInstruction(String text) {
    if (!mounted) return;
    setState(() => _instruction = text);
  }

  void _popWithResult(FaceScanAttendanceResult? result) {
    if (!mounted) return;
    Navigator.pop(context, result);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
        Text(
          'Starting camera...',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ],
    ),
  );

  Widget _buildCameraView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Camera feed ───────────────────────────────────────────────────
        CameraPreview(_controller!),

        // ── Overlay dim ───────────────────────────────────────────────────
        Container(color: Colors.black.withOpacity(0.25)),

        // ── Face oval guide ───────────────────────────────────────────────
        Center(
          child: Container(
            width: 240,
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(
                color: _showResult
                    ? (_isSuccess ? Colors.green : Colors.red)
                    : Colors.white70,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(150),
            ),
          ),
        ),

        // ── Top bar ───────────────────────────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _popWithResult(null),
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'Mark Attendance',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
        ),

        // ── Result card ───────────────────────────────────────────────────
        if (_showResult && _attendanceResult != null)
          _buildResultOverlay(_attendanceResult!),

        // ── Bottom instruction ────────────────────────────────────────────
        if (!_showResult)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.85),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Liveness progress dot
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _progressDot(_liveness.blinkDetected, 'Blink'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _instruction,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Result overlay ────────────────────────────────────────────────────────

  Widget _buildResultOverlay(FaceScanAttendanceResult result) {
    return Container(
      color: Colors.black.withOpacity(0.65),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Icon ──────────────────────────────────────────────────
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: result.success
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  result.success ? Icons.check_circle : Icons.cancel,
                  color: result.success ? Colors.green : Colors.red,
                  size: 48,
                ),
              ),
              const SizedBox(height: 16),

              // ── Status title ───────────────────────────────────────────
              Text(
                result.success ? 'Attendance Marked!' : 'Failed',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: result.success ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 8),

              // ── User details (shown on success) ────────────────────────
              if (result.success && result.user != null) ...[
                const Divider(height: 24),
                _userDetailRow(
                  Icons.person_rounded,
                  'Name',
                  result.user!.name,
                ),
                const SizedBox(height: 8),
                _userDetailRow(
                  Icons.email_rounded,
                  'Email',
                  result.user!.email,
                ),
                const SizedBox(height: 8),
                _userDetailRow(
                  Icons.badge_rounded,
                  'Role',
                  result.user!.role.toUpperCase(),
                ),
                if (result.user!.rollNumber != null) ...[
                  const SizedBox(height: 8),
                  _userDetailRow(
                    Icons.numbers_rounded,
                    'Roll No.',
                    result.user!.rollNumber!,
                  ),
                ],
                if (result.user!.department != null) ...[
                  const SizedBox(height: 8),
                  _userDetailRow(
                    Icons.school_rounded,
                    'Dept.',
                    result.user!.department!,
                  ),
                ],
                const Divider(height: 24),
                // Similarity score bar
                _similarityBar(result.similarity),
              ],

              // ── Message (shown on failure) ─────────────────────────────
              if (!result.success) ...[
                const SizedBox(height: 4),
                Text(
                  result.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _userDetailRow(IconData icon, String label, String value) => Row(
    children: [
      Icon(icon, size: 18, color: Colors.grey),
      const SizedBox(width: 8),
      Text(
        '$label: ',
        style: const TextStyle(
          fontSize: 13,
          color: Colors.grey,
          fontWeight: FontWeight.w500,
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );

  Widget _similarityBar(double similarity) {
    final percent = (similarity * 100).toStringAsFixed(1);
    final color = similarity >= 0.75
        ? Colors.green
        : similarity >= 0.65
        ? Colors.orange
        : Colors.red;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Match confidence',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              '$percent%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: similarity.clamp(0.0, 1.0),
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _progressDot(bool completed, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: completed ? 18 : 12,
        height: completed ? 18 : 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: completed ? Colors.green : Colors.white54,
        ),
        child: completed
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : null,
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: const TextStyle(color: Colors.white54, fontSize: 11),
      ),
    ],
  );
}