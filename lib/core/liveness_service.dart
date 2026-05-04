import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class LivenessService {
  bool blinkDetected = false;
  // bool smileDetected = false;
  // bool headTurnDetected = false;

  void reset() {
    blinkDetected = false;
    // smileDetected = false;
    // headTurnDetected = false;
  }

  void processFace(Face face) {
    // 👁️ Blink detection
    if (face.leftEyeOpenProbability != null &&
        face.rightEyeOpenProbability != null) {
      if (face.leftEyeOpenProbability! < 0.4 &&
          face.rightEyeOpenProbability! < 0.4) {
        blinkDetected = true;
      }
    }

    // 😊 Smile detection
    // if (face.smilingProbability != null &&
    //     face.smilingProbability! > 0.7) {
    //   smileDetected = true;
    // }

    // 🔄 Head turn detection
    // if (face.headEulerAngleY != null) {
    //   if (face.headEulerAngleY!.abs() > 15) {
    //     headTurnDetected = true;
    //   }
    // }
  }

  bool isLivenessPassed() {
    return blinkDetected; //&& smileDetected && headTurnDetected;
  }
}