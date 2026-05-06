abstract class AuthEvent {}

class LoginEvent extends AuthEvent {
  final String email;
  final String password;

  LoginEvent(this.email, this.password);
}

class RegisterEvent extends AuthEvent {
  final String name;
  final String email;
  final String password;
  final List<double> imagePath;
  final String role;
  final String? rollNumber;
  final String? employeeId;
  final String? department;
  final String? phone;
  final String faceImagePath;

  RegisterEvent(this.name, this.email, this.password, this.imagePath,this.faceImagePath,{
    required this.role,
    this.rollNumber,
    this.employeeId,
    this.department,
    this.phone,
  });
}