import 'package:facial_attendance/common_widgets/common_appbar.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:flutter/material.dart';

class Dashboard extends StatefulWidget {

  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50),
        child: CommonAppbar(title: 'Dashboard'),
      ),
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(child: GridView.count(crossAxisCount: 2,crossAxisSpacing: 16,mainAxisSpacing: 16,children: [
            _buildCard(
              context,
              title: "Register List",
              icon: Icons.list_alt,
              color: Colors.orange,
              onTap: () {
                Navigator.pushNamed(context, "/register");
              },
            ),
            _buildCard(
              context,
              title: "Attendance",
              icon: Icons.check_circle,
              color: Colors.green,
              onTap: () {
                // if(mounted){
                Navigator.pushNamed(context,"/attendance");
                // }
              },
            ),
            _buildCard(
              context,
              title: "Attendance Report",
              icon: Icons.bar_chart,
              color: Colors.blue,
              onTap: () {
                Navigator.pushNamed(context,"/attendance_report");
              },
            ),
          ],))
        ],
      ),
    );
  }

  Widget _buildCard(
      BuildContext context, {
        required String title,
        required IconData icon,
        required Color color,
        required VoidCallback onTap,
      }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: color.withOpacity(0.15),
                child: Icon(
                  icon,
                  size: 30,
                  color: color,
                ),
              ),
              const SizedBox(height: 15),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
