import 'package:camera/camera.dart';
import 'package:facial_attendance/core/liveness_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CameraScreen — used for REGISTRATION only.
// Single-challenge liveness (blink only), forgiving thresholds,
// generous micro-movement window, camera flip support.
// Returns file path via Navigator.pop(context, filePath).
// ─────────────────────────────────────────────────────────────────────────────
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {

  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _controller;
  List<CameraDescription> _allCameras = [];
  int _selectedCameraIndex = 0;
  bool _isSwitching = false;
  bool _cameraReady = false;

  // ── Liveness (registration-grade: easy single blink) ─────────────────────
  bool _blinkDetected       = false;
  bool _faceInFrame         = false;
  bool _screenDetected      = false;
  int  _screenFrameCount    = 0;
  int  _microMovementCount  = 0;
  double? _prevEyeY;

  // Much lower bar than attendance: just blink + a tiny bit of natural motion
  static const int _microMovementTarget = 4;
  static const int _screenFrameLimit    = 8; // more lenient than attendance

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isProcessing = false;
  bool _isCapturing  = false;
  bool _captured     = false;

  // ── Flip animation ────────────────────────────────────────────────────────
  late final AnimationController _flipAnim;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,       // for eye-Y micro-movement
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.12,
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
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    _flipAnim.dispose();
    super.dispose();
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _initCamera({int? cameraIndex}) async {
    try {
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
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _flipCamera() async {
    if (_isSwitching || _allCameras.length < 2 || _isCapturing) return;
    setState(() { _isSwitching = true; _cameraReady = false; });
    _flipAnim.forward(from: 0);
    try { await _controller?.stopImageStream(); } catch (_) {}
    _resetLiveness();
    await _initCamera(cameraIndex:
        (_selectedCameraIndex + 1) % _allCameras.length);
  }

  // ── Liveness helpers ──────────────────────────────────────────────────────

  void _resetLiveness() {
    _blinkDetected      = false;
    _faceInFrame        = false;
    _screenDetected     = false;
    _screenFrameCount   = 0;
    _microMovementCount = 0;
    _prevEyeY           = null;
  }

  /// Layer 2: screen detection via Y-plane variance (lenient for registration)
  bool _analyzeFrame(CameraImage image) {
    try {
      final yPlane = image.planes[0].bytes;
      double sum = 0, sumSq = 0;
      int count = 0;
      for (int i = 0; i < yPlane.length; i += 6) {
        final v = yPlane[i].toDouble();
        sum += v; sumSq += v * v; count++;
      }
      if (count == 0) return true;
      final mean = sum / count;
      final variance = (sumSq / count) - (mean * mean);

      if (variance < 160) {
        _screenFrameCount++;
        if (_screenFrameCount >= _screenFrameLimit) {
          _screenDetected = true;
          return false;
        }
      } else {
        _screenFrameCount = (_screenFrameCount - 1).clamp(0, _screenFrameLimit);
      }
    } catch (_) {}
    return true;
  }

  /// Returns true once all registration-grade liveness checks pass.
  bool _isRegistrationLivenessPassed() =>
      _blinkDetected &&
      _microMovementCount >= _microMovementTarget &&
      !_screenDetected;

  // ── Per-frame processing ──────────────────────────────────────────────────

  Future<void> _onCameraFrame(CameraImage image) async {
    if (_isProcessing || _isCapturing) return;
    _isProcessing = true;

    try {
      // Layer 2: screen check
      if (!_analyzeFrame(image)) {
        if (mounted) setState(() {});
        return;
      }

      final camera = _allCameras[_selectedCameraIndex];
      final faces  = await _detectFaces(image, camera);

      if (faces.isEmpty) {
        if (mounted) setState(() => _faceInFrame = false);
        return;
      }

      final face = faces.first;
      if (mounted) setState(() => _faceInFrame = true);

      // Layer 1: blink (forgiving threshold for registration)
      if (!_blinkDetected) {
        final leftEye  = face.leftEyeOpenProbability  ?? 1.0;
        final rightEye = face.rightEyeOpenProbability ?? 1.0;
        if (leftEye < 0.35 && rightEye < 0.35) {
          _blinkDetected = true;
          debugPrint('✅ Blink detected for registration');
        }
      }

      // Layer 4: micro-movement (lenient — just proves not a still photo)
      final eyeY = face.landmarks[FaceLandmarkType.leftEye]
          ?.position.y.toDouble();
      if (eyeY != null && _prevEyeY != null) {
        final delta = (eyeY - _prevEyeY!).abs();
        if (delta > 0.2 && delta < 15) _microMovementCount++;
      }
      _prevEyeY = eyeY;

      if (mounted) setState(() {});

      // All checks passed → capture
      if (_isRegistrationLivenessPassed() && !_isCapturing) {
        _isCapturing = true;
        if (mounted) setState(() {});
        await _controller!.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 400));
        final file = await _controller!.takePicture();
        debugPrint('📸 Registration photo captured: ${file.path}');
        if (!mounted) return;
        setState(() => _captured = true);
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.pop(context, file.path);
      }
    } catch (e) {
      debugPrint('❌ Frame error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<List<Face>> _detectFaces(
      CameraImage image, CameraDescription camera) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) allBytes.putUint8List(plane.bytes);
      final rotation = InputImageRotationValue.fromRawValue(
              camera.sensorOrientation) ??
          InputImageRotation.rotation0deg;
      final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;
      return await _faceDetector.processImage(InputImage.fromBytes(
        bytes: allBytes.done().buffer.asUint8List(),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      ));
    } catch (_) { return []; }
  }

  bool get _isFrontCamera => _allCameras.isNotEmpty &&
      _allCameras[_selectedCameraIndex].lensDirection ==
          CameraLensDirection.front;

  // ── Instruction text ──────────────────────────────────────────────────────

  String get _instruction {
    if (_captured)               return '✅ Photo captured!';
    if (_isCapturing)            return 'Capturing...';
    if (_screenDetected)         return '⚠️ Screen detected — use your real face';
    if (!_faceInFrame)           return 'Position your face inside the oval';
    if (!_blinkDetected)         return 'Slowly blink your eyes once';
    if (_microMovementCount < _microMovementTarget)
                                 return 'Hold still naturally...';
    return 'Almost there...';
  }

  Color get _instructionColor {
    if (_captured)           return Colors.green;
    if (_screenDetected)     return Colors.redAccent;
    if (!_faceInFrame)       return Colors.white70;
    return Colors.white;
  }

  double get _progress {
    double p = 0;
    if (_faceInFrame)   p += 0.2;
    if (_blinkDetected) p += 0.5;
    p += (_microMovementCount / _microMovementTarget * 0.3).clamp(0, 0.3);
    return p.clamp(0, 1);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: !_cameraReady || _controller == null
          ? _buildLoading()
          : _buildCamera(),
    );
  }

  Widget _buildLoading() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 16),
          Text(
            _isSwitching ? 'Switching camera...' : 'Starting camera...',
            style: const TextStyle(color: Colors.white),
          ),
        ]),
      );

  Widget _buildCamera() {
    return Stack(fit: StackFit.expand, children: [

      // ── Camera feed ───────────────────────────────────────────────────────
      CameraPreview(_controller!),

      // ── Dark vignette ─────────────────────────────────────────────────────
      Container(color: Colors.black.withOpacity(0.20)),

      // ── Oval face guide ───────────────────────────────────────────────────
      Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 230,
          height: 295,
          decoration: BoxDecoration(
            border: Border.all(
              color: _captured
                  ? Colors.green
                  : _screenDetected
                      ? Colors.red
                      : _faceInFrame
                          ? const Color(0xFF00E5FF)
                          : Colors.white54,
              width: _faceInFrame ? 3.5 : 2,
            ),
            borderRadius: BorderRadius.circular(150),
          ),
        ),
      ),

      // ── Corner scan lines (decoration) ────────────────────────────────────
      if (_faceInFrame && !_captured)
        Center(
          child: SizedBox(
            width: 230 + 30,
            height: 295 + 30,
            child: CustomPaint(painter: _CornerPainter(
              color: _blinkDetected
                  ? Colors.greenAccent
                  : const Color(0xFF00E5FF),
            )),
          ),
        ),

      // ── Top bar ───────────────────────────────────────────────────────────
      Positioned(
        top: 0, left: 0, right: 0,
        child: SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              _CircleButton(
                icon: Icons.arrow_back_ios_rounded,
                onTap: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Register Face',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    Text('One-time setup',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: _flipAnim,
                builder: (_, __) => Transform(
                  alignment: Alignment.center,
                  transform:
                      Matrix4.rotationY(_flipAnim.value * 3.14159),
                  child: _CircleButton(
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

      // ── Success flash ─────────────────────────────────────────────────────
      if (_captured)
        Container(
          color: Colors.green.withOpacity(0.25),
          child: const Center(
            child: Icon(Icons.check_circle_outline,
                color: Colors.white, size: 100),
          ),
        ),

      // ── Bottom panel ──────────────────────────────────────────────────────
      if (!_captured)
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 44),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.92),
                  Colors.transparent,
                ],
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [

              // Step indicators
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _StepDot(
                  icon: Icons.face_rounded,
                  label: 'Face',
                  done: _faceInFrame,
                  active: !_faceInFrame,
                ),
                _StepLine(done: _faceInFrame),
                _StepDot(
                  icon: Icons.visibility_off_rounded,
                  label: 'Blink',
                  done: _blinkDetected,
                  active: _faceInFrame && !_blinkDetected,
                ),
                _StepLine(done: _blinkDetected),
                _StepDot(
                  icon: Icons.camera_alt_rounded,
                  label: 'Capture',
                  done: _isCapturing,
                  active: _blinkDetected && !_isCapturing,
                ),
              ]),

              const SizedBox(height: 16),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white,
                  valueColor: AlwaysStoppedAnimation(
                    _screenDetected ? Colors.red : Colors.greenAccent,
                  ),
                  minHeight: 6,
                ),
              ),

              const SizedBox(height: 14),

              // Instruction
              Text(
                _instruction,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _instructionColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),

              // Tips
              if (!_faceInFrame) ...[
                const SizedBox(height: 8),
                _TipText('Make sure your face fits inside the oval'),
              ] else if (!_blinkDetected) ...[
                const SizedBox(height: 8),
                _TipText('Close both eyes fully, then open them'),
              ],

              // Retry for spoof
              if (_screenDetected) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setState(_resetLiveness),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Corner bracket painter for the face guide
