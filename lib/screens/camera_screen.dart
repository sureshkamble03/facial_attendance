import 'package:camera/camera.dart';
import 'package:facial_attendance/core/liveness_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  final liveness = LivenessService();
  bool _isProcessing = false;

  bool _isCapturing = false;
  String instruction = "Blink";

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
    ),
  );
  late CameraDescription frontCamera;

  void initCamera() async {
    final cameras = await availableCameras();
    frontCamera = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
    );

    controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
    );


    await controller!.initialize();

    controller!.startImageStream((image) async {
      if (_isProcessing || _isCapturing) return;

      _isProcessing = true;

      try {
        final faces = await detectFacesFromCamera(image, frontCamera);

        if (faces.isEmpty) return;

        liveness.processFace(faces.first);

        setState(() {
          instruction = getInstruction();
        });

        if (liveness.isLivenessPassed()) {
          _isCapturing = true;

          await controller!.stopImageStream(); // 🛑 VERY IMPORTANT
          await Future.delayed(Duration(milliseconds: 300));
          final file = await controller!.takePicture();

          if (!mounted) return;

          Navigator.pop(context, file.path);
        }

      } catch (e) {
        print("Camera error: $e");
      } finally {
        _isProcessing = false;
      }
    });

    setState(() {});
  }

  Future<List<Face>> detectFacesFromCamera(
      CameraImage image,
      CameraDescription camera,
      ) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();

      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }

      final bytes = allBytes.done().buffer.asUint8List();

      final imageSize = Size(
        image.width.toDouble(),
        image.height.toDouble(),
      );

      final rotation = InputImageRotationValue.fromRawValue(
        camera.sensorOrientation,
      ) ??
          InputImageRotation.rotation0deg;

      final format = InputImageFormatValue.fromRawValue(
        image.format.raw,
      ) ??
          InputImageFormat.nv21;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);

      return faces;
    } catch (e) {
      print("Face detection error: $e");
      return [];
    }
  }

  String getInstruction() {
    if (!liveness.blinkDetected) return "Blink";
    // if (!liveness.headTurnDetected) return "Turn Head";
    // if (!liveness.smileDetected) return "Smile";
    return "Capturing...";
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(controller!),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                instruction,
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}