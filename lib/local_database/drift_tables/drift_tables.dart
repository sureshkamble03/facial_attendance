
import 'package:drift/drift.dart';

// ─────────────────────────────────────────────────────────────────────────────
// USERS TABLE — stores both students and teachers
// ─────────────────────────────────────────────────────────────────────────────
class Users extends Table {
  IntColumn get id          => integer().autoIncrement()();
  TextColumn get name       => text().withLength(min: 2, max: 100)();
  TextColumn get email      => text().unique()();
  TextColumn get password   => text()(); // store hashed password
  TextColumn get role       => text()(); // 'student' | 'teacher'
  TextColumn get rollNumber => text().nullable()(); // only for students
  TextColumn get employeeId => text().nullable()(); // only for teachers
  TextColumn get department => text().nullable()();
  TextColumn get phone      => text().nullable()();
  TextColumn get embedding  => text().nullable()(); // JSON string of 192 doubles
  TextColumn get faceImagePath => text().nullable()();
  BoolColumn get isFaceRegistered => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ─────────────────────────────────────────────────────────────────────────────
// SUBJECTS TABLE
// ─────────────────────────────────────────────────────────────────────────────
class Subjects extends Table {
  IntColumn get id          => integer().autoIncrement()();
  TextColumn get name       => text().withLength(min: 2, max: 100)();
  TextColumn get code       => text().unique()();
  TextColumn get department => text().nullable()();
  IntColumn get teacherId   => integer().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ─────────────────────────────────────────────────────────────────────────────
// ENROLLMENTS TABLE — which students are in which subject
// ─────────────────────────────────────────────────────────────────────────────
class Enrollments extends Table {
  IntColumn get id        => integer().autoIncrement()();
  IntColumn get studentId => integer().references(Users, #id)();
  IntColumn get subjectId => integer().references(Subjects, #id)();
  DateTimeColumn get enrolledAt => dateTime().withDefault(currentDateAndTime)();

  // A student can only be enrolled once per subject
  @override
  List<Set<Column>> get uniqueWith => [
    {studentId, subjectId},
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// ATTENDANCE SESSIONS TABLE — teacher starts a session for a subject
// ─────────────────────────────────────────────────────────────────────────────
class AttendanceSessions extends Table {
  IntColumn get id        => integer().autoIncrement()();
  //IntColumn get subjectId => integer().references(Subjects, #id)();
  IntColumn get teacherId => integer().references(Users, #id)();
  TextColumn get sessionDate => text()(); // store as 'yyyy-MM-dd'
  TextColumn get startTime   => text()(); // store as 'HH:mm'
  TextColumn get endTime     => text().nullable()();
  TextColumn get status      => text().withDefault(const Constant('open'))();
  // status: 'open' | 'closed'
  TextColumn get location    => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ─────────────────────────────────────────────────────────────────────────────
// ATTENDANCE RECORDS TABLE — individual student/teacher attendance
// ─────────────────────────────────────────────────────────────────────────────
class AttendanceRecords extends Table {
  IntColumn get id        => integer().autoIncrement()();
  IntColumn get userId    => integer().references(Users, #id)();
  TextColumn get role     => text()(); // 'student' | 'teacher'
  TextColumn get status   => text().withDefault(const Constant('present'))();
  // status: 'present' | 'absent' | 'late'
  TextColumn get method   => text().withDefault(const Constant('face'))();
  // method: 'face' | 'manual'
  RealColumn get similarityScore => real().nullable()(); // face match score
  TextColumn get markedAt => text()(); // 'HH:mm:ss'
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get markedDate => dateTime()();

  // One record per user per session
  @override
  List<Set<Column>> get uniqueWith => [
    {userId},
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// FACE LOGS TABLE — every face scan attempt (pass or fail)
// ─────────────────────────────────────────────────────────────────────────────
class FaceLogs extends Table {
  IntColumn get id            => integer().autoIncrement()();
  IntColumn get userId        => integer().references(Users, #id)();
  IntColumn get sessionId     => integer().nullable().references(AttendanceSessions, #id)();
  BoolColumn get isMatch      => boolean()();
  RealColumn get similarity   => real()();
  TextColumn get imagePath    => text().nullable()();
  DateTimeColumn get scannedAt => dateTime().withDefault(currentDateAndTime)();
}