import 'package:camera/camera.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/geo_fence_service.dart';
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
  const GroupScanCameraScreen({super.key, required this.db,
      this.isGroupMode = true});

  @override
  State<GroupScanCameraScreen> createState() => _GroupScanCameraScreenState();
}

class _GroupScanCameraScreenState extends State<GroupScanCameraScreen>
    with SingleTickerProviderStateMixin {

  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _controller;
  List<CameraDescription> _allCameras = [];
  int  _selectedCameraIndex = 0;
  Size? _previewSize;
  bool _isSwitching = false;
  bool _cameraReady = false;

  // ── Services ──────────────────────────────────────────────────────────────
  final LivenessService      _liveness    = LivenessService();
  final FaceEmbeddingService _embedding   = FaceEmbeddingService();
  final FaceService          _faceService = FaceService();
  final GeoFenceService      _geoService  = GeoFenceService();

  // ── Geo ───────────────────────────────────────────────────────────────────
  String          _geoStatus = 'checking';
  GeoCheckResult? _geoResult;

  // ── Scan state ────────────────────────────────────────────────────────────
  bool _isProcessing = false;
  bool _isCapturing  = false;
  bool _showResult   = false;
  List<Face>                     _liveFaces = [];
  List<FaceScanAttendanceResult> _results   = [];

  late final AnimationController _flipAnim;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, enableLandmarks: true,
      enableTracking: true, performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.10,
    ),
  );

  @override
  void initState() {
    super.initState();
    _flipAnim = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 350));
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _verifyLocation();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _controller?.dispose();
    _faceDetector.close();
    _faceService.dispose();
    _flipAnim.dispose();
    super.dispose();
  }

  // ── Location gate ─────────────────────────────────────────────────────────

  Future<void> _verifyLocation() async {
    if (mounted) setState(() => _geoStatus = 'checking');
    try {
      final dbZones = await widget.db.getActiveZones();
      final zones   = dbZones.map((z) => GeoZone(
        id: z.id, name: z.name, latitude: z.latitude,
        longitude: z.longitude, radiusMeters: z.radiusMeters,
        isActive: z.isActive, createdAt: z.createdAt,
      )).toList();

      final result = await _geoService.verifyLocation(zones);
      if (!mounted) return;
      setState(() {
        _geoResult = result;
        _geoStatus = result.allowed ? 'allowed' : 'denied';
      });
      if (result.allowed) _initCamera();
    } catch (e) {
      if (mounted) setState(() {
        _geoStatus = 'denied';
        _geoResult = GeoCheckResult(allowed: false,
            message: 'Location check failed: $e');
      });
    }
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _initCamera({int? cameraIndex}) async {
    try {
      await _embedding.loadModel();
      if (_allCameras.isEmpty) _allCameras = await availableCameras();

      if (cameraIndex == null) {
        _selectedCameraIndex = _allCameras.indexWhere(
            (c) => c.lensDirection == CameraLensDirection.back);
        if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;
      } else {
        _selectedCameraIndex = cameraIndex;
      }

      await _controller?.dispose();
      _controller = CameraController(_allCameras[_selectedCameraIndex],
          ResolutionPreset.high, enableAudio: false,
          imageFormatGroup: ImageFormatGroup.nv21);
      await _controller!.initialize();
      if (!mounted) return;
      await _controller!.lockCaptureOrientation();
      setState(() { _cameraReady = true; _isSwitching = false;
        _liveFaces = []; _previewSize = null; });
      _controller!.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrint('❌ Camera error: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _flipCamera() async {
    if (_isSwitching || _allCameras.length < 2 || _isCapturing) return;
    setState(() { _isSwitching = true; _cameraReady = false; _liveFaces = []; });
    _flipAnim.forward(from: 0);
    try { await _controller?.stopImageStream(); } catch (_) {}
    _liveness.reset();
    await _initCamera(cameraIndex:
        (_selectedCameraIndex + 1) % _allCameras.length);
  }

  // ── Frame pipeline ────────────────────────────────────────────────────────

  Future<void> _onCameraFrame(CameraImage image) async {
    if (_isProcessing || _isCapturing) return;
    _isProcessing = true;

    if (_previewSize == null) {
      _previewSize = Size(image.width.toDouble(), image.height.toDouble());
    }

    try {
      final camera = _allCameras[_selectedCameraIndex];
      final faces  = await _detectFaces(image, camera);

      if (mounted && !_isCapturing) setState(() => _liveFaces = faces);

      if (faces.isEmpty) return;

      if (faces.isNotEmpty && !_isCapturing) {
        _isCapturing = true;
        if (mounted) setState(() {});
        await _controller!.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 500));
        final file = await _controller!.takePicture();
        await _runGroupScan(file.path);
      }
    } catch (e) { debugPrint('❌ Frame error: $e'); }
    finally { _isProcessing = false; }
  }

  Future<void> _runGroupScan(String imagePath) async {
    final results = await widget.db.markMultipleAttendanceByFaceScan(
      imagePath: imagePath,
      embeddingService: _embedding,
      faceService: _faceService,
      geoLatitude:  _geoResult?.latitude,
      geoLongitude: _geoResult?.longitude,
      zoneName:     _geoResult?.matchedZoneName,
    );
    if (!mounted) return;
    setState(() { _showResult = true; _results = results; _liveFaces = []; });
    await Future.delayed(const Duration(seconds: 5));
    if (mounted) Navigator.pop(context, _results);
  }

  Future<List<Face>> _detectFaces(CameraImage image,
      CameraDescription camera) async {
    try {
      final WriteBuffer buf = WriteBuffer();
      for (final p in image.planes) buf.putUint8List(p.bytes);
      InputImageRotation rot;
      switch (camera.sensorOrientation) {
        case 90:  rot = InputImageRotation.rotation90deg; break;
        case 180: rot = InputImageRotation.rotation180deg; break;
        case 270: rot = InputImageRotation.rotation270deg; break;
        default:  rot = InputImageRotation.rotation0deg;
      }
      return await _faceDetector.processImage(InputImage.fromBytes(
        bytes: buf.done().buffer.asUint8List(),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rot, format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      ));
    } catch (_) { return []; }
  }

  bool get _isFrontCamera => _allCameras.isNotEmpty &&
      _allCameras[_selectedCameraIndex].lensDirection ==
          CameraLensDirection.front;

  String get _instruction {
    if (_isCapturing) return 'Scanning ${_liveFaces.length} person(s)...';
    if (_liveFaces.isEmpty) return 'Position group in front of camera';
    return '${_liveFaces.length} face(s) detected — hold still';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (_geoStatus) {
        'checking' => _geoCheckingView(),
        'denied'   => _geoDeniedView(),
        _          => _cameraView(),
      },
    );
  }

  Widget _geoCheckingView() => Container(
    color: const Color(0xFF0A1628),
    child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center,
        children: [
      Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08),
            shape: BoxShape.circle),
        child: const Icon(Icons.location_searching_rounded,
            color: Colors.white, size: 40)),
      const SizedBox(height: 24),
      const Text('Verifying Location', style: TextStyle(color: Colors.white,
          fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text('Checking you are in an allowed zone...',
          style: TextStyle(color: Colors.white.withOpacity(0.55),
              fontSize: 13)),
      const SizedBox(height: 28),
      const CircularProgressIndicator(
          color: Color(0xFF1A73E8), strokeWidth: 3),
    ])),
  );

  Widget _geoDeniedView() => Container(
    color: const Color(0xFF0A1628),
    child: SafeArea(child: Column(children: [
      Align(alignment: Alignment.centerLeft,
        child: Padding(padding: const EdgeInsets.all(16),
          child: GestureDetector(onTap: () => Navigator.pop(context),
            child: Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back_ios_rounded,
                  color: Colors.white, size: 18))))),
      const Spacer(),
      Container(padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.red.withOpacity(0.12),
            shape: BoxShape.circle),
        child: const Icon(Icons.location_off_rounded,
            color: Colors.redAccent, size: 52)),
      const SizedBox(height: 24),
      const Text('Location Verification Failed',
          style: TextStyle(color: Colors.white, fontSize: 19,
              fontWeight: FontWeight.bold), textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Text(_geoResult?.message ?? 'Unable to verify location.',
            style: TextStyle(color: Colors.white.withOpacity(0.60),
                fontSize: 14, height: 1.55),
            textAlign: TextAlign.center)),
      if (_geoResult?.distanceMeters != null) ...[
        const SizedBox(height: 20),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.near_me_rounded, color: Colors.white38, size: 16),
            const SizedBox(width: 8),
            Text('${_geoResult!.matchedZoneName ?? "Nearest zone"}  '
                '— ${_geoResult!.distanceMeters!.toStringAsFixed(0)} m away',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ])),
      ],
      const Spacer(),
      Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: SizedBox(width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _verifyLocation,
            icon: const Icon(Icons.my_location_rounded),
            label: const Text('Try Again',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            )))),
    ])),
  );

  Widget _cameraView() {
    if (!_cameraReady || _controller == null) {
      return Container(color: Colors.black,
        child: Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 16),
          Text(_isSwitching ? 'Switching camera...' : 'Starting camera...',
              style: const TextStyle(color: Colors.white)),
        ])));
    }

    final screenSize = MediaQuery.of(context).size;

    return Stack(fit: StackFit.expand, children: [
      CameraPreview(_controller!),
      Container(color: Colors.black.withOpacity(0.15)),

      // Face bounding boxes
      if (!_showResult && _liveFaces.isNotEmpty && _previewSize != null)
        CustomPaint(painter: FaceBoxPainter(
          faces: _liveFaces, imageSize: _previewSize!,
          screenSize: screenSize, isFrontCamera: _isFrontCamera)),

      // Top bar
      Positioned(top: 0, left: 0, right: 0,
        child: SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            _TopBarButton(icon: Icons.arrow_back_ios_rounded,
                onTap: () => Navigator.pop(context)),
            Expanded(child: Text(
                widget.isGroupMode ? 'Group Attendance' : 'Mark Attendance',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.w600))),
            AnimatedBuilder(animation: _flipAnim,
              builder: (_, __) => Transform(alignment: Alignment.center,
                transform: Matrix4.rotationY(_flipAnim.value * 3.14159),
                child: _TopBarButton(icon: Icons.flip_camera_ios_rounded,
                    onTap: _flipCamera,
                    disabled: _isSwitching || _isCapturing))),
          ])))),

      // Zone badge
      if (_geoResult?.matchedZoneName != null && !_showResult)
        Positioned(top: 100, left: 0, right: 0,
          child: Center(child: _ZoneBadge(
              zoneName: _geoResult!.matchedZoneName!))),

      // Face count badge
      if (!_showResult && _liveFaces.isNotEmpty)
        Positioned(top: _geoResult?.matchedZoneName != null ? 144 : 100,
          left: 0, right: 0,
          child: Center(child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _FaceCountBadge(key: ValueKey(_liveFaces.length),
                count: _liveFaces.length)))),

      // Result overlay
      if (_showResult) _groupResultOverlay(),

      // Bottom instruction
      if (!_showResult)
        Positioned(bottom: 40, left: 20, right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.70),
                borderRadius: BorderRadius.circular(30)),
            child: Text(_instruction,
                style: const TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center))),
    ]);
  }

  Widget _groupResultOverlay() {
    final successList = _results.where((r) => r.success).toList();
    final failedList  = _results.where((r) => !r.success).toList();

    return Container(
      color: Colors.black.withOpacity(0.88),
      child: Center(child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Zone info
          if (_geoResult?.matchedZoneName != null)
            Container(margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.green.withOpacity(0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_on_rounded,
                    size: 13, color: Colors.green),
                const SizedBox(width: 5),
                Text(_geoResult!.matchedZoneName!,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.green,
                        fontWeight: FontWeight.w600)),
              ])),

          // Summary badges
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _badge('${successList.length}', 'Marked',
                Colors.green, Icons.check_circle),
            _badge('${failedList.length}', 'Failed',
                Colors.red, Icons.cancel),
            _badge('${_results.length}', 'Total',
                Colors.blue, Icons.groups),
          ]),
          const Divider(height: 24),

          // Per-person results list
          SizedBox(height: 280,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = _results[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 18,
                    backgroundColor: r.success
                        ? Colors.green.shade50 : Colors.red.shade50,
                    child: Icon(r.success ? Icons.check : Icons.close,
                        color: r.success ? Colors.green : Colors.red,
                        size: 18)),
                  title: Text(r.user?.name ?? 'Unknown ${i + 1}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(r.message,
                      style: TextStyle(fontSize: 12,
                          color: r.success
                              ? Colors.green.shade700
                              : Colors.red.shade700)),
                  trailing: Text('${(r.similarity * 100).toStringAsFixed(1)}%',
                      style: TextStyle(fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: r.success ? Colors.green : Colors.red)),
                );
              },
            )),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, _results),
              icon: const Icon(Icons.check),
              label: const Text('Done'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            )),
        ]))),
    );
  }

  Widget _badge(String count, String label, Color color, IconData icon) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 24, backgroundColor: color.withOpacity(0.1),
            child: Icon(icon, color: color, size: 22)),
        const SizedBox(height: 4),
        Text(count, style: TextStyle(fontSize: 20,
            fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]);
}

