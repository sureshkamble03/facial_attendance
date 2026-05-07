import 'package:facial_attendance/local_database/app_database.dart';


class UserWithEmbedding {
  final User user;
  final List<double>? embedding;   // Face embedding vector

  UserWithEmbedding({
    required this.user,
    this.embedding,
  });

  // Optional: Helper getter
  int get id => user.id;
  String get name => user.name;
  String get email => user.email;
  String? get rollNumber => user.rollNumber;
  String? get department => user.department;
  String? get role => user.role;
}