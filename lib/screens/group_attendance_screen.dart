import 'package:camera/camera.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/liveness_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../local_database/app_database.dart';

typedef GroupAttendanceResult = List<FaceScanAttendanceResult>;

class GroupScanCameraScreen extends StatefulWidget {
  final AppDatabase db;
  final bool isGroupMode;

  const GroupScanCameraScreen({
    super.key,
    required this.db,
    this.isGroupMode = true,
  });

  @override
  State<GroupScanCameraScreen> createState() => _GroupScanCameraScreenState();
}

class _GroupScanCameraScreenState extends State<GroupScanCameraScreen>
    with SingleTickerProviderStateMixin {
  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _controller;
  List<CameraDescription> _allCameras = [];
  int _selectedCameraIndex = 0;
  Size? _previewSize; // actual pixel size of camera frames

  // ── Services ──────────────────────────────────────────────────────────────
  final LivenessService _liveness  = LivenessService();
  final FaceEmbeddingService _embedding = FaceEmbeddingService();
  final FaceService _faceService   = FaceService();

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isProcessing = false;
  bool _isCapturing  = false;
  bool _cameraReady  = false;
  bool _isSwitching  = false;
  bool _showResult   = false;

  // ── Live face boxes ───────────────────────────────────────────────────────
  List<Face> _liveFaces = []; // updated every frame for the overlay

  String _instruction = 'Stand in front of camera';
  List<FaceScanAttendanceResult> _results = [];

  // ── Flip animation ────────────────────────────────────────────────────────
  late final AnimationController _flipAnimController;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      minFaceSize: 0.10,
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true
    ),
  );

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _flipAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initCamera();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _controller?.dispose();
    _faceDetector.close();
    _faceService.dispose();
    _flipAnimController.dispose();
    super.dispose();
  }

  // ── Camera init ───────────────────────────────────────────────────────────

  Future<void> _initCamera({int? cameraIndex}) async {
    try {
      await _embedding.loadModel();

      if (_allCameras.isEmpty) {
        _allCameras = await availableCameras();
      }

      if (cameraIndex == null) {
        // Default: back camera for group (wider FOV)
        _selectedCameraIndex = _allCameras.indexWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
        );
        if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;
      } else {
        _selectedCameraIndex = cameraIndex;
      }

      final selectedCamera = _allCameras[_selectedCameraIndex];

      await _controller?.dispose();

      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _controller!.initialize();
      if (!mounted) return;

      await _controller!.lockCaptureOrientation();

      setState(() {
        _cameraReady  = true;
        _isSwitching  = false;
        _liveFaces    = [];
        _previewSize  = null;
      });

      _controller!.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrint('❌ Camera init error: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  // ── Flip camera ───────────────────────────────────────────────────────────

  Future<void> _flipCamera() async {
    if (_isSwitching || _allCameras.length < 2 || _isCapturing) return;

    setState(() {
      _isSwitching = true;
      _cameraReady = false;
      _liveFaces   = [];
    });

    _flipAnimController.forward(from: 0);

    try {
      await _controller?.stopImageStream();
    } catch (_) {}

    _liveness.reset();
    _setInstruction('Stand in front of camera');

    final nextIndex = (_selectedCameraIndex + 1) % _allCameras.length;
    await _initCamera(cameraIndex: nextIndex);
  }

  // ── Per-frame processing ──────────────────────────────────────────────────

  Future<void> _onCameraFrame(CameraImage image) async {
    if (_isProcessing || _isCapturing) return;
    _isProcessing = true;

    // Store the raw frame dimensions for the painter
    if (_previewSize == null) {
      _previewSize = Size(image.width.toDouble(), image.height.toDouble());
    }

    try {
      final currentCamera = _allCameras[_selectedCameraIndex];
      final faces = await _detectFacesFromFrame(image, currentCamera);

      // Always update live bounding boxes (even when not capturing)
      if (mounted && !_isCapturing) {
        setState(() => _liveFaces = faces);
      }

      if (faces.isEmpty) {
        _setInstruction(widget.isGroupMode
            ? 'Position group in front of camera'
            : 'Position your face clearly');
        return;
      }

      _setInstruction('${faces.length} face(s) detected — hold still');

      if (faces.isNotEmpty) {
        _isCapturing = true;
        _setInstruction('Scanning ${faces.length} person(s)...');

        await _controller!.stopImageStream();
        await Future.delayed(const Duration(seconds: 2));

        final file = await _controller!.takePicture();
        await _runGroupFaceScan(file.path, faces.length);
      }
    } catch (e) {
      debugPrint('❌ Frame error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // ── Face detection ────────────────────────────────────────────────────────

  Future<List<Face>> _detectFacesFromFrame(
      CameraImage image,
      CameraDescription camera,
      ) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }

      final rotation = _getInputImageRotation(camera);

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

  InputImageRotation _getInputImageRotation(CameraDescription camera) {
    switch (camera.sensorOrientation) {
      case 90:  return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default:  return InputImageRotation.rotation0deg;
    }
  }

  // ── Group scan ────────────────────────────────────────────────────────────

  Future<void> _runGroupFaceScan(String imagePath, int detectedCount) async {
    final resultList = await widget.db.markMultipleAttendanceByFaceScan(
      imagePath: imagePath,
      embeddingService: _embedding,
      faceService: _faceService,
      threshold: 0.75
    );

    if (!mounted) return;

    setState(() {
      _showResult = true;
      _results    = resultList;
      _liveFaces  = []; // clear boxes when showing result
    });

    await Future.delayed(const Duration(seconds: 5));
    if (mounted) Navigator.pop(context, _results);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setInstruction(String text) {
    if (!mounted) return;
    setState(() => _instruction = text);
  }

  void _popWithResults() {
    if (!mounted) return;
    Navigator.pop(context, _results);
  }

  bool get _isFrontCamera =>
      _allCameras.isNotEmpty &&
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
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 16),
        Text(
          _isSwitching ? 'Switching camera...' : 'Starting camera...',
          style: const TextStyle(color: Colors.white),
        ),
      ],
    ),
  );

  Widget _buildCameraView() {
    final screenSize = MediaQuery.of(context).size;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Camera feed ───────────────────────────────────────────────────
        CameraPreview(_controller!),

        // ── Light dim overlay ─────────────────────────────────────────────
        Container(color: Colors.black.withOpacity(0.15)),

        // ── Face bounding box painter ─────────────────────────────────────
        if (!_showResult && _liveFaces.isNotEmpty && _previewSize != null)
          CustomPaint(
            painter: FaceBoxPainter(
              faces: _liveFaces,
              imageSize: _previewSize!,
              screenSize: screenSize,
              isFrontCamera: _isFrontCamera,
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
                  _TopBarButton(
                    icon: Icons.arrow_back_ios_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.isGroupMode ? 'Group Attendance' : 'Mark Attendance',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // ── Flip camera button ──────────────────────────────────
                  AnimatedBuilder(
                    animation: _flipAnimController,
                    builder: (context, child) {
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationY(
                          _flipAnimController.value * 3.14159,
                        ),
                        child: _TopBarButton(
                          icon: Icons.flip_camera_ios_rounded,
                          onTap: _flipCamera,
                          disabled: _isSwitching || _isCapturing,
                          tooltip: _isFrontCamera
                              ? 'Switch to back camera'
                              : 'Switch to front camera',
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Camera label pill ──────────────────────────────────────────────
        if (!_showResult && !_isSwitching)
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _CameraPill(
                  key: ValueKey(_selectedCameraIndex),
                  label: _isFrontCamera ? 'Front Camera' : 'Back Camera',
                  icon: _isFrontCamera
                      ? Icons.face_rounded
                      : Icons.camera_rear_rounded,
                ),
              ),
            ),
          ),

        // ── Face count badge ───────────────────────────────────────────────
        if (!_showResult && _liveFaces.isNotEmpty)
          Positioned(
            top: 140,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _FaceCountBadge(
                  key: ValueKey(_liveFaces.length),
                  count: _liveFaces.length,
                ),
              ),
            ),
          ),

        // ── Result overlay ─────────────────────────────────────────────────
        if (_showResult) _buildGroupResultOverlay(),

        // ── Bottom instruction ─────────────────────────────────────────────
        if (!_showResult)
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.70),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                _instruction,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  // ── Group result overlay ──────────────────────────────────────────────────

  Widget _buildGroupResultOverlay() {
    final successList = _results.where((r) => r.success).toList();
    final failedList  = _results.where((r) => !r.success).toList();

    return Container(
      color: Colors.black.withOpacity(0.88),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _summaryBadge('${successList.length}', 'Marked',
                      Colors.green, Icons.check_circle),
                  _summaryBadge('${failedList.length}', 'Failed',
                      Colors.red, Icons.cancel),
                  _summaryBadge('${_results.length}', 'Total',
                      Colors.blue, Icons.groups),
                ],
              ),
              const Divider(height: 24),
              SizedBox(
                height: 300,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final r = _results[index];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: r.success
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        child: Icon(
                          r.success ? Icons.check : Icons.close,
                          color: r.success ? Colors.green : Colors.red,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        r.user?.name ?? 'Unknown face ${index + 1}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        r.message,
                        style: TextStyle(
                          fontSize: 12,
                          color: r.success
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${(r.similarity * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: r.success ? Colors.green : Colors.red,
                            ),
                          ),
                          Text(
                            r.user?.role ?? '',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _popWithResults,
                  icon: const Icon(Icons.check),
                  label: const Text('Done'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A73E8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryBadge(
      String count,
      String label,
      Color color,
      IconData icon,
      ) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: color.withOpacity(0.1),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(count,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// FaceBoxPainter — draws animated corner-bracket boxes around each detected face
// ─────────────────────────────────────────────────────────────────────────────
class FaceBoxPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final Size screenSize;
  final bool isFrontCamera;

  FaceBoxPainter({
    required this.faces,
    required this.imageSize,
    required this.screenSize,
    required this.isFrontCamera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Scale factors: map face rect coords (in camera image space) → screen space
    final double scaleX = size.width  / imageSize.height; // portrait: width/height swapped
    final double scaleY = size.height / imageSize.width;

    final Paint boxPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final Paint glowPaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    for (final face in faces) {
      final rect = face.boundingBox;

      // Map from camera coords to screen coords
      double left   = rect.left   * scaleX;
      double top    = rect.top    * scaleY;
      double right  = rect.right  * scaleX;
      double bottom = rect.bottom * scaleY;

      // Mirror horizontally for front camera
      if (isFrontCamera) {
        final mirroredLeft  = size.width - right;
        final mirroredRight = size.width - left;
        left  = mirroredLeft;
        right = mirroredRight;
      }

      final faceRect = Rect.fromLTRB(left, top, right, bottom);

      // Padding around face
      final paddedRect = faceRect.inflate(12);
      final cornerLen  = (paddedRect.shortestSide * 0.22).clamp(16.0, 36.0);
      final radius     = 6.0;

      // Draw glow first, then sharp line on top
      _drawCornerBrackets(canvas, glowPaint, paddedRect, cornerLen, radius);
      _drawCornerBrackets(canvas, boxPaint, paddedRect, cornerLen, radius);


    }
  }

  void _drawCornerBrackets(
      Canvas canvas,
      Paint paint,
      Rect rect,
      double len,
      double r,
      ) {
    final path = Path();

    // ── Top-left ──────────────────────────────────────────────────────────
    path.moveTo(rect.left, rect.top + len);
    path.lineTo(rect.left, rect.top + r);
    path.arcToPoint(Offset(rect.left + r, rect.top),
        radius: Radius.circular(r), clockwise: true);
    path.lineTo(rect.left + len, rect.top);

    // ── Top-right ─────────────────────────────────────────────────────────
    path.moveTo(rect.right - len, rect.top);
    path.lineTo(rect.right - r, rect.top);
    path.arcToPoint(Offset(rect.right, rect.top + r),
        radius: Radius.circular(r), clockwise: false);
    path.lineTo(rect.right, rect.top + len);

    // ── Bottom-right ──────────────────────────────────────────────────────
    path.moveTo(rect.right, rect.bottom - len);
    path.lineTo(rect.right, rect.bottom - r);
    path.arcToPoint(Offset(rect.right - r, rect.bottom),
        radius: Radius.circular(r), clockwise: false);
    path.lineTo(rect.right - len, rect.bottom);

    // ── Bottom-left ───────────────────────────────────────────────────────
    path.moveTo(rect.left + len, rect.bottom);
    path.lineTo(rect.left + r, rect.bottom);
    path.arcToPoint(Offset(rect.left, rect.bottom - r),
        radius: Radius.circular(r), clockwise: false);
    path.lineTo(rect.left, rect.bottom - len);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(FaceBoxPainter oldDelegate) =>
      oldDelegate.faces != faces ||
          oldDelegate.imageSize != imageSize ||
          oldDelegate.isFrontCamera != isFrontCamera;
}

// ── Shared UI widgets ─────────────────────────────────────────────────────────

class _TopBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool disabled;
  final String? tooltip;

  const _TopBarButton({
    required this.icon,
    required this.onTap,
    this.disabled = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: disabled ? Colors.white30 : Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _CameraPill extends StatelessWidget {
  final String label;
  final IconData icon;

  const _CameraPill({super.key, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _FaceCountBadge extends StatelessWidget {
  final int count;

  const _FaceCountBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF00E5FF).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.face_rounded, color: Color(0xFF00E5FF), size: 14),
          const SizedBox(width: 6),
          Text(
            '$count face${count == 1 ? '' : 's'} detected',
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}