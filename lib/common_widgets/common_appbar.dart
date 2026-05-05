import 'package:facial_attendance/common_files/colors.dart';
import 'package:flutter/material.dart';

class CommonAppbar extends StatelessWidget {
  final String title;
  final String? username;
  final String? iconPath;
  final String? suffixPath;
  final VoidCallback? onButtonPressed;
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;

  final bool showMenu; // ✅ whether to show menu or back arrow

  const CommonAppbar({
    super.key,
    required this.title,
    this.username,
    this.iconPath,
    this.suffixPath,
    this.onButtonPressed,
    this.onBackPressed,
    this.actions,
    this.showMenu = false, // default to back arrow
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.primary,
      ),
      padding: EdgeInsets.all(14),
      child: Column(
        children: [
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(3.0),
                      child: InkWell(
                          onTap: () {
                            if (showMenu) {
                              // ✅ open the drawer
                              onButtonPressed?.call();
                            } else {
                              // ✅ back navigation
                              onBackPressed?.call();
                            }
                          },
                          child:showMenu?Image.asset('assets/images/hamberger.png',height: 20,width: 20,):
                          Icon(Icons.arrow_back,color: Colors.white,)
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
             /* CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white,
                child: Image.asset(
                  'assets/images/tvu_logo.png',
                  height: 30,
                ),
              ),*/
            ],
          ),
        ],
      ),
    );
  }
}
