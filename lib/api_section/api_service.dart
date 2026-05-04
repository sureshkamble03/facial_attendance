import 'dart:io';

import 'package:http/http.dart' as http;

class ApiService {
  final baseUrl = "https://your-api.com";

  Future<bool> verifyFace(File image) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/verify-face'),
    );

    request.files.add(
      await http.MultipartFile.fromPath('image', image.path),
    );

    final response = await request.send();
    return response.statusCode == 200;
  }
}