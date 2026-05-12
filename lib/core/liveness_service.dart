import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// class LivenessService {
//   bool blinkDetected = false;
//   // bool smileDetected = false;
//   // bool headTurnDetected = false;
//
//   void reset() {
//     blinkDetected = false;
//     // smileDetected = false;
//     // headTurnDetected = false;
//   }
//
//   void processFace(Face face) {
//     // 👁️ Blink detection
//     if (face.leftEyeOpenProbability != null &&
//         face.rightEyeOpenProbability != null) {
//       if (face.leftEyeOpenProbability! < 0.4 &&
//           face.rightEyeOpenProbability! < 0.4) {
//         blinkDetected = true;
//       }
//     }
//
//     // 😊 Smile detection
//     // if (face.smilingProbability != null &&
//     //     face.smilingProbability! > 0.7) {
//     //   smileDetected = true;
//     // }
//
//     // 🔄 Head turn detection
//     // if (face.headEulerAngleY != null) {
//     //   if (face.headEulerAngleY!.abs() > 15) {
//     //     headTurnDetected = true;
//     //   }
//     // }
//   }
//
//   bool isLivenessPassed() {
//     return blinkDetected; //&& smileDetected && headTurnDetected;
//   }
// }

enum LivenessChallenge { blink, turnLeft, turnRight, smile, nodUp, nodDown }

extension LivenessChallengeX on LivenessChallenge {
  String get instruction => switch (this) {
    LivenessChallenge.blink     => 'Slowly blink your eyes',
    LivenessChallenge.turnLeft  => 'Turn your head LEFT',
    LivenessChallenge.turnRight => 'Turn your head RIGHT',
    LivenessChallenge.smile     => 'Give a big smile 😄',
    LivenessChallenge.nodUp     => 'Look UP slowly',
    LivenessChallenge.nodDown   => 'Look DOWN slowly',
  };

