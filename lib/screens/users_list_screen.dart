import 'dart:io';
import 'package:facial_attendance/screens/group_attendance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/users_bloc.dart';
import '../bloc/users_event.dart';
import '../bloc/users_state.dart';
import '../local_database/app_database.dart';
import '../main.dart';
import 'attendance_log.dart';
import 'new_attendance_screen.dart';

class UsersList extends StatefulWidget {
  const UsersList({super.key});

  @override
  State<UsersList> createState() => _UsersListState();
}

class _UsersListState extends State<UsersList> {
  final scrollController = ScrollController();
  final AppDatabase db = AppDatabase();

  @override
  void initState() {
    super.initState();

    context.read<UsersBloc>().add(FetchUsersEvent());

    scrollController.addListener(() {
      if (scrollController.position.pixels ==
          scrollController.position.maxScrollExtent) {
        context.read<UsersBloc>().add(LoadMoreUsersEvent());
      }
    });
  }

  _refreshAttendanceList(){
    context.read<UsersBloc>().add(FetchUsersEvent());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Users List'),
        actions: [
        IconButton(onPressed: (){
          Navigator.pushNamed(context, "/register");
        }, icon: Icon(Icons.add_circle_outline)),
          IconButton(onPressed: (){
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AttendanceLogsScreen(db:db),
              ),
            );
           // Navigator.pushNamed(context, "/attendanceReport");
          }, icon: Icon(Icons.list)),
          ElevatedButton(
            onPressed: () async {
              // Show dialog with two options
              final String? choice = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Mark Attendance'),
                  content: const Text('Choose attendance mode:'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'single'),
                      child: const Text('Single Person'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'group'),
                      child: const Text('Group Attendance'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              );

              if (choice == null) return; // User cancelled

              final db = getIt<AppDatabase>();

              if (choice == 'single') {
                // Navigate to Single Face Scan
                final result = await Navigator.push<FaceScanAttendanceResult?>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScanCameraScreen(
                      sessionId: 1, // Replace with actual sessionId
                      db: db,
                    ),
                  ),
                );

                if (!mounted || result == null) return;

                if (result.success && result.user != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ ${result.user!.name} marked present'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _refreshAttendanceList();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.message),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              }
              else if (choice == 'group') {
                // Navigate to Group Scan
                final rawResult = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupScanCameraScreen(
                      sessionId: 1, // Replace with actual sessionId
                      db: db,
                    ),
                  ),
                );

                if (!mounted || rawResult == null) return;

                if (rawResult is List<FaceScanAttendanceResult>) {
                  final results = rawResult;
                  final successCount = results.where((r) => r.success).length;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '$successCount out of ${results.length} attendances marked successfully',
                      ),
                      backgroundColor: successCount > 0 ? Colors.green : Colors.orange,
                    ),
                  );
                  _refreshAttendanceList();
                }
              }
            },
            child: const Text('Mark Attendance'),
          ),
          /*ElevatedButton(onPressed: () async {

            final dynamic rawResult = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GroupScanCameraScreen(
                  sessionId: 1,   // or your sessionId
                  db:getIt<AppDatabase>(),
                ),
              ),
            );

            if (rawResult != null) {
              if (rawResult is List<FaceScanAttendanceResult>) {
                final results = rawResult;
                int successCount = results.where((r) => r.success).length;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '$successCount out of ${results.length} attendances marked successfully',
                    ),
                    backgroundColor: successCount > 0 ? Colors.green : Colors.orange,
                  ),
                );

                // Optional: Refresh attendance list
                setState(() {});
              }
              else if (rawResult is FaceScanAttendanceResult) {
                if (rawResult.success) {
                  // result.user has full user data — name, email, role, rollNumber, dept
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ ${rawResult.user?.name} marked present'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _refreshAttendanceList();
                }
              }
            }

          *//*  // No userId needed — user is identified from face scan automatically
            final result = await Navigator.push<FaceScanAttendanceResult>(
              context,
              // MaterialPageRoute(
              //   builder: (_) => ScanCameraScreen(
              //     sessionId: 1,
              //     db: getIt<AppDatabase>(),
              //   ),
              // ),
              MaterialPageRoute(
                builder: (_) => GroupScanCameraScreen(
                  sessionId: 1,
                  db: getIt<AppDatabase>(),
                ),
              ),
            );

            if (!mounted || result == null) return;
            if (result is List<FaceScanAttendanceResult>) {
              final results = result as List<FaceScanAttendanceResult>;

              int successCount = results.where((r) => r.success).length;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$successCount/${results.length} attendances marked successfully'),
                  backgroundColor: successCount > 0 ? Colors.green : Colors.orange,
                ),
              );
              _refreshAttendanceList();

            }*//*
            // if (result.success) {
            //   // result.user has full user data — name, email, role, rollNumber, dept
            //   ScaffoldMessenger.of(context).showSnackBar(
            //     SnackBar(
            //       content: Text('✅ ${result.user?.name} marked present'),
            //       backgroundColor: Colors.green,
            //     ),
            //   );
            //   _refreshAttendanceList();
            // }
          }, child: Text('Attendance'))*/
        ],
      ),
      body: BlocBuilder<UsersBloc, UsersState>(
        builder: (context, state) {
          return ListView.builder(
            controller: scrollController,
            itemCount: state.users.length + 1,
            itemBuilder: (context, index) {
              if (index < state.users.length) {
                final user = state.users[index];

                return ListTile(
                  leading: user.faceImagePath != null
                      ? Image.file(File(user.faceImagePath!), width: 40)
                      : const Icon(Icons.person),

                  title: Text(user.name),
                  subtitle: Text(user.email),
                  trailing: IconButton(onPressed: (){
                    _deleteUserWithConfirm(user.id,user.name);
                  }, icon: Icon(Icons.delete)),
                );
              } else {
                return state.hasMore
                    ? const Center(child: CircularProgressIndicator())
                    : const SizedBox();
              }
            },
          );
        },
      )
    );
  }

  Future<void> _deleteUserWithConfirm(int userId, String userName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Are you sure you want to delete "$userName"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await db.deleteUser(userId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User deleted successfully')),
      );
      // Refresh list
      _refreshAttendanceList();
    }
  }
}
