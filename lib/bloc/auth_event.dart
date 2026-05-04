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

  RegisterEvent(this.name, this.email, this.password, this.imagePath);
}