import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:facial_attendance/bloc/auth_event.dart';
import 'package:facial_attendance/bloc/auth_state.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/local_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../local_database/app_database.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final FaceService faceService;
  final LocalStorage storage;
  final AppDatabase db;

  AuthBloc(this.faceService, this.storage,this.db) : super(AuthInitial()) {

    on<LoginEvent>((event, emit) async {
      emit(AuthLoading());
      await Future.delayed(const Duration(seconds: 1));
      emit(AuthSuccess());
    });

    on<RegisterEvent>((event, emit) async {
      emit(AuthLoading());

      try {
        await db.insertUser(UsersCompanion.insert(
          name: event.name,
          email: event.email,
          password: event.password,
          role: event.role,
          embedding: Value(jsonEncode(event.imagePath)),
          faceImagePath: Value(event.faceImagePath),
          rollNumber: Value(event.rollNumber??''),
          employeeId: Value(event.employeeId??''),
          department: Value(event.department??''),
          phone: Value(event.phone??''),
          isFaceRegistered: Value(true)
        )
        );
        debugPrint('✅ BLoC: embedding saved → length: ${event.imagePath.length}');
        emit(AuthSuccess());

      } catch (e) {
        debugPrint('❌ BLoC: registration failed → $e');
        emit(AuthError('Registration failed: $e'));
      }
    });
  }
}