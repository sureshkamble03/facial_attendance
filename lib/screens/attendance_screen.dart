import 'package:facial_attendance/bloc/attendance_bloc.dart';
import 'package:facial_attendance/bloc/attendance_event.dart';
import 'package:facial_attendance/bloc/attendance_state.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:facial_attendance/core/verify_face.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AttendanceScreen extends StatefulWidget {
  final FaceEmbeddingService embeddingService;

  const AttendanceScreen({super.key, required this.embeddingService});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  String message = "Mark your attendance";


  Future<void> markAttendance() async {
    final result = await Navigator.pushNamed(context, "/camera");

    if (result == null) return;

    final imagePath = result as String;

    bool isMatch = await verifyFace(
      imagePath,
      widget.embeddingService,
    );

    setState(() {
      message = isMatch
          ? "✅ Attendance Marked"
          : "❌ Face Not Matched";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Attendance")),
      body: Center(
        child: BlocConsumer<AttendanceBloc,AttendanceState>(

          listener: (context, state) {
            if (state is AttendanceSuccess) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text("✅ Attendance Marked")));
            } else if (state is AttendanceFailure) {

              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text("❌ Failed")));
            }
          },
          builder: (context, state) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(message, style: const TextStyle(fontSize: 18)),

                const SizedBox(height: 20),

                ElevatedButton.icon(
                  onPressed: () async {
                    final path = await Navigator.pushNamed(context, "/camera");

                    if (path != null) {
                      context.read<AttendanceBloc>().add(
                        MarkAttendanceEvent(path as String),
                      );
                    }
                    bool isMatch = await verifyFace(path.toString(),widget.embeddingService); // replace with actual logic

                    setState(() {
                      message = isMatch
                          ? "✅ Attendance Marked"
                          : "❌ Face Not Matched";
                    });
                  },


                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Scan Face"),
                )
              ],
            );
          },
        ),
      ),
    );
  }
}