import 'package:facial_attendance/bloc/attendance_bloc.dart';
import 'package:facial_attendance/bloc/attendance_event.dart';
import 'package:facial_attendance/bloc/attendance_state.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/verify_face.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class AttendanceScreen extends StatefulWidget {
  final FaceEmbeddingService embeddingService;

  const AttendanceScreen({super.key, required this.embeddingService});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  String message = "Mark your attendance";


  // Future<void> markAttendance() async {
  //   final result = await Navigator.pushNamed(context, "/camera");
  //
  //   if (result == null) return;
  //
  //   final imagePath = result as String;
  //
  //   // Let Bloc handle everything
  //   context.read<AttendanceBloc>().add(MarkAttendanceEvent(imagePath));
  // }
  Future<void> markAttendance() async {
    try {
      // Use this safer way
      final result = await Navigator.of(context, rootNavigator: true)
          .pushNamed("/camera");

      if (result == null) return;

      final imagePath = result as String;

      // Send to Bloc
      if (mounted) {
        context.read<AttendanceBloc>().add(MarkAttendanceEvent(imagePath));
      }
    } catch (e) {
      print("Navigation Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Cannot open camera. Try again.")),
        );
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,                    // Prevent default back behavior
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text("Attendance")),
        body: Center(
          child: BlocConsumer<AttendanceBloc,AttendanceState>(

          listener: (context, state) {
            if (state is AttendanceSuccess) {
              setState(() => message = "✅ Attendance Marked Successfully");
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("✅ Attendance Marked!")),
              );
            } else if (state is AttendanceFailure) {
              setState(() => message = "❌ Face Not Matched");
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("❌ Face not recognized")),
              );
            }
          },
          builder: (context, state) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(message, style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: markAttendance,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Scan Face"),
                ),
                if (state is AttendanceLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
              ],
            );
          },
        ),
      ),
    ),
    );
  }
}