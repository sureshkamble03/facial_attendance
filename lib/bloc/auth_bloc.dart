import 'package:facial_attendance/bloc/auth_event.dart';
import 'package:facial_attendance/bloc/auth_state.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/local_storage.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final FaceService faceService;
  final LocalStorage storage;

  AuthBloc(this.faceService, this.storage) : super(AuthInitial()) {

    on<LoginEvent>((event, emit) async {
      emit(AuthLoading());
      await Future.delayed(const Duration(seconds: 1));
      emit(AuthSuccess());
    });

    on<RegisterEvent>((event, emit) async {
      emit(AuthLoading());

      final face = await faceService.detectSingleFace(event.imagePath);

      if (face == null) {
        emit(AuthError("No face detected"));
        return;
      }

      final features = faceService.extractFeatures(face);
      await storage.saveEmbedding(features);

      emit(AuthSuccess());
    });
  }
}