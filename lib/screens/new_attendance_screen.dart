import 'package:camera/camera.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/geo_fence_service.dart';
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
  int  _selectedCameraIndex = 0;
  bool _isSwitching = false;

  // ── Services ──────────────────────────────────────────────────────────────
  final LivenessService      _liveness    = LivenessService();
  final FaceEmbeddingService _embedding   = FaceEmbeddingService();
  final FaceService          _faceService = FaceService();
  final GeoFenceService      _geoService  = GeoFenceService();

  // ── Geo ───────────────────────────────────────────────────────────────────
  String         _geoStatus = 'checking'; // 'checking' | 'allowed' | 'denied'
  GeoCheckResult? _geoResult;

  // ── Scan state ────────────────────────────────────────────────────────────
  bool _isProcessing = false;
  bool _isCapturing  = false;
  bool _cameraReady  = false;
  bool _showResult   = false;
  bool _isSuccess    = false;
  FaceScanAttendanceResult? _attendanceResult;

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
    _liveness.reset();
    _verifyLocation(); // location gate — camera starts only if this passes
  }

  @override
  void dispose() {
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
            (c) => c.lensDirection == CameraLensDirection.front);
        if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;
      } else {
        _selectedCameraIndex = cameraIndex;
      }

      await _controller?.dispose();
      _controller = CameraController(_allCameras[_selectedCameraIndex],
          ResolutionPreset.medium, enableAudio: false,
          imageFormatGroup: ImageFormatGroup.nv21);
      await _controller!.initialize();
      if (!mounted) return;
      setState(() { _cameraReady = true; _isSwitching = false; });
      _controller!.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrint('❌ Camera error: $e');
      _popWithResult(null);
    }
  }

  Future<void> _flipCamera() async {
    if (_isSwitching || _allCameras.length < 2 || _isCapturing) return;
    setState(() { _isSwitching = true; _cameraReady = false; });
    _flipAnim.forward(from: 0);
    try { await _controller?.stopImageStream(); } catch (_) {}
    _liveness.reset();
    await _initCamera(cameraIndex: (_selectedCameraIndex + 1) % _allCameras.length);
  }

  // ── Frame pipeline ────────────────────────────────────────────────────────

  Future<void> _onCameraFrame(CameraImage image) async {
    if (_isProcessing || _isCapturing) return;
    _isProcessing = true;
    try {
      if (!_liveness.analyzeFrame(image)) { if (mounted) setState(() {}); return; }
      final faces = await _detectFaces(image, _allCameras[_selectedCameraIndex]);
      if (faces.isEmpty) { if (mounted) setState(() {}); return; }
      _liveness.processFace(faces.first);
      if (mounted) setState(() {});
      if (_liveness.spoofReason != null) return;
      if (_liveness.isLivenessPassed()) {
        _isCapturing = true;
        if (mounted) setState(() {});
        await _controller!.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 300));
        final file = await _controller!.takePicture();
        await _runAttendance(file.path);
      }
    } catch (e) { debugPrint('❌ Frame error: $e'); }
    finally { _isProcessing = false; }
  }

  Future<void> _runAttendance(String imagePath) async {
    final result = await widget.db.markAttendanceByFaceScan(
      imagePath: imagePath,
      embeddingService: _embedding,
      faceService: _faceService,
      geoLatitude:  _geoResult?.latitude,
      geoLongitude: _geoResult?.longitude,
      zoneName:     _geoResult?.matchedZoneName,
    );
    if (!mounted) return;
    setState(() {
      _showResult = true; _isSuccess = result.success;
      _attendanceResult = result;
    });
    await Future.delayed(const Duration(seconds: 3));
    _popWithResult(result);
  }

  Future<List<Face>> _detectFaces(CameraImage image,
      CameraDescription camera) async {
    try {
      final WriteBuffer buf = WriteBuffer();
      for (final p in image.planes) buf.putUint8List(p.bytes);
      final rot = InputImageRotationValue.fromRawValue(camera.sensorOrientation)
          ?? InputImageRotation.rotation0deg;
      final fmt = InputImageFormatValue.fromRawValue(image.format.raw)
          ?? InputImageFormat.nv21;
      return await _faceDetector.processImage(InputImage.fromBytes(
        bytes: buf.done().buffer.asUint8List(),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rot, format: fmt,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      ));
    } catch (_) { return []; }
  }

  void _popWithResult(FaceScanAttendanceResult? r) {
    if (mounted) Navigator.pop(context, r);
  }

  bool get _isFrontCamera => _allCameras.isNotEmpty &&
      _allCameras[_selectedCameraIndex].lensDirection ==
          CameraLensDirection.front;

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
          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13)),
      const SizedBox(height: 28),
      const CircularProgressIndicator(color: Color(0xFF1A73E8), strokeWidth: 3),
    ])),
  );

  Widget _geoDeniedView() => Container(
    color: const Color(0xFF0A1628),
    child: SafeArea(child: Column(children: [
      // Back button
      Align(alignment: Alignment.centerLeft,
        child: Padding(padding: const EdgeInsets.all(16),
          child: GestureDetector(onTap: () => Navigator.pop(context),
            child: Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle),
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
          ]),
        ),
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
            ),
          ))),
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

    return Stack(fit: StackFit.expand, children: [
      CameraPreview(_controller!),
      Container(color: Colors.black.withOpacity(0.25)),

      // Zone badge
      if (_geoResult?.matchedZoneName != null)
        Positioned(top: 100, left: 0, right: 0,
          child: Center(child: _ZoneBadge(
              zoneName: _geoResult!.matchedZoneName!))),

      // Oval
      Center(child: Container(width: 240, height: 300,
        decoration: BoxDecoration(
          border: Border.all(
            color: _showResult ? (_isSuccess ? Colors.green : Colors.red)
                : _liveness.spoofReason != null ? Colors.redAccent
                : Colors.white70,
            width: 3),
          borderRadius: BorderRadius.circular(150)))),

      // Top bar
      Positioned(top: 0, left: 0, right: 0,
        child: SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            _TopBarButton(icon: Icons.arrow_back_ios_rounded,
                onTap: () => _popWithResult(null)),
            const Expanded(child: Text('Mark Attendance',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.w600))),
            AnimatedBuilder(animation: _flipAnim,
              builder: (_, __) => Transform(alignment: Alignment.center,
                transform: Matrix4.rotationY(_flipAnim.value * 3.14159),
                child: _TopBarButton(icon: Icons.flip_camera_ios_rounded,
                    onTap: _flipCamera,
                    disabled: _isSwitching || _isCapturing))),
          ])))),

      if (_showResult && _attendanceResult != null)
        _resultOverlay(_attendanceResult!),

      if (!_showResult)
        Positioned(bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Colors.black.withOpacity(0.90), Colors.transparent])),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ClipRRect(borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: _liveness.progress,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation(
                    _liveness.spoofReason != null
                        ? Colors.red : Colors.greenAccent),
                  minHeight: 6)),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _ChallengeChip(label: _liveness.challenge1.label,
                    done: _liveness.challenge1Passed,
                    active: !_liveness.challenge1Passed),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward_ios,
                    color: Colors.white38, size: 12),
                const SizedBox(width: 10),
                _ChallengeChip(label: _liveness.challenge2.label,
                    done: _liveness.challenge2Passed,
                    active: _liveness.challenge1Passed &&
                        !_liveness.challenge2Passed),
              ]),
              const SizedBox(height: 14),
              Text(_isCapturing ? 'Scanning...' : _liveness.currentInstruction,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _liveness.spoofReason != null
                        ? Colors.redAccent : Colors.white,
                    fontSize: 18, fontWeight: FontWeight.w600)),
              if (_liveness.spoofReason != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () { _liveness.reset(); setState(() {}); },
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text('Try Again',
                      style: TextStyle(color: Colors.white))),
              ],
            ]))),
    ]);
  }

  Widget _resultOverlay(FaceScanAttendanceResult result) => Container(
    color: Colors.black.withOpacity(0.65),
    child: Center(child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.3), blurRadius: 20)]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 72, height: 72,
          decoration: BoxDecoration(
            color: result.success ? Colors.green.withOpacity(0.1)
                : Colors.red.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(result.success ? Icons.check_circle : Icons.cancel,
              color: result.success ? Colors.green : Colors.red, size: 48)),
        const SizedBox(height: 16),
        Text(result.success ? 'Attendance Marked!' : 'Failed',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                color: result.success ? Colors.green : Colors.red)),
        if (_geoResult?.matchedZoneName != null) ...[
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.location_on_rounded, size: 13, color: Colors.grey),
            const SizedBox(width: 4),
            Text(_geoResult!.matchedZoneName!,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ],
        if (result.success && result.user != null) ...[
          const Divider(height: 24),
          _row(Icons.person_rounded, 'Name', result.user!.name),
          const SizedBox(height: 8),
          _row(Icons.email_rounded, 'Email', result.user!.email),
          const Divider(height: 24),
          _simBar(result.similarity),
        ],
        if (!result.success) ...[
          const SizedBox(height: 4),
          Text(result.message, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14,
                  color: Colors.black54, height: 1.5)),
        ],
      ]))),
  );

  Widget _row(IconData icon, String label, String value) =>
      Row(children: [
        Icon(icon, size: 18, color: Colors.grey), const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontSize: 13,
            color: Colors.grey, fontWeight: FontWeight.w500)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w600, color: Colors.black87),
            overflow: TextOverflow.ellipsis)),
      ]);

  Widget _simBar(double sim) {
    final c = sim >= 0.75 ? Colors.green : sim >= 0.65 ? Colors.orange : Colors.red;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Match confidence',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        Text('${(sim * 100).toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: sim.clamp(0.0, 1.0),
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(c), minHeight: 8)),
    ]);
  }
}

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

class _TopBarButton extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  final bool disabled; final String? tooltip;
  const _TopBarButton({required this.icon, required this.onTap,
      this.disabled = false, this.tooltip});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: disabled ? null : onTap,
    child: Container(width: 42, height: 42,
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.45),
          shape: BoxShape.circle),
      child: Icon(icon, color: disabled ? Colors.white30 : Colors.white,
          size: 22)));
}

class _ChallengeChip extends StatelessWidget {
  final String label; final bool done; final bool active;
  const _ChallengeChip({required this.label, required this.done,
      required this.active});
  @override
  Widget build(BuildContext context) {
    final bg = done ? Colors.green.withOpacity(0.2)
        : active ? Colors.white.withOpacity(0.15)
        : Colors.white.withOpacity(0.06);
    final border = done ? Colors.green : active ? Colors.white54 : Colors.white24;
    return AnimatedContainer(duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? Colors.green : active ? Colors.white70 : Colors.white30,
            size: 14),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(
            color: done ? Colors.green : active ? Colors.white : Colors.white38,
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
      ]));
  }
}
