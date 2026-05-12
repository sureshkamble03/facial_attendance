import 'package:camera/camera.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/liveness_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../local_database/app_database.dart';

class ScanCameraScreen extends StatefulWidget {
  final AppDatabase db;
  const ScanCameraScreen({super.key, required this.db});

  @override
  State<ScanCameraScreen> createState() => _ScanCameraScreenState();
}

class _ScanCameraScreenState extends State<ScanCameraScreen>
    with SingleTickerProviderStateMixin {

  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _controller;
  List<CameraDescription> _allCameras = [];
  int _selectedCameraIndex = 0;
  bool _isSwitching = false;

  // ── Services ──────────────────────────────────────────────────────────────
  final LivenessService      _liveness    = LivenessService();
  final FaceEmbeddingService _embedding   = FaceEmbeddingService();
  final FaceService          _faceService = FaceService();

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isProcessing = false;
  bool _isCapturing  = false;
  bool _cameraReady  = false;
  bool _showResult   = false;
  bool _isSuccess    = false;
  FaceScanAttendanceResult? _attendanceResult;

  // ── Flip animation ────────────────────────────────────────────────────────
  late final AnimationController _flipAnim;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,      // needed for micro-movement depth check
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.10,
    ),
  );

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _flipAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _liveness.reset();
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    _faceService.dispose();
    _flipAnim.dispose();
    super.dispose();
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _initCamera({int? cameraIndex}) async {
    try {
      await _embedding.loadModel();
      if (_allCameras.isEmpty) _allCameras = await availableCameras();

      if (cameraIndex == null) {
        _selectedCameraIndex = _allCameras.indexWhere(
                (c) => c.lensDirection == CameraLensDirection.front);
        if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;
      } else {
        _selectedCameraIndex = cameraIndex;
      }

      await _controller?.dispose();
      _controller = CameraController(
        _allCameras[_selectedCameraIndex],
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await _controller!.initialize();
      if (!mounted) return;
      setState(() { _cameraReady = true; _isSwitching = false; });
      _controller!.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrint('❌ Camera init error: $e');
      _popWithResult(null);
    }
  }

  Future<void> _flipCamera() async {
    if (_isSwitching || _allCameras.length < 2 || _isCapturing) return;
    setState(() { _isSwitching = true; _cameraReady = false; });
    _flipAnim.forward(from: 0);
    try { await _controller?.stopImageStream(); } catch (_) {}
    _liveness.reset();
    await _initCamera(cameraIndex:
    (_selectedCameraIndex + 1) % _allCameras.length);
  }

  // ── Per-frame pipeline ────────────────────────────────────────────────────

  Future<void> _onCameraFrame(CameraImage image) async {
    if (_isProcessing || _isCapturing) return;
    _isProcessing = true;

    try {
      // Layer 2: screen/texture check
      if (!_liveness.analyzeFrame(image)) {
        if (mounted) setState(() {});
        return;
      }

      // Face detection
      final camera = _allCameras[_selectedCameraIndex];
      final faces  = await _detectFacesFromFrame(image, camera);

      if (faces.isEmpty) {
        if (mounted) setState(() {});
        return;
      }

      // Layers 1 + 3 + 4: challenge, motion, micro-movement
      _liveness.processFace(faces.first);
      if (mounted) setState(() {});

      if (_liveness.spoofReason != null) return;

      if (_liveness.isLivenessPassed()) {
        _isCapturing = true;
        if (mounted) setState(() {});
        await _controller!.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 300));
        final file = await _controller!.takePicture();
        await _runFaceScanAttendance(file.path);
      }
    } catch (e) {
      debugPrint('❌ Frame error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _runFaceScanAttendance(String imagePath) async {
    final result = await widget.db.markAttendanceByFaceScan(
      imagePath: imagePath,
      embeddingService: _embedding,
      faceService: _faceService,
    );
    if (!mounted) return;
    setState(() {
      _showResult       = true;
      _isSuccess        = result.success;
      _attendanceResult = result;
    });
    await Future.delayed(const Duration(seconds: 3));
    _popWithResult(result);
  }

  Future<List<Face>> _detectFacesFromFrame(
      CameraImage image, CameraDescription camera) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) allBytes.putUint8List(plane.bytes);
      final rotation = InputImageRotationValue.fromRawValue(
          camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
      final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;
      return await _faceDetector.processImage(InputImage.fromBytes(
        bytes: allBytes.done().buffer.asUint8List(),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation, format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      ));
    } catch (e) { return []; }
  }

  void _popWithResult(FaceScanAttendanceResult? result) {
    if (!mounted) return;
    Navigator.pop(context, result);
  }

  bool get _isFrontCamera => _allCameras.isNotEmpty &&
      _allCameras[_selectedCameraIndex].lensDirection ==
          CameraLensDirection.front;

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

  Widget _buildLoadingView() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const CircularProgressIndicator(color: Colors.white),
      const SizedBox(height: 16),
      Text(_isSwitching ? 'Switching camera...' : 'Starting camera...',
          style: const TextStyle(color: Colors.white, fontSize: 16)),
    ]),
  );

  Widget _buildCameraView() {
    return Stack(fit: StackFit.expand, children: [
      CameraPreview(_controller!),
      Container(color: Colors.black.withOpacity(0.25)),

      // Oval guide
      Center(
        child: Container(
          width: 240, height: 300,
          decoration: BoxDecoration(
            border: Border.all(
              color: _showResult
                  ? (_isSuccess ? Colors.green : Colors.red)
                  : _liveness.spoofReason != null
                  ? Colors.redAccent
                  : Colors.white70,
              width: 3,
            ),
            borderRadius: BorderRadius.circular(150),
          ),
        ),
      ),

      // Top bar
      Positioned(
        top: 0, left: 0, right: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              _TopBarButton(
                  icon: Icons.arrow_back_ios_rounded,
                  onTap: () => _popWithResult(null)),
              const Expanded(
                child: Text('Mark Attendance',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.w600)),
              ),
              AnimatedBuilder(
                animation: _flipAnim,
                builder: (_, __) => Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(_flipAnim.value * 3.14159),
                  child: _TopBarButton(
                    icon: Icons.flip_camera_ios_rounded,
                    onTap: _flipCamera,
                    disabled: _isSwitching || _isCapturing,
                    tooltip: _isFrontCamera
                        ? 'Switch to back camera'
                        : 'Switch to front camera',
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),

      // Result overlay
      if (_showResult && _attendanceResult != null)
        _buildResultOverlay(_attendanceResult!),

      // Bottom liveness panel
      if (!_showResult)
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.90), Colors.transparent],
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _liveness.progress,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation(
                    _liveness.spoofReason != null
                        ? Colors.red
                        : Colors.greenAccent,
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 14),

              // Challenge chips
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _ChallengeChip(
                  label: _liveness.challenge1.label,
                  done: _liveness.challenge1Passed,
                  active: !_liveness.challenge1Passed,
                ),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward_ios,
                    color: Colors.white38, size: 12),
                const SizedBox(width: 10),
                _ChallengeChip(
                  label: _liveness.challenge2.label,
                  done: _liveness.challenge2Passed,
                  active: _liveness.challenge1Passed &&
                      !_liveness.challenge2Passed,
                ),
              ]),
              const SizedBox(height: 14),

              // Instruction
              Text(
                _isCapturing ? 'Scanning...' : _liveness.currentInstruction,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _liveness.spoofReason != null
                      ? Colors.redAccent
                      : Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),

              // Retry button if spoof caught
              if (_liveness.spoofReason != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () { _liveness.reset(); setState(() {}); },
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text('Try Again',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ]),
          ),
        ),
    ]);
  }

  Widget _buildResultOverlay(FaceScanAttendanceResult result) {
    return Container(
      color: Colors.black.withOpacity(0.65),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.3), blurRadius: 20)]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: result.success
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(result.success ? Icons.check_circle : Icons.cancel,
                  color: result.success ? Colors.green : Colors.red, size: 48),
            ),
            const SizedBox(height: 16),
            Text(result.success ? 'Attendance Marked!' : 'Failed',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                    color: result.success ? Colors.green : Colors.red)),
            const SizedBox(height: 8),
            if (result.success && result.user != null) ...[
              const Divider(height: 24),
              _detailRow(Icons.person_rounded, 'Name', result.user!.name),
              const SizedBox(height: 8),
              _detailRow(Icons.email_rounded, 'Email', result.user!.email),
              const SizedBox(height: 8),
              _detailRow(Icons.badge_rounded, 'Role',
                  result.user!.role.toUpperCase()),
              if (result.user!.rollNumber != null) ...[
                const SizedBox(height: 8),
                _detailRow(Icons.numbers_rounded, 'Roll No.',
                    result.user!.rollNumber!),
              ],
              const Divider(height: 24),
              _similarityBar(result.similarity),
            ],
            if (!result.success) ...[
              const SizedBox(height: 4),
              Text(result.message, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.black54,
                      height: 1.5)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) =>
      Row(children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontSize: 13,
            color: Colors.grey, fontWeight: FontWeight.w500)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w600, color: Colors.black87),
            overflow: TextOverflow.ellipsis)),
      ]);

  Widget _similarityBar(double similarity) {
    final percent = (similarity * 100).toStringAsFixed(1);
    final color = similarity >= 0.75 ? Colors.green
        : similarity >= 0.65 ? Colors.orange : Colors.red;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Match confidence',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        Text('$percent%', style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.bold, color: color)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: similarity.clamp(0.0, 1.0),
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color), minHeight: 8),
      ),
    ]);
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _TopBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool disabled;
  final String? tooltip;

  const _TopBarButton({required this.icon, required this.onTap,
    this.disabled = false, this.tooltip});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45), shape: BoxShape.circle),
        child: Icon(icon,
            color: disabled ? Colors.white30 : Colors.white, size: 22),
      ),
    ),
  );
}

class _ChallengeChip extends StatelessWidget {
  final String label;
  final bool done;
  final bool active;

  const _ChallengeChip(
      {required this.label, required this.done, required this.active});

  @override
  Widget build(BuildContext context) {
    final bg = done ? Colors.green.withOpacity(0.2)
        : active ? Colors.white.withOpacity(0.15)
        : Colors.white.withOpacity(0.06);
    final border = done ? Colors.green
        : active ? Colors.white54 : Colors.white24;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? Colors.green : active ? Colors.white70 : Colors.white30,
          size: 14,
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(
          color: done ? Colors.green : active ? Colors.white : Colors.white38,
          fontSize: 12,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
        )),
      ]),
    );
  }
}