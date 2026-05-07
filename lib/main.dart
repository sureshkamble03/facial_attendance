
import 'package:facial_attendance/api_section/api_service.dart';
import 'package:facial_attendance/bloc/attendance_bloc.dart';
import 'package:facial_attendance/bloc/auth_bloc.dart';
import 'package:facial_attendance/bloc/users_bloc.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/local_storage.dart';
import 'package:facial_attendance/screens/attendance_log.dart';
import 'package:facial_attendance/screens/attendance_screen.dart';
import 'package:facial_attendance/screens/camera_screen.dart';
import 'package:facial_attendance/screens/group_attendance_screen.dart';
import 'package:facial_attendance/screens/login_screen.dart';
import 'package:facial_attendance/screens/new_attendance_screen.dart';
import 'package:facial_attendance/screens/register_screen.dart';
import 'package:facial_attendance/screens/users_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'core/attendance_service.dart';
import 'local_database/app_database.dart';

final getIt = GetIt.instance;

Future<void> setupLocator() async {
  // Database — singleton
  getIt.registerSingleton<AppDatabase>(AppDatabase());

  // Embedding service — load model once
  final embeddingService = FaceEmbeddingService();
  await embeddingService.loadModel();
  getIt.registerSingleton<FaceEmbeddingService>(embeddingService);

  // Attendance service
  getIt.registerSingleton<AttendanceService>(
    AttendanceService(
      db: getIt<AppDatabase>(),
      embeddingService: getIt<FaceEmbeddingService>(),
    ),
  );
}

void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  await setupLocator();
 // final embeddingService = FaceEmbeddingService();
  // await embeddingService.loadModel();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {

  MyApp({super.key});

  final apiService = ApiService();
  final facialService = FaceService();
  final localStorage = LocalStorage();
  final db = AppDatabase();

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => AuthBloc(FaceService(), LocalStorage(),db),
        ),
        BlocProvider(
          create: (_) => AttendanceBloc(
            FaceService(),
            LocalStorage(),
            ApiService(),
            FaceEmbeddingService()
          ),
        ),
        BlocProvider(
          create: (_) => UsersBloc(db),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        routes: {
          "/": (_) => UsersList(),
          "/register": (_) => RegisterScreen(embeddingService: getIt<FaceEmbeddingService>(),),
          "/attendance": (_) => AttendanceScreen(embeddingService: getIt<FaceEmbeddingService>(),),
          "/camera": (_) => CameraScreen(),
          "/userlist": (_) => UsersList(),
          "/markattendance": (_) => ScanCameraScreen(sessionId: 1, db: getIt<AppDatabase>(),),
          "/mark_attendance_group": (_) => GroupScanCameraScreen(sessionId: 1, db: getIt<AppDatabase>(),),
          "/attendanceReport": (_) => AttendanceLogsScreen(db: getIt<AppDatabase>(),),
        },
      ),
    );
  }
}