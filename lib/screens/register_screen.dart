import 'dart:io';

import 'package:facial_attendance/bloc/auth_bloc.dart';
import 'package:facial_attendance/bloc/auth_event.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image/image.dart' as img;

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

  String? faceImagePath;

  Future<void> captureFace() async {

    final result = await Navigator.pushNamed(context, "/camera");

    if (result != null) {
      setState(() {
        faceImagePath = result as String;
      });
    }
  }

  void register() async {
    if (faceImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture face')),
      );
      return;
    }

    // Step 1 — decode image
    final file = File(faceImagePath!);
    final bytes = await file.readAsBytes();
    final img.Image? image = img.decodeImage(bytes);
    if (image == null) {
      debugPrint('❌ Failed to decode image');
      return;
    }

    // Step 2 — detect face and crop it first
    // ✅ Always crop before embedding — raw image gives bad results
    final face = await FaceService().detectSingleFace(faceImagePath!);
    if (face == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No face detected. Please retake photo')),
      );
      return;
    }

    final cropped = await FaceService().cropFace(faceImagePath!, face);
    if (cropped == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Face crop failed. Please retake photo')),
      );
      return;
    }

    // Step 3 — generate 192-value embedding from CROPPED face
    final embedding = await widget.embeddingService.getEmbedding(cropped);
    debugPrint('✅ Registration embedding length: ${embedding.length}');

    if (embedding.length != 192) {
      debugPrint('❌ Wrong embedding size: ${embedding.length}');
      return;
    }

    // Step 4 — pass embedding to bloc
    context.read<AuthBloc>().add(
      RegisterEvent(
        nameController.text,
        emailController.text,
        passwordController.text,
        embedding, // ← 192 values passed here
      ),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register")),
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
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password"),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: captureFace,
              child: const Text("Capture Face"),
            ),

            if (faceImagePath != null)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Image.file(
                  File(faceImagePath!),
                  height: 150,
                ),
              ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: register,
              child: const Text("Register"),
            ),
          ],
        ),
      ),
    );
  }
}