// ─────────────────────────────────────────────────────────────────────────────
class _CornerPainter extends CustomPainter {
  final Color color;
  _CornerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const len = 22.0;
    const r   = 5.0;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final path = Path();

    // Top-left
    path.moveTo(rect.left, rect.top + len);
    path.lineTo(rect.left, rect.top + r);
    path.arcToPoint(Offset(rect.left + r, rect.top),
        radius: const Radius.circular(r));
    path.lineTo(rect.left + len, rect.top);

    // Top-right
    path.moveTo(rect.right - len, rect.top);
    path.lineTo(rect.right - r, rect.top);
    path.arcToPoint(Offset(rect.right, rect.top + r),
        radius: const Radius.circular(r), clockwise: false);
    path.lineTo(rect.right, rect.top + len);

    // Bottom-right
    path.moveTo(rect.right, rect.bottom - len);
    path.lineTo(rect.right, rect.bottom - r);
    path.arcToPoint(Offset(rect.right - r, rect.bottom),
        radius: const Radius.circular(r), clockwise: false);
    path.lineTo(rect.right - len, rect.bottom);

    // Bottom-left
    path.moveTo(rect.left + len, rect.bottom);
    path.lineTo(rect.left + r, rect.bottom);
    path.arcToPoint(Offset(rect.left, rect.bottom - r),
        radius: const Radius.circular(r), clockwise: false);
    path.lineTo(rect.left, rect.bottom - len);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Small UI widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool disabled;
  final String? tooltip;

  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.disabled = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip ?? '',
        child: GestureDetector(
          onTap: disabled ? null : onTap,
          child: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.50),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                color: disabled ? Colors.white30 : Colors.white, size: 20),
          ),
        ),
      );
}

class _StepDot extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool done;
  final bool active;

  const _StepDot({
    required this.icon,
    required this.label,
    required this.done,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = done
        ? Colors.greenAccent
        : active
            ? Colors.white
            : Colors.white30;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: done || active ? 38 : 30,
        height: done || active ? 38 : 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done
              ? Colors.greenAccent.withOpacity(0.2)
              : active
                  ? Colors.white.withOpacity(0.12)
                  : Colors.transparent,
          border: Border.all(color: color, width: done ? 2 : 1.5),
        ),
        child: Icon(done ? Icons.check : icon,
            color: color, size: done || active ? 18 : 14),
      ),
      const SizedBox(height: 4),
      Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w500)),
    ]);
  }
}

class _StepLine extends StatelessWidget {
  final bool done;
  const _StepLine({required this.done});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: 36,
        height: 2,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          color: done ? Colors.greenAccent : Colors.white24,
        ),
      );
}

class _TipText extends StatelessWidget {
  final String text;
  const _TipText(this.text);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, color: Colors.white38, size: 13),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      );
}
