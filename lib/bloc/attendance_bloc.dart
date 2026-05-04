
import 'package:facial_attendance/api_section/api_service.dart';
import 'package:facial_attendance/bloc/attendance_event.dart';
import 'package:facial_attendance/bloc/attendance_state.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/local_storage.dart';
import 'package:facial_attendance/core/verify_face.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AttendanceBloc extends Bloc<AttendanceEvent, AttendanceState> {
  final FaceService faceService;
  final FaceEmbeddingService embeddingService;
  final LocalStorage storage;
  final ApiService api;

  AttendanceBloc(this.faceService, this.storage, this.api,this.embeddingService)
      : super(AttendanceInitial()) {

   /* on<MarkAttendanceEvent>((event, emit) async {
      emit(AttendanceLoading());

      try {
        // Try API first
        // final apiResult = await api.verifyFace(File(event.imagePath));
        final isMatch = await verifyFace(event.imagePath,embeddingService);

        if (isMatch) {
          emit(AttendanceSuccess());
          return;
        }

        // Fallback offline
        final face = await faceService.detectSingleFace(event.imagePath);
        final saved = await storage.getEmbedding();

        if (face == null || saved == null) {
          emit(AttendanceFailure());
          return;
        }

        final newFeatures = faceService.extractFeatures(face);
        final score = faceService.compare(newFeatures, saved);
        // final isMatch = await verifyFace(event.imagePath);

        if (score < 50) {

          emit(AttendanceSuccess());
        } else {
          emit(AttendanceFailure());
        }

      } catch (_) {
        storage.clearEmbedding();
        emit(AttendanceFailure());
      }
    });*/

    on<MarkAttendanceEvent>((event, emit) async {
      emit(AttendanceLoading());

      try {
        final isMatch = await verifyFace(event.imagePath, embeddingService);

        if (isMatch) {
          emit(AttendanceSuccess());
        } else {
          emit(AttendanceFailure());
        }
      } catch (e) {
        print("Error in MarkAttendance: $e");
        emit(AttendanceFailure());
      }
    });
  }
}