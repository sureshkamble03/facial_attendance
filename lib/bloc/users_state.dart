import '../local_database/app_database.dart';

class UsersState {
  final List<User> users;
  final bool hasMore;
  final bool isLoading;

  UsersState({
    required this.users,
    required this.hasMore,
    required this.isLoading,
  });

  UsersState copyWith({
    List<User>? users,
    bool? hasMore,
    bool? isLoading,
  }) {
    return UsersState(
      users: users ?? this.users,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}