// ── Face box painter ───────────────────────────────────────────────────────────
class FaceBoxPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final Size screenSize;
  final bool isFrontCamera;

  FaceBoxPainter({required this.faces, required this.imageSize,
      required this.screenSize, required this.isFrontCamera});

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width  / imageSize.height;
    final scaleY = size.height / imageSize.width;

    final boxPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    for (final face in faces) {
      final rect = face.boundingBox;
      double left = rect.left * scaleX, top = rect.top * scaleY;
      double right = rect.right * scaleX, bottom = rect.bottom * scaleY;
      if (isFrontCamera) {
        final ml = size.width - right; final mr = size.width - left;
        left = ml; right = mr;
      }
      final padded = Rect.fromLTRB(left, top, right, bottom).inflate(12);
      final len    = (padded.shortestSide * 0.22).clamp(16.0, 36.0);
      _drawBrackets(canvas, glowPaint, padded, len, 6.0);
      _drawBrackets(canvas, boxPaint,  padded, len, 6.0);
    }
  }

  void _drawBrackets(Canvas c, Paint p, Rect r, double len, double rad) {
    final path = Path();
    path.moveTo(r.left, r.top + len);
    path.lineTo(r.left, r.top + rad);
    path.arcToPoint(Offset(r.left + rad, r.top),
        radius: Radius.circular(rad), clockwise: true);
    path.lineTo(r.left + len, r.top);

    path.moveTo(r.right - len, r.top);
    path.lineTo(r.right - rad, r.top);
    path.arcToPoint(Offset(r.right, r.top + rad),
        radius: Radius.circular(rad), clockwise: false);
    path.lineTo(r.right, r.top + len);

    path.moveTo(r.right, r.bottom - len);
    path.lineTo(r.right, r.bottom - rad);
    path.arcToPoint(Offset(r.right - rad, r.bottom),
        radius: Radius.circular(rad), clockwise: false);
    path.lineTo(r.right - len, r.bottom);

    path.moveTo(r.left + len, r.bottom);
    path.lineTo(r.left + rad, r.bottom);
    path.arcToPoint(Offset(r.left, r.bottom - rad),
        radius: Radius.circular(rad), clockwise: false);
    path.lineTo(r.left, r.bottom - len);

    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(FaceBoxPainter old) =>
      old.faces != faces || old.isFrontCamera != isFrontCamera;
}

