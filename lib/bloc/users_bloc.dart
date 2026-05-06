import 'package:facial_attendance/bloc/users_event.dart';
import 'package:facial_attendance/bloc/users_state.dart';
import 'package:facial_attendance/local_database/app_database.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class UsersBloc extends Bloc<UsersEvent, UsersState> {
  final AppDatabase usersDao;

  static const int pageSize = 10;
  int offset = 0;

  UsersBloc(this.usersDao)
      : super(UsersState(users: [], hasMore: true, isLoading: false)) {

    on<FetchUsersEvent>((event, emit) async {
      emit(state.copyWith(isLoading: true));

      offset = 0;

      final users = await usersDao.getUsersPaginated(
        limit: pageSize,
        offset: offset,
      );

      emit(UsersState(
        users: users,
        hasMore: users.length == pageSize,
        isLoading: false,
      ));
    });

    on<LoadMoreUsersEvent>((event, emit) async {
      if (!state.hasMore || state.isLoading) return;

      emit(state.copyWith(isLoading: true));

      offset += pageSize;

      final moreUsers = await usersDao.getUsersPaginated(
        limit: pageSize,
        offset: offset,
      );

      emit(state.copyWith(
        users: [...state.users, ...moreUsers],
        hasMore: moreUsers.length == pageSize,
        isLoading: false,
      ));
    });
  }
}