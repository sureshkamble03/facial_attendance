import 'package:facial_attendance/common_widgets/common_appbar.dart';
import 'package:facial_attendance/local_database/app_database.dart';
import 'package:facial_attendance/screens/attendance_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  List<AttendanceRecord> records = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAttendanceRecords();
  }

  Future<void> _loadAttendanceRecords() async {
    final db = context.read<AppDatabase>(); // or inject your database

    try {
      final data = await db.getStudentAttendance(1,1);
      setState(() {
        records = data;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading data: $e")),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(preferredSize: Size.fromHeight(50), child: CommonAppbar(title: 'Attendance Report')),
      backgroundColor: Colors.white,
      body: Column(
        children: [
           AttendanceTable(records: records),
        ],
      ),
    );
  }
}
