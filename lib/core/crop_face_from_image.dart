import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart';

Future<Uint8List> cropFaceFromImage(File imageFile, Rect box) async {
  final bytes = await imageFile.readAsBytes();
  final img = decodeImage(bytes)!;

  // Add some padding
  final padding = (box.width * 0.1).toInt();
  final left = (box.left - padding).clamp(0, img.width).toInt();
  final top = (box.top - padding).clamp(0, img.height).toInt();
  final width = (box.width + padding * 2).clamp(0, img.width - left).toInt();
  final height = (box.height + padding * 2).clamp(0, img.height - top).toInt();

  final cropped = copyCrop(img, x: left, y: top, width: width, height: height);
  return encodeJpg(cropped);
}