// ── Shared widgets ─────────────────────────────────────────────────────────────
class _ZoneBadge extends StatelessWidget {
  final String zoneName;
  const _ZoneBadge({required this.zoneName});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(color: Colors.green.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.5))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.location_on_rounded, color: Colors.greenAccent, size: 14),
      const SizedBox(width: 6),
      Text(zoneName, style: const TextStyle(color: Colors.greenAccent,
          fontSize: 12, fontWeight: FontWeight.w600)),
    ]));
}

class _FaceCountBadge extends StatelessWidget {
  final int count;
  const _FaceCountBadge({super.key, required this.count});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(color: const Color(0xFF00E5FF).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.6))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.face_rounded, color: Color(0xFF00E5FF), size: 14),
      const SizedBox(width: 6),
      Text('$count face${count == 1 ? '' : 's'} detected',
          style: const TextStyle(color: Color(0xFF00E5FF),
              fontSize: 12, fontWeight: FontWeight.w600)),
    ]));
}

class _TopBarButton extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  final bool disabled; final String? tooltip;
  const _TopBarButton({required this.icon, required this.onTap,
      this.disabled = false, this.tooltip});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: disabled ? null : onTap,
    child: Container(width: 42, height: 42,
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.45),
          shape: BoxShape.circle),
      child: Icon(icon,
          color: disabled ? Colors.white30 : Colors.white, size: 22)));
}
