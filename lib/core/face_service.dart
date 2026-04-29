import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

class FaceService {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(enableContours: true,enableClassification: true,enableTracking: true),
  );

  Future<Face?> detectSingleFace(String path) async {
    final inputImage = InputImage.fromFilePath(path);
    final faces = await _detector.processImage(inputImage);
    if (faces.isEmpty) return null;
    return faces.first;
  }

  List<double> extractFeatures(Face face) {
    return [
      face.headEulerAngleY ?? 0,
      face.headEulerAngleZ ?? 0,
      face.boundingBox.width,
      face.boundingBox.height,
    ];
  }

  double compare(List<double> f1, List<double> f2) {
    double sum = 0;
    for (int i = 0; i < f1.length; i++) {
      sum += (f1[i] - f2[i]) * (f1[i] - f2[i]);
    }
    return sum;
  }

  Future<img.Image?> cropFace(String path, Face face) async {
    final image = img.decodeImage(await File(path).readAsBytes());

    if (image == null) return null;

    final rect = face.boundingBox;

    final x = rect.left.toInt().clamp(0, image.width - 1);
    final y = rect.top.toInt().clamp(0, image.height - 1);
    final w = rect.width.toInt().clamp(0, image.width - x);
    final h = rect.height.toInt().clamp(0, image.height - y);

    return img.copyCrop(
      image,
      x: x,
      y: y,
      width: w,
      height: h,
    );
  }
}