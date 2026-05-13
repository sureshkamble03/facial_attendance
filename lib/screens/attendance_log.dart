import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:facial_attendance/local_database/app_database.dart';
import 'package:intl/intl.dart';

import '../common_files/colors.dart';

class AttendanceLogsScreen extends StatefulWidget {
  final AppDatabase db;

  const AttendanceLogsScreen({super.key, required this.db});

  @override
  State<AttendanceLogsScreen> createState() => _AttendanceLogsScreenState();
}

class _AttendanceLogsScreenState extends State<AttendanceLogsScreen> {
  List<AttendanceRecordWithUser> _records = [];
  bool _isLoading = true;
  bool _isDeleting = false;
  int? _deletedCount;
  // Filters
  DateTime? _selectedDate;
  String? _selectedRole; // "student", "teacher", "staff", etc.

  final List<String> _roles = ['All', 'student', 'teacher'];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadAttendanceLogs();
  }

  Future<void> _loadAttendanceLogs() async {
    setState(() => _isLoading = true);

    try {
      final attendance = widget.db.attendanceRecords;
      final users = widget.db.users;

      final query = widget.db.select(attendance).join([
        innerJoin(users, users.id.equalsExp(attendance.userId)),
      ]);

      // ── Date Filter ─────────────────────────────────────
      if (_selectedDate != null) {
        final start = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
        );

        final end = start.add(const Duration(days: 1));

        query.where(
          attendance.markedDate.isBiggerOrEqualValue(start) &
          attendance.markedDate.isSmallerThanValue(end),
        );
      }
      //
      // ── Role Filter ─────────────────────────────────────
      if (_selectedRole != null && _selectedRole != 'All') {
        query.where(users.role.equals(_selectedRole!));
      }
      //
      // ── Ordering ────────────────────────────────────────
      query.orderBy([
        OrderingTerm.desc(attendance.markedDate),
        OrderingTerm.desc(attendance.id),
      ]);

      final results = await query.get();

      final recordsWithUser = results.map((row) {
        return AttendanceRecordWithUser(
          record: row.readTable(attendance),
          user: row.readTable(users),
        );
      }).toList();

      setState(() {
        _records = recordsWithUser;
      });
    } catch (e) {
      debugPrint('Error loading attendance logs: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load attendance logs')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadAttendanceLogs();
    }
  }

  Future<void> _deleteTodaysLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Today\'s Attendance?'),
        content: const Text(
          'This action will delete ALL attendance records marked today.\n\n'
              'This cannot be undone. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);

    try {
      final count = await widget.db.deleteTodaysAttendance();

      setState(() => _deletedCount = count);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count records deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadAttendanceLogs();
      }
    } catch (e) {
      debugPrint('Delete error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete records')),
        );
      }
    } finally {
      setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Logs'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAttendanceLogs,
          ),
          IconButton(onPressed: _isDeleting ? null : _deleteTodaysLogs, icon: const Icon(Icons.delete))
        ],
      ),
      body: Column(
        children: [
          // Filters
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)
              ],
            ),
            child: Column(
              children: [
                // Date Filter
                Row(
                  children: [
                    const Text("Date:", style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 20),
                        label: Text(
                          _selectedDate == null
                              ? "All Dates"
                              : DateFormat('dd MMM yyyy').format(_selectedDate!),
                        ),
                        onPressed: _pickDate,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    if (_selectedDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() => _selectedDate = null);
                          _loadAttendanceLogs();
                        },
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // Role Filter
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _roles.map((role) {
                      final isSelected = _selectedRole == role || (_selectedRole == null && role == 'All');
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(role.toUpperCase()),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              _selectedRole = role == 'All' ? null : role;
                            });
                            _loadAttendanceLogs();
                          },
                          backgroundColor: Colors.grey.shade100,
                          selectedColor: Colors.blue.shade100,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // Results Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${_records.length} records found",
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  _selectedDate != null
                      ? DateFormat('dd MMM yyyy').format(_selectedDate!)
                      : "All Dates",
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 60, color: Colors.grey),
                  SizedBox(height: 12),
                  Text("No attendance records found",
                      style: TextStyle(fontSize: 16)),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _records.length,
              itemBuilder: (context, index) {
                final item = _records[index];
                return _buildAttendanceCard(item);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard(AttendanceRecordWithUser item) {
    final record = item.record;
    final user = item.user;

    final color = record.status == 'present' ? Colors.green : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: color.withOpacity(0.1),
              child: Icon(
                user.role == 'student' ? Icons.school : Icons.person,
                color: color,
                size: 32,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          user.role.toUpperCase(),
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    user.email ?? user.rollNumber ?? '',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.pin_drop, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(
                        record.zoneName??'NA',
                        style: TextStyle(fontWeight: FontWeight.w500,color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(
                        record.markedAt,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      if (record.similarityScore != null)
                        Text(
                          "${(record.similarityScore! * 100).toStringAsFixed(0)}% match",
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Helper Model
class AttendanceRecordWithUser {
  final AttendanceRecord record;
  final User user;

  AttendanceRecordWithUser({required this.record, required this.user});
}