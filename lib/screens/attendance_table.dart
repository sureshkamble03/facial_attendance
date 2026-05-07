import 'package:facial_attendance/local_database/app_database.dart';
import 'package:flutter/material.dart';

class AttendanceTable extends StatelessWidget {
  final List<AttendanceRecord> records;
  const AttendanceTable({super.key, required this.records});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal, // For horizontal scrolling if needed
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.blueGrey[50]),
          dataRowHeight: 55,
          headingTextStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          columns: const [
            DataColumn(label: Text('ID')),
            DataColumn(label: Text('User ID')),
            DataColumn(label: Text('Role')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Created Time')),
            DataColumn(label: Text('Created Date')),
          ],
          rows: _createDummyData(),
          // rows: records.map((record) {
          //   final time = record.markedAt ?? '--:--';
          //   final date = record.createdAt != null
          //       ? "${record.createdAt!.day}/${record.createdAt!.month}/${record.createdAt!.year}"
          //       : '--';
          //
          //   Color statusColor = Colors.black;
          //   if (record.status.toLowerCase() == 'present') statusColor = Colors.green;
          //   if (record.status.toLowerCase() == 'late') statusColor = Colors.orange;
          //   if (record.status.toLowerCase() == 'absent') statusColor = Colors.red;
          //
          //   return DataRow(
          //     cells: [
          //       DataCell(Text(record.id.toString())),
          //       DataCell(Text("U${record.userId}")),
          //       DataCell(Text(record.role.toUpperCase())),
          //       DataCell(
          //         Text(
          //           record.status.toUpperCase(),
          //           style: TextStyle(
          //             color: statusColor,
          //             fontWeight: FontWeight.bold,
          //           ),
          //         ),
          //       ),
          //       DataCell(Text(time)),
          //       DataCell(Text(date)),
          //     ],
          //   );
          // }).toList(),
        ),
      ),
    );
  }

  List<DataRow> _createDummyData() {
    final dummyData = [
      {
        'id': '1',
        'userid': 'U1001',
        'role': 'Employee',
        'status': 'Present',
        'time': '09:15 AM',
        'date': '2026-05-04'
      },
      {
        'id': '2',
        'userid': 'U1002',
        'role': 'Manager',
        'status': 'Present',
        'time': '08:45 AM',
        'date': '2026-05-04'
      },
      {
        'id': '3',
        'userid': 'U1003',
        'role': 'Employee',
        'status': 'Late',
        'time': '10:05 AM',
        'date': '2026-05-04'
      },
      {
        'id': '4',
        'userid': 'U1004',
        'role': 'HR',
        'status': 'Absent',
        'time': '--',
        'date': '2026-05-04'
      },
      {
        'id': '5',
        'userid': 'U1005',
        'role': 'Employee',
        'status': 'Present',
        'time': '09:00 AM',
        'date': '2026-05-03'
      },
    ];

    return dummyData.map((data) {
      // Color coding for status
      Color statusColor = Colors.black;
      if (data['status'] == 'Present') statusColor = Colors.green;
      if (data['status'] == 'Late') statusColor = Colors.orange;
      if (data['status'] == 'Absent') statusColor = Colors.red;

      return DataRow(
        cells: [
          DataCell(Text(data['id']!)),
          DataCell(Text(data['userid']!)),
          DataCell(Text(data['role']!)),
          DataCell(
            Text(
              data['status']!,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          DataCell(Text(data['time']!)),
          DataCell(Text(data['date']!)),
        ],
      );
    }).toList();
  }
}