  String get label => switch (this) {
    LivenessChallenge.blink     => 'Blink',
    LivenessChallenge.turnLeft  => 'Turn Left',
    LivenessChallenge.turnRight => 'Turn Right',
    LivenessChallenge.smile     => 'Smile',
    LivenessChallenge.nodUp     => 'Nod Up',
    LivenessChallenge.nodDown   => 'Nod Down',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// LivenessService
// ─────────────────────────────────────────────────────────────────────────────
class LivenessService {

  // ── Challenge state ───────────────────────────────────────────────────────
  late LivenessChallenge _challenge1;
  late LivenessChallenge _challenge2;
  bool _challenge1Passed = false;
  bool _challenge2Passed = false;

  // ── Layer 3: Motion consistency ───────────────────────────────────────────
  final List<double> _yawHistory  = [];
  final List<double> _pitchHistory = [];
  static const int   _historySize  = 40;   // ~1.3 s at 30 fps
  static const double _minMotionRange = 1.2;  // real face micro-tremor floor
  static const double _maxJumpPerFrame = 30.0; // loop-reset spike threshold

  int  _loopJumpCount = 0;
  static const int _maxAllowedJumps = 2;

  // ── Layer 4: Depth jitter (inter-frame landmark delta) ────────────────────
  double? _prevLeftEye;
  double? _prevRightEye;
  int _microMovementCount = 0;
  static const int _microMovementTarget = 6;

  // ── Layer 2: Screen/texture detection ─────────────────────────────────────
  bool _screenDetected       = false;
  int  _screenFrameCount     = 0;
  static const int _screenFrameLimit = 5; // must fail N frames in a row

  // ── Spoof feedback ────────────────────────────────────────────────────────
  String? _spoofReason;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Call once at the start of each attendance session.
  void reset() {
    _pickChallenges();
    _challenge1Passed = false;
    _challenge2Passed = false;

    _yawHistory.clear();
    _pitchHistory.clear();
    _loopJumpCount    = 0;

    _prevLeftEye  = null;
    _prevRightEye = null;
    _microMovementCount = 0;

    _screenDetected   = false;
    _screenFrameCount = 0;
    _spoofReason      = null;

    debugPrint('🎯 Liveness challenges: '
        '${_challenge1.label} → ${_challenge2.label}');
  }

  // ── Layer 2: call with every raw CameraImage frame ────────────────────────
  /// Returns false + sets [spoofReason] if this frame looks like a screen.
  bool analyzeFrame(CameraImage image) {
    final variance = _computeVariance(image);
    debugPrint('📊 Frame variance: ${variance.toStringAsFixed(1)}');

    if (variance < 180) {
      // Could be a flat photo/screen — require several consecutive failures
      _screenFrameCount++;
      if (_screenFrameCount >= _screenFrameLimit) {
        _screenDetected = true;
        _spoofReason = 'Screen or photo detected — please use your real face';
        return false;
      }
    } else {
      // Reset streak if texture looks real
      _screenFrameCount = (_screenFrameCount - 1).clamp(0, _screenFrameLimit);
    }
    return true;
  }

  /// Call with the detected [Face] every frame (after [analyzeFrame] passes).
  void processFace(Face face) {
    if (_screenDetected) return;

    // ── Layer 3: motion consistency ──────────────────────────────────────
    final yaw   = face.headEulerAngleY ?? 0.0;
    final pitch = face.headEulerAngleX ?? 0.0;

    if (_yawHistory.isNotEmpty) {
      final delta = (yaw - _yawHistory.last).abs();
      if (delta > _maxJumpPerFrame) {
        _loopJumpCount++;
        debugPrint('⚠️ Loop jump detected ($delta°), count: $_loopJumpCount');
        if (_loopJumpCount >= _maxAllowedJumps) {
          _spoofReason = 'Video loop detected — please use your real face';
          return;
        }
      }
    }

    _yawHistory.add(yaw);
    _pitchHistory.add(pitch);
    if (_yawHistory.length  > _historySize) _yawHistory.removeAt(0);
    if (_pitchHistory.length > _historySize) _pitchHistory.removeAt(0);

    // ── Layer 4: micro-movement / depth jitter ───────────────────────────
    final leftEyeY  = face.landmarks[FaceLandmarkType.leftEye]?.position.y.toDouble();
    final rightEyeY = face.landmarks[FaceLandmarkType.rightEye]?.position.y.toDouble();

    if (leftEyeY != null && rightEyeY != null) {
      if (_prevLeftEye != null && _prevRightEye != null) {
        final leftDelta  = (leftEyeY  - _prevLeftEye! ).abs();
        final rightDelta = (rightEyeY - _prevRightEye!).abs();
        // Real faces always have tiny natural movement (0.5–4 px per frame)
        if (leftDelta > 0.3 && leftDelta < 12 &&
            rightDelta > 0.3 && rightDelta < 12) {
          _microMovementCount++;
        }
      }
      _prevLeftEye  = leftEyeY;
      _prevRightEye = rightEyeY;
    }

    // ── Layer 1: challenge checks ────────────────────────────────────────
    if (!_challenge1Passed) {
      if (_checkChallenge(_challenge1, face)) {
        _challenge1Passed = true;
        debugPrint('✅ Challenge 1 passed: ${_challenge1.label}');
      }
    } else if (!_challenge2Passed) {
      if (_checkChallenge(_challenge2, face)) {
        _challenge2Passed = true;
        debugPrint('✅ Challenge 2 passed: ${_challenge2.label}');
      }
    }
  }

  /// True when ALL layers pass.
  bool isLivenessPassed() {
    if (_screenDetected)            return false;
    if (_spoofReason != null)       return false;
    if (!_challenge1Passed)         return false;
    if (!_challenge2Passed)         return false;
    if (!_hasNaturalMotion)         return false;
    if (!_hasSufficientMicroMovement) return false;
    return true;
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  /// Human-readable instruction for the current step.
  String get currentInstruction {
    if (_screenDetected)         return '⚠️ Screen detected — use your real face';
    if (_spoofReason != null)    return '⚠️ Liveness check failed';
    if (!_challenge1Passed)      return _challenge1.instruction;
    if (!_challenge2Passed)      return _challenge2.instruction;
    if (!_hasNaturalMotion)      return 'Move your head slightly';
    if (!_hasSufficientMicroMovement) return 'Hold still naturally...';
    return 'Scanning...';
  }

  LivenessChallenge get challenge1 => _challenge1;
  LivenessChallenge get challenge2 => _challenge2;
  bool get challenge1Passed => _challenge1Passed;
  bool get challenge2Passed => _challenge2Passed;
  String? get spoofReason   => _spoofReason;

  /// Progress 0.0 – 1.0 for a smooth progress indicator.
  double get progress {
    double p = 0;
    if (_challenge1Passed) p += 0.4;
    if (_challenge2Passed) p += 0.4;
    if (_hasNaturalMotion) p += 0.1;
    if (_hasSufficientMicroMovement) p += 0.1;
    return p;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _pickChallenges() {
    final pool = List<LivenessChallenge>.from(LivenessChallenge.values)
      ..shuffle(Random());
    _challenge1 = pool[0];
    _challenge2 = pool[1];
    // Ensure both challenges are different
    while (_challenge2 == _challenge1) {
      pool.shuffle(Random());
      _challenge2 = pool[1];
    }
  }

  bool _checkChallenge(LivenessChallenge c, Face face) => switch (c) {
    LivenessChallenge.blink =>
    (face.leftEyeOpenProbability  ?? 1.0) < 0.25 &&
        (face.rightEyeOpenProbability ?? 1.0) < 0.25,
    LivenessChallenge.turnLeft  => (face.headEulerAngleY ?? 0) < -20,
    LivenessChallenge.turnRight => (face.headEulerAngleY ?? 0) >  20,
    LivenessChallenge.smile     => (face.smilingProbability ?? 0) > 0.78,
    LivenessChallenge.nodUp     => (face.headEulerAngleX ?? 0) >  18,
    LivenessChallenge.nodDown   => (face.headEulerAngleX ?? 0) < -18,
  };

  bool get _hasNaturalMotion {
    if (_yawHistory.length < 20) return true; // not enough data yet
    final minY = _yawHistory.reduce(min);
    final maxY = _yawHistory.reduce(max);
    // Real face: always some micro-tremor > 1.2° over 40 frames
    // Looping video: either perfectly still OR has sudden large jumps
    return (maxY - minY) >= _minMotionRange;
  }

  bool get _hasSufficientMicroMovement =>
      _microMovementCount >= _microMovementTarget;

  /// Compute brightness variance of Y-plane pixels (NV21 format).
  /// Low variance = flat uniform surface (screen, photo, card).
  double _computeVariance(CameraImage image) {
    try {
      final yPlane = image.planes[0].bytes;
      const sampleStep = 6; // sample every 6th pixel for speed

      double sum   = 0;
      double sumSq = 0;
      int    count = 0;

      for (int i = 0; i < yPlane.length; i += sampleStep) {
        final v = yPlane[i].toDouble();
        sum   += v;
        sumSq += v * v;
        count++;
      }

      if (count == 0) return 9999;
      final mean = sum / count;
      return (sumSq / count) - (mean * mean);
    } catch (e) {
      return 9999; // if we can't compute, don't block
    }
  }
}