import 'dart:io';
import 'package:facial_attendance/common_files/colors.dart';
import 'package:facial_attendance/screens/group_attendance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/users_bloc.dart';
import '../bloc/users_event.dart';
import '../bloc/users_state.dart';
import '../local_database/app_database.dart';
import '../main.dart';
import 'admin_zones_screen.dart';
import 'attendance_log.dart';
import 'embeding_test_screen_from_url.dart';
import 'group_photo_attendance.dart';
import 'new_attendance_screen.dart';

class UsersList extends StatefulWidget {
  const UsersList({super.key});

  @override
  State<UsersList> createState() => _UsersListState();
}

class _UsersListState extends State<UsersList> {
  final scrollController = ScrollController();

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

  void _refreshAttendanceList() =>
      context.read<UsersBloc>().add(FetchUsersEvent());

  // ── Attendance dialog ──────────────────────────────────────────
  Future<void> _showAttendanceDialog() async {
    final String? choice = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_rounded, size: 48, color: AppColors.primary),
              const SizedBox(height: 12),
              const Text('Mark Attendance',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Choose attendance mode:',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              _AttendanceOption(
                icon: Icons.person_rounded,
                label: 'Single Person',
                color: AppColors.primary,
                onTap: () => Navigator.pop(ctx, 'single'),
              ),
              const SizedBox(height: 12),
              _AttendanceOption(
                icon: Icons.groups_rounded,
                label: 'Group Attendance',
                color: AppColors.accent,
                onTap: () => Navigator.pop(ctx, 'group'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;

    final db = getIt<AppDatabase>();

    if (choice == 'single') {
      final result = await Navigator.push<FaceScanAttendanceResult?>(
        context,
        MaterialPageRoute(builder: (_) => ScanCameraScreen(db: db)),
      );
      if (!mounted || result == null) return;
      _showResultSnack(
        result.success ? '✅ ${result.user!.name} marked present' : result.message,
        result.success ? Colors.green : Colors.orange,
      );
      if (result.success) _refreshAttendanceList();
    } else {
      final rawResult = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GroupScanCameraScreen(db: db)),
      );
      if (!mounted || rawResult == null) return;
      if (rawResult is List<FaceScanAttendanceResult>) {
        final success = rawResult.where((r) => r.success).length;
        _showResultSnack(
          '$success / ${rawResult.length} attendances marked',
          success > 0 ? Colors.green : Colors.orange,
        );
        _refreshAttendanceList();
      }
    }
  }

  void _showResultSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Delete confirm ─────────────────────────────────────────────
  Future<void> _deleteUserWithConfirm(int userId, String userName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.deleteRed.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_rounded,
                    color: AppColors.deleteRed, size: 36),
              ),
              const SizedBox(height: 16),
              const Text('Delete User',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to delete\n"$userName"?',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.deleteRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true) {
      await getIt<AppDatabase>().deleteUser(userId);
      _showResultSnack('User "$userName" deleted', Colors.red.shade400);
      _refreshAttendanceList();
    }
  }

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(),
      body: BlocBuilder<UsersBloc, UsersState>(
        builder: (context, state) {
          if (state.users.isEmpty) return _buildEmptyState();

          return ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: state.users.length + 1,
            itemBuilder: (context, index) {
              if (index < state.users.length) {
                return _UserCard(
                  user: state.users[index],
                  onDelete: () => _deleteUserWithConfirm(
                    state.users[index].id,
                    state.users[index].name,
                  ),
                );
              }
              return state.hasMore
                  ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
                  : const SizedBox(height: 20);
            },
          );
        },
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Users',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
          Text('Registered Members',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (value) {
            switch (value) {
              case 'register':
                Navigator.pushNamed(context, "/register");
                break;
              case 'logs':
                Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) =>
                            AttendanceLogsScreen(db: getIt<AppDatabase>())));
                break;
              case 'group':
                Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => GroupPhotoAttendanceScreen(
                            db: getIt<AppDatabase>())));
                break;
              case 'test':
                Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) =>
                            EmbeddingTestScreen(db: getIt<AppDatabase>())));
                break;
              case 'zones':
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminZonesScreen(),
                  ),
                );
                break;
              case 'refresh':
                _refreshAttendanceList();
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'register',
                child: _MenuRow(Icons.person_add_rounded, 'Register User')),
            PopupMenuItem(value: 'logs',
                child: _MenuRow(Icons.history_rounded, 'Attendance Logs')),
            PopupMenuItem(value: 'test',
                child: _MenuRow(Icons.science_rounded, 'Embedding Test')),
            PopupMenuItem(value: 'group',
                child: _MenuRow(Icons.photo_library_rounded, 'Photo Attendance')),
            PopupMenuItem(value: 'zones',
              child: _MenuRow(Icons.location_on_rounded, 'Manage Zones'),
            ),
            PopupMenuDivider(),
            PopupMenuItem(value: 'refresh',
                child: _MenuRow(Icons.refresh_rounded, 'Refresh')),
          ],
        ),
      ],
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: _showAttendanceDialog,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 4,
      icon: const Icon(Icons.camera_alt_rounded),
      label: const Text('Mark Attendance',
          style: TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline_rounded, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No users registered',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Tap the menu to register a new user',
              style: TextStyle(color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}

// ── User Card ──────────────────────────────────────────────────────────────────
class _UserCard extends StatelessWidget {
  final dynamic user;
  final VoidCallback onDelete;

  const _UserCard({required this.user, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: _Avatar(imagePath: user.faceImagePath, name: user.name),
        title: Text(
          user.name,
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Icon(Icons.email_outlined, size: 13, color: Colors.grey),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  user.email,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (value) {
            if (value == 'delete') onDelete();
          },
          itemBuilder: (_) => [
            // const PopupMenuItem(
            //   value: 'view',
            //   child: _MenuRow(Icons.visibility_rounded, 'View Profile'),
            // ),
            // const PopupMenuItem(
            //   value: 'edit',
            //   child: _MenuRow(Icons.edit_rounded, 'Edit User'),
            // ),
            // const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: _MenuRow(Icons.delete_rounded, 'Delete User',
                  color: Color(0xFFD32F2F)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Avatar ─────────────────────────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String? imagePath;
  final String name;

  const _Avatar({this.imagePath, required this.name});

  @override
  Widget build(BuildContext context) {
    if (imagePath != null) {
      return CircleAvatar(
        radius: 26,
        backgroundImage: FileImage(File(imagePath!)),
      );
    }
    return CircleAvatar(
      radius: 26,
      backgroundColor: const Color(0xFF1A73E8).withOpacity(0.15),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
            color: Color(0xFF1A73E8),
            fontWeight: FontWeight.bold,
            fontSize: 18),
      ),
    );
  }
}

// ── Attendance Mode Option ─────────────────────────────────────────────────────
class _AttendanceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttendanceOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 15)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}

// ── Popup Menu Row ─────────────────────────────────────────────────────────────
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MenuRow(this.icon, this.label,
      {this.color = const Color(0xFF333333)});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color, fontSize: 14)),
      ],
    );
  }
}