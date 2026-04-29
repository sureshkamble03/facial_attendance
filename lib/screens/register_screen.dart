import 'dart:io';

import 'package:facial_attendance/bloc/auth_bloc.dart';
import 'package:facial_attendance/bloc/auth_event.dart';
import 'package:facial_attendance/core/embedding_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image/image.dart' as img;

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
        const SnackBar(content: Text("Please capture face")),
      );
      return;
    }

    // ✅ Convert file → bytes → image
    final file = File(faceImagePath!);
    final bytes = await file.readAsBytes();

    final img.Image? image = img.decodeImage(bytes);

    if (image == null) {
      print("❌ Failed to decode image");
      return;
    }

    // ✅ Now generate embedding
    final embedding =
    await widget.embeddingService.getEmbedding(image);

    print("Embedding length: ${embedding.length}");

    context.read<AuthBloc>().add(
      RegisterEvent(
        nameController.text,
        emailController.text,
        passwordController.text,
        faceImagePath!,
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