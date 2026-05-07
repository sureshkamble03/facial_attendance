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

// class GroupScanCameraScreen extends StatefulWidget {
//   final AppDatabase db;
//
//   const GroupScanCameraScreen({
//     super.key,
//     required this.db,
//   });
//
//   @override
//   State<GroupScanCameraScreen> createState() => _GroupScanCameraScreenState();
// }
//
// class _GroupScanCameraScreenState extends State<GroupScanCameraScreen> {
//   // ── Camera ────────────────────────────────────────────────────────────────
//   CameraController? _controller;
//   late CameraDescription _backCamera; // ✅ back camera for group
//
//   // ── Services ──────────────────────────────────────────────────────────────
//   final FaceEmbeddingService _embedding = FaceEmbeddingService();
//   final FaceService _faceService        = FaceService();
//
//   // ── State ─────────────────────────────────────────────────────────────────
//   bool _isProcessing  = false;
//   bool _isCapturing   = false;
//   bool _cameraReady   = false;
//   bool _showResult    = false;
//
//   // ── Stable frame detection ────────────────────────────────────────────────
//   // Wait for same face count across N frames before capturing
//   int _lastFaceCount     = 0;
//   int _stableFrameCount  = 0;
//   static const int _requiredStableFrames = 8; // ~8 frames at stable count
//
//   String _instruction = 'Position the group in front of camera';
//   int _detectedCount  = 0;
//   List<FaceScanAttendanceResult> _results = [];
//
//   // ── Use accurate mode + landmarks for better group detection ──────────────
//   final FaceDetector _faceDetector = FaceDetector(
//     options: FaceDetectorOptions(
//       enableContours: true,
//       enableClassification: true,
//       enableLandmarks: true,
//       enableTracking: true,
//       minFaceSize: 0.15,
//       // performanceMode: FaceDetectorMode.fast,
//       // minFaceSize: 0.10, // ✅ detect smaller faces (people farther away)
//     ),
//   );
//
//   @override
//   void initState() {
//     super.initState();
//     SystemChrome.setPreferredOrientations([
//       DeviceOrientation.portraitUp,
//       DeviceOrientation.landscapeLeft,
//       DeviceOrientation.landscapeRight,
//     ]);
//     _initCamera();
//   }
//
//   @override
//   void dispose() {
//     SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
//     _controller?.dispose();
//     _faceDetector.close();
//     _faceService.dispose();
//     super.dispose();
//   }
//
//   // ── Camera init ───────────────────────────────────────────────────────────
//   Future<void> _initCamera() async {
//     try {
//
//       await _embedding.loadModel();
//       debugPrint('✅ Model loaded');
//
//       final cameras = await availableCameras();
//
//       // ✅ Back camera — wider FOV, higher resolution, better for groups
//       _backCamera = cameras.firstWhere(
//             (c) => c.lensDirection == CameraLensDirection.back,
//         orElse: () => cameras.first,
//       );
//
//       _controller = CameraController(
//         _backCamera,
//         ResolutionPreset.veryHigh, // ✅ higher res = better face detection
//         enableAudio: false,
//         imageFormatGroup: ImageFormatGroup.nv21,
//       );
//
//       await _controller!.initialize();
//       if (!mounted) return;
//       await _controller!.lockCaptureOrientation();
//       // ✅ Lock focus and exposure for stable capture
//       ///commented for testing
//       // await _controller!.setFocusMode(FocusMode.auto);
//       // await _controller!.setExposureMode(ExposureMode.auto);
//
//       if (!mounted) return;
//       setState(() => _cameraReady = true);
//       _controller!.startImageStream(_onCameraFrame);
//     } catch (e) {
//       debugPrint('❌ Camera init error: $e');
//       if (mounted) Navigator.pop(context);
//     }
//   }
//
//   // ── Per-frame processing ──────────────────────────────────────────────────
//   Future<void> _onCameraFrame(CameraImage image) async {
//     if (_isProcessing || _isCapturing) return;
//     _isProcessing = true;
//
//     try {
//       final faces = await _detectFacesFromFrame(image, _backCamera);
//
//       if (faces.isEmpty) {
//         _stableFrameCount = 0;
//         _lastFaceCount    = 0;
//         _setInstruction('No faces detected — move closer');
//         return;
//       }
//
//       // ── Stability check — same count for N consecutive frames ─────────────
//       if (faces.length == _lastFaceCount) {
//         _stableFrameCount++;
//       } else {
//         // Face count changed — reset counter
//         _stableFrameCount = 0;
//         _lastFaceCount    = faces.length;
//       }
//
//       // Update UI with live count
//       if (mounted) {
//         setState(() => _detectedCount = faces.length);
//       }
//
//       final remaining = _requiredStableFrames - _stableFrameCount;
//       if (remaining > 0) {
//         _setInstruction(
//           '${faces.length} face(s) detected\n'
//               'Hold steady... ($remaining)',
//         );
//         return;
//       }
//
//       // ── Stable face count reached — capture ───────────────────────────────
//       _isCapturing = true;
//       _setInstruction('Capturing ${faces.length} faces...');
//
//       await _controller!.stopImageStream();
//       await Future.delayed(const Duration(milliseconds: 500));
//
//       final file = await _controller!.takePicture();
//       debugPrint('📸 Captured: ${file.path}');
//
//       await _processGroupPhoto(file.path, faces);
//     } catch (e) {
//       debugPrint('❌ Frame error: $e');
//     } finally {
//       _isProcessing = false;
//     }
//   }
//
//   // ── Process group photo ───────────────────────────────────────────────────
//   Future<void> _processGroupPhoto(String imagePath, List<Face> faces) async {
//     debugPrint('🔄 Processing ${faces.length} faces...');
//     _setInstruction('Processing ${faces.length} faces...');
//
//     try {
//       final results = await widget.db.markMultipleAttendanceByFaceScan(
//         imagePath: imagePath,
//         embeddingService: _embedding,
//         faceService: _faceService,
//       );
//
//       if (!mounted) return;
//
//       setState(() {
//         _showResult = true;
//         _results    = results;
//       });
//
//       debugPrint('✅ Done. Results: ${results.length}');
//
//       await Future.delayed(const Duration(seconds: 8));
//       if (mounted) _popWithResults();
//     } catch (e) {
//       debugPrint('❌ processGroupPhoto error: $e');
//       _setInstruction('Error processing. Please retry.');
//     }
//   }
//
//   void _popWithResults() {
//     if (!mounted) return;
//     Navigator.pop(context, _results);
//   }
//
//   // ── Face detection from camera frame ──────────────────────────────────────
//   Future<List<Face>> _detectFacesFromFrame(
//       CameraImage image,
//       CameraDescription camera,
//       ) async {
//     try {
//       final WriteBuffer allBytes = WriteBuffer();
//       for (final Plane plane in image.planes) {
//         allBytes.putUint8List(plane.bytes);
//       }
//
//       final rotation = InputImageRotationValue.fromRawValue(
//           camera.sensorOrientation) ??
//           InputImageRotation.rotation0deg;
//
//       final inputImage = InputImage.fromBytes(
//         bytes: allBytes.done().buffer.asUint8List(),
//         metadata: InputImageMetadata(
//           size: Size(image.width.toDouble(), image.height.toDouble()),
//           rotation: rotation,
//           format: InputImageFormat.nv21,
//           bytesPerRow: image.planes.first.bytesPerRow,
//         ),
//       );
//
//       return await _faceDetector.processImage(inputImage);
//     } catch (e) {
//       debugPrint('❌ Detection error: $e');
//       return [];
//     }
//   }
//
//   void _setInstruction(String text) {
//     if (!mounted) return;
//     setState(() => _instruction = text);
//   }
//
//   // ── Build ─────────────────────────────────────────────────────────────────
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: _cameraReady && _controller != null
//           ? _buildCameraView()
//           : _buildLoadingView(),
//     );
//   }
//
//   Widget _buildLoadingView() => const Center(
//     child: Column(
//       mainAxisAlignment: MainAxisAlignment.center,
//       children: [
//         CircularProgressIndicator(color: Colors.white),
//         SizedBox(height: 16),
//         Text('Starting camera...', style: TextStyle(color: Colors.white)),
//       ],
//     ),
//   );
//
//   Widget _buildCameraView() {
//     return Stack(
//       fit: StackFit.expand,
//       children: [
//         // ── Camera feed ───────────────────────────────────────────────────
//         CameraPreview(_controller!),
//         Container(color: Colors.black.withOpacity(0.25)),
//
//         // ── Group guide frame ─────────────────────────────────────────────
//         Center(
//           child: Container(
//             width: MediaQuery.of(context).size.width * 0.9,
//             height: MediaQuery.of(context).size.height * 0.55,
//             decoration: BoxDecoration(
//               border: Border.all(
//                 color: _showResult
//                     ? Colors.green
//                     : _detectedCount > 0
//                     ? Colors.blue
//                     : Colors.white54,
//                 width: 3,
//               ),
//               borderRadius: BorderRadius.circular(20),
//             ),
//             child: _detectedCount > 0 && !_showResult
//                 ? Align(
//               alignment: Alignment.topRight,
//               child: Container(
//                 margin: const EdgeInsets.all(8),
//                 padding: const EdgeInsets.symmetric(
//                     horizontal: 10, vertical: 4),
//                 decoration: BoxDecoration(
//                   color: Colors.blue,
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: Text(
//                   '$_detectedCount face(s)',
//                   style: const TextStyle(
//                     color: Colors.white,
//                     fontSize: 12,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//               ),
//             )
//                 : null,
//           ),
//         ),
//
//         // ── Top bar ───────────────────────────────────────────────────────
//         Positioned(
//           top: 0,
//           left: 0,
//           right: 0,
//           child: SafeArea(
//             child: Padding(
//               padding: const EdgeInsets.all(16),
//               child: Row(
//                 children: [
//                   IconButton(
//                     onPressed: () => Navigator.pop(context),
//                     icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
//                   ),
//                   const Expanded(
//                     child: Text(
//                       'Group Attendance',
//                       textAlign: TextAlign.center,
//                       style: TextStyle(
//                         color: Colors.white,
//                         fontSize: 20,
//                         fontWeight: FontWeight.w600,
//                       ),
//                     ),
//                   ),
//                   // ✅ Manual capture button
//                   IconButton(
//                     onPressed: _isCapturing ? null : _captureManually,
//                     icon: const Icon(Icons.camera_alt, color: Colors.white),
//                     tooltip: 'Capture now',
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ),
//
//         // ── Bottom instruction ─────────────────────────────────────────────
//         if (!_showResult)
//           Positioned(
//             bottom: 40,
//             left: 20,
//             right: 20,
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 // Stability progress bar
//                 if (_detectedCount > 0 && _stableFrameCount > 0)
//                   Column(
//                     children: [
//                       ClipRRect(
//                         borderRadius: BorderRadius.circular(4),
//                         child: LinearProgressIndicator(
//                           value: _stableFrameCount / _requiredStableFrames,
//                           backgroundColor: Colors.white24,
//                           valueColor: const AlwaysStoppedAnimation(Colors.blue),
//                           minHeight: 6,
//                         ),
//                       ),
//                       const SizedBox(height: 8),
//                     ],
//                   ),
//                 Container(
//                   padding: const EdgeInsets.symmetric(
//                       horizontal: 24, vertical: 12),
//                   decoration: BoxDecoration(
//                     color: Colors.black.withOpacity(0.75),
//                     borderRadius: BorderRadius.circular(30),
//                   ),
//                   child: Text(
//                     _instruction,
//                     style: const TextStyle(
//                       color: Colors.white,
//                       fontSize: 16,
//                       fontWeight: FontWeight.w500,
//                     ),
//                     textAlign: TextAlign.center,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//
//         // ── Result overlay ─────────────────────────────────────────────────
//         if (_showResult) _buildGroupResultOverlay(),
//       ],
//     );
//   }
//
//   // ── Manual capture ────────────────────────────────────────────────────────
//   Future<void> _captureManually() async {
//     if (_isCapturing || _controller == null) return;
//     _isCapturing = true;
//
//     try {
//       await _controller!.stopImageStream();
//       await Future.delayed(const Duration(milliseconds: 300));
//       final file = await _controller!.takePicture();
//       debugPrint('📸 Manual capture: ${file.path}');
//
//       // Detect faces on captured image directly
//       final faces = await _faceService.detectFaces(file.path);
//       debugPrint('🔍 Faces on manual capture: ${faces.length}');
//
//       if (faces.isEmpty) {
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(content: Text('No faces detected in photo')),
//           );
//         }
//         // Restart stream for retry
//         _isCapturing = false;
//         _controller!.startImageStream(_onCameraFrame);
//         return;
//       }
//
//       await _processGroupPhoto(file.path, faces);
//     } catch (e) {
//       debugPrint('❌ Manual capture error: $e');
//       _isCapturing = false;
//     }
//   }
//
//   // ── Result overlay ────────────────────────────────────────────────────────
//   Widget _buildGroupResultOverlay() {
//     final successList = _results.where((r) => r.success).toList();
//     final failedList  = _results.where((r) => !r.success).toList();
//
//     return Container(
//       color: Colors.black.withOpacity(0.88),
//       child: Center(
//         child: Container(
//           margin: const EdgeInsets.all(20),
//           padding: const EdgeInsets.all(20),
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(20),
//           ),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               // ── Summary row ──────────────────────────────────────────────
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                 children: [
//                   _summaryBadge(
//                     '${successList.length}',
//                     'Marked',
//                     Colors.green,
//                     Icons.check_circle,
//                   ),
//                   _summaryBadge(
//                     '${failedList.length}',
//                     'Failed',
//                     Colors.red,
//                     Icons.cancel,
//                   ),
//                   _summaryBadge(
//                     '${_results.length}',
//                     'Total',
//                     Colors.blue,
//                     Icons.groups,
//                   ),
//                 ],
//               ),
//               const Divider(height: 24),
//
//               // ── Result list ──────────────────────────────────────────────
//               SizedBox(
//                 height: 300,
//                 child: ListView.separated(
//                   shrinkWrap: true,
//                   itemCount: _results.length,
//                   separatorBuilder: (_, __) =>
//                   const Divider(height: 1),
//                   itemBuilder: (context, index) {
//                     final r = _results[index];
//                     return ListTile(
//                       dense: true,
//                       leading: CircleAvatar(
//                         radius: 18,
//                         backgroundColor: r.success
//                             ? Colors.green.shade50
//                             : Colors.red.shade50,
//                         child: Icon(
//                           r.success ? Icons.check : Icons.close,
//                           color: r.success ? Colors.green : Colors.red,
//                           size: 18,
//                         ),
//                       ),
//                       title: Text(
//                         r.user?.name ?? 'Unknown face ${index + 1}',
//                         style: const TextStyle(
//                             fontSize: 14, fontWeight: FontWeight.w600),
//                       ),
//                       subtitle: Text(
//                         r.message,
//                         style: TextStyle(
//                           fontSize: 12,
//                           color: r.success
//                               ? Colors.green.shade700
//                               : Colors.red.shade700,
//                         ),
//                       ),
//                       trailing: Column(
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: [
//                           Text(
//                             '${(r.similarity * 100).toStringAsFixed(1)}%',
//                             style: TextStyle(
//                               fontWeight: FontWeight.bold,
//                               fontSize: 13,
//                               color: r.success ? Colors.green : Colors.red,
//                             ),
//                           ),
//                           Text(
//                             r.user?.role ?? '',
//                             style: const TextStyle(
//                                 fontSize: 10, color: Colors.grey),
//                           ),
//                         ],
//                       ),
//                     );
//                   },
//                 ),
//               ),
//               const SizedBox(height: 12),
//               SizedBox(
//                 width: double.infinity,
//                 child: ElevatedButton.icon(
//                   onPressed: _popWithResults,
//                   icon: const Icon(Icons.check),
//                   label: const Text('Done'),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.deepPurple,
//                     foregroundColor: Colors.white,
//                     padding: const EdgeInsets.symmetric(vertical: 12),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget _summaryBadge(
//       String count,
//       String label,
//       Color color,
//       IconData icon,
//       ) =>
//       Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           CircleAvatar(
//             radius: 24,
//             backgroundColor: color.withOpacity(0.1),
//             child: Icon(icon, color: color, size: 22),
//           ),
//           const SizedBox(height: 4),
//           Text(
//             count,
//             style: TextStyle(
//               fontSize: 20,
//               fontWeight: FontWeight.bold,
//               color: color,
//             ),
//           ),
//           Text(label,
//               style: const TextStyle(fontSize: 12, color: Colors.grey)),
//         ],
//       );
// }

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

class _GroupScanCameraScreenState extends State<GroupScanCameraScreen> {

  CameraController? _controller;
  late CameraDescription _frontCamera;

  final LivenessService _liveness = LivenessService();
  final FaceEmbeddingService _embedding = FaceEmbeddingService();
  final FaceService _faceService = FaceService();

  bool _isProcessing = false;
  bool _isCapturing = false;
  bool _cameraReady = false;

  String _instruction = 'Stand in front of camera';
  bool _showResult = false;
  List<FaceScanAttendanceResult> _results = [];

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      minFaceSize: 0.15,           // Smaller = better for edges
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      await _embedding.loadModel();

      final cameras = await availableCameras();
      _frontCamera = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        _frontCamera,
        ResolutionPreset.high,           // Better quality
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _controller!.initialize();
      if (!mounted) return;

      // Important: Lock preview to current orientation
      await _controller!.lockCaptureOrientation();

      setState(() => _cameraReady = true);
      _controller!.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrint('❌ Camera init error: $e');
      Navigator.pop(context);
    }
  }

  Future<void> _onCameraFrame(CameraImage image) async {
    if (_isProcessing || _isCapturing) return;
    _isProcessing = true;

    try {
      final faces = await _detectFacesFromFrame(image, _frontCamera);

      if (faces.isEmpty) {
        _setInstruction(widget.isGroupMode
            ? 'Multiple people can stand anywhere in frame'
            : 'Position your face clearly');
        return;
      }

      _setInstruction('${faces.length} face(s) detected');

      if (faces.isNotEmpty) {
        _isCapturing = true;
        _setInstruction('Scanning ${faces.length} person(s)...');

        await _controller!.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 500));

        final file = await _controller!.takePicture();
        await _runGroupFaceScan(file.path, faces.length);
      }
    } catch (e) {
      debugPrint('❌ Frame error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // ── Improved Face Detection with Proper Rotation ─────────────────────
  Future<List<Face>> _detectFacesFromFrame(
      CameraImage image,
      CameraDescription camera,
      ) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }

      // ✅ Critical: Proper rotation handling
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

  // ✅ Better rotation logic
  InputImageRotation _getInputImageRotation(CameraDescription camera) {
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation rotation = InputImageRotation.rotation0deg;

    switch (sensorOrientation) {
      case 90:
        rotation = InputImageRotation.rotation90deg;
        break;
      case 180:
        rotation = InputImageRotation.rotation180deg;
        break;
      case 270:
        rotation = InputImageRotation.rotation270deg;
        break;
    }
    return rotation;
  }

  Future<void> _runGroupFaceScan(String imagePath, int detectedCount) async {
    final resultList = await widget.db.markMultipleAttendanceByFaceScan(
      imagePath: imagePath,
      embeddingService: _embedding,
      faceService: _faceService,
    );

    if (!mounted) return;

    setState(() {
      _showResult = true;
      _results = resultList;
    });

    await Future.delayed(const Duration(seconds: 5));
    if (mounted) Navigator.pop(context, _results);
  }

  // ... rest of your build methods ...

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _cameraReady && _controller != null
          ? _buildCameraView()
          : _buildLoadingView(),
    );
  }

  Widget _buildCameraView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Full screen camera preview
        CameraPreview(_controller!),

        Container(color: Colors.black.withOpacity(0.2)),

        // Removed fixed oval → Full screen detection
        if (!_showResult)
          Center(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 3),
                borderRadius: BorderRadius.circular(12),
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
                ],
              ),
            ),
          ),
        ),

        if (_showResult) _buildGroupResultOverlay(),

        if (!_showResult)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              _instruction,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
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
              // ── Summary row ──────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _summaryBadge(
                    '${successList.length}',
                    'Marked',
                    Colors.green,
                    Icons.check_circle,
                  ),
                  _summaryBadge(
                    '${failedList.length}',
                    'Failed',
                    Colors.red,
                    Icons.cancel,
                  ),
                  _summaryBadge(
                    '${_results.length}',
                    'Total',
                    Colors.blue,
                    Icons.groups,
                  ),
                ],
              ),
              const Divider(height: 24),

              // ── Result list ──────────────────────────────────────────────
              SizedBox(
                height: 300,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  separatorBuilder: (_, __) =>
                  const Divider(height: 1),
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
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
          Text(
            count,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      );

  void _popWithResults() {
    if (!mounted) return;
    Navigator.pop(context, _results);
  }
  void _setInstruction(String text) {
    if (!mounted) return;
    setState(() => _instruction = text);
  }


}