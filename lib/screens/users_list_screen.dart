import 'dart:io';
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
          ElevatedButton(onPressed: () async {
            // No userId needed — user is identified from face scan automatically
            final result = await Navigator.push<FaceScanAttendanceResult>(
              context,
              MaterialPageRoute(
                builder: (_) => ScanCameraScreen(
                  sessionId: 1,
                  db: getIt<AppDatabase>(),
                ),
              ),
            );

            if (!mounted || result == null) return;

            if (result.success) {
              // result.user has full user data — name, email, role, rollNumber, dept
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ ${result.user?.name} marked present'),
                  backgroundColor: Colors.green,
                ),
              );
              _refreshAttendanceList();
            }
          }, child: Text('Attendance'))
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
