
import 'package:facial_attendance/api_section/api_service.dart';
import 'package:facial_attendance/bloc/attendance_bloc.dart';
import 'package:facial_attendance/bloc/auth_bloc.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/face_service.dart';
import 'package:facial_attendance/core/local_storage.dart';
import 'package:facial_attendance/screens/attendance_screen.dart';
import 'package:facial_attendance/screens/camera_screen.dart';
import 'package:facial_attendance/screens/login_screen.dart';
import 'package:facial_attendance/screens/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() async{
  WidgetsFlutterBinding.ensureInitialized();

  final embeddingService = FaceEmbeddingService();
  await embeddingService.loadModel();
  runApp(MyApp(embeddingService));
}

class MyApp extends StatelessWidget {
  final FaceEmbeddingService embeddingService;

  MyApp(this.embeddingService,{super.key});

  final apiService = ApiService();
  final facialService = FaceService();
  final localStorage = LocalStorage();

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    // final mediaQuery = MediaQuery.of(context);

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
            FaceEmbeddingService()
          ),
        ),
      ],
      child: MaterialApp(
        routes: {
          "/": (_) => LoginScreen(),
          "/register": (_) => RegisterScreen(embeddingService: embeddingService,),
          "/attendance": (_) => AttendanceScreen(embeddingService: embeddingService,),
          "/camera": (_) => CameraScreen(),
        },
      ),
    );
  }
}