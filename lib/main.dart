import 'package:facial_attendance/api_section/api_service.dart';
import 'package:facial_attendance/bloc/attendance_bloc.dart';
import 'package:facial_attendance/bloc/auth_bloc.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/local_storage.dart';
import 'package:facial_attendance/screens/attendance_report_screen.dart';
import 'package:facial_attendance/screens/attendance_screen.dart';
import 'package:facial_attendance/screens/camera_screen.dart';
import 'package:facial_attendance/screens/dashboard.dart';
import 'package:facial_attendance/screens/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final embeddingService = FaceEmbeddingService();
  await embeddingService.loadModel();

  runApp(MyApp(embeddingService));
}

class MyApp extends StatelessWidget {
  final FaceEmbeddingService embeddingService;

  const MyApp(this.embeddingService, {super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => AuthBloc(FaceService(), LocalStorage()),
        ),
        BlocProvider(
          create: (_) => AttendanceBloc(
            FaceService(),
            LocalStorage(),
            ApiService(),
            FaceEmbeddingService(), // Better to pass the same instance if possible
          ),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        initialRoute: "/",
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case "/":
              return MaterialPageRoute(builder: (_) => const Dashboard());

            case "/register":
              return MaterialPageRoute(
                builder: (_) => RegisterScreen(embeddingService: embeddingService),
              );

            case "/attendance":
              return MaterialPageRoute(
                builder: (_) => AttendanceScreen(embeddingService: embeddingService),
              );

            case "/attendance_report":
              return MaterialPageRoute(builder: (_) => const AttendanceReportScreen());

            case "/camera":
              return MaterialPageRoute(builder: (_) => const CameraScreen());

            default:
              return MaterialPageRoute(builder: (_) => const Dashboard());
          }
        },
      ),
    );
  }
}