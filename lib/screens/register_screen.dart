import 'dart:io';

import 'package:facial_attendance/bloc/auth_bloc.dart';
import 'package:facial_attendance/bloc/auth_event.dart';
import 'package:facial_attendance/bloc/auth_state.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../core/face_service.dart';

class RegisterScreen extends StatefulWidget {
  final FaceEmbeddingService embeddingService;

  const RegisterScreen({super.key, required this.embeddingService});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final rollNumberController = TextEditingController();
  final employeeIdController = TextEditingController();
  final departmentController = TextEditingController();
  final phoneController = TextEditingController();

  String selectedRole = "student"; // default
  String? faceImagePath;

  Future<void> captureFace() async {
    final result = await Navigator.pushNamed(context, "/camera");

    if (result != null) {
      setState(() {
        faceImagePath = result as String;
      });
    }
  }

  Future<String> compressAndSaveImage(String path) async {
    final dir = await getApplicationDocumentsDirectory();

    final targetPath =
        "${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg";

    final result = await FlutterImageCompress.compressAndGetFile(
      path,
      targetPath,
      quality: 70,
    );

    return result!.path;
  }

  void register() async {
    if (faceImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture face')),
      );
      return;
    }

    // 👉 Role validation
    if (selectedRole == "student" && rollNumberController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter Roll Number')),
      );
      return;
    }

    if (selectedRole == "teacher" && employeeIdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter Employee ID')),
      );
      return;
    }

    // -------- FACE PROCESSING (same as yours) --------
    final file = File(faceImagePath!);
    final compressedPath = await compressAndSaveImage(faceImagePath!);
    final bytes = await file.readAsBytes();
    final img.Image? image = img.decodeImage(bytes);
    if (image == null) return;

    final face = await FaceService().detectSingleFace(faceImagePath!);
    if (face == null) return;

    final cropped = await FaceService().cropFace(faceImagePath!, face);
    if (cropped == null) return;

    final embedding = await widget.embeddingService.getEmbedding(cropped);

    if (embedding!.length != 192) return;

    // -------- SEND TO BLOC --------
    context.read<AuthBloc>().add(
      RegisterEvent(
        nameController.text,
        emailController.text,
        passwordController.text,
        embedding,
        compressedPath,
        role: selectedRole,
        rollNumber: selectedRole == "student"
            ? rollNumberController.text
            : null,
        employeeId: selectedRole == "teacher"
            ? employeeIdController.text
            : null,
        department: departmentController.text,
        phone: phoneController.text,
      ),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthSuccess) {
          Navigator.pushNamed(context, "/userlist");
        }
      },
      child: Scaffold(
        appBar: AppBar(
            title: const Text("Register"),
          backgroundColor: Colors.blue.shade300,
          foregroundColor: Colors.white),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Name"),
              ),

              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: "Email"),
              ),

              // TextField(
              //   controller: passwordController,
              //   obscureText: true,
              //   decoration: const InputDecoration(labelText: "Password"),
              // ),

              const SizedBox(height: 10),

              // ✅ ROLE DROPDOWN
              DropdownButtonFormField<String>(
                value: selectedRole,
                items: const [
                  DropdownMenuItem(value: "student", child: Text("Student")),
                  DropdownMenuItem(value: "teacher", child: Text("Teacher")),
                ],
                onChanged: (value) {
                  setState(() {
                    selectedRole = value!;
                  });
                },
                decoration: const InputDecoration(labelText: "Role"),
              ),

              const SizedBox(height: 10),

              // ✅ CONDITIONAL FIELD
              if (selectedRole == "student")
                TextField(
                  controller: rollNumberController,
                  decoration: const InputDecoration(labelText: "Roll Number"),
                ),

              if (selectedRole == "teacher")
                TextField(
                  controller: employeeIdController,
                  decoration: const InputDecoration(labelText: "Employee ID"),
                ),

              // TextField(
              //   controller: departmentController,
              //   decoration: const InputDecoration(labelText: "Department"),
              // ),

              // TextField(
              //   controller: phoneController,
              //   keyboardType: TextInputType.phone,
              //   decoration: const InputDecoration(labelText: "Phone"),
              // ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: captureFace,
                child: const Text("Capture Face"),
              ),

              if (faceImagePath != null)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Image.file(File(faceImagePath!), height: 150),
                ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: register,
                child: const Text("Register"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}