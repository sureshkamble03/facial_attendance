// lib/database/app_database.dart

import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'drift_tables/drift_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Users,
  Subjects,
  Enrollments,
  AttendanceSessions,
  AttendanceRecords,
  FaceLogs,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // ── Users ────────────────────────────────────────────────────────────────

  // Insert new user (student or teacher)
  Future<int> insertUser(UsersCompanion user) =>
      into(users).insert(user);

  // Get user by email
  Future<User?> getUserByEmail(String email) =>
      (select(users)..where((u) => u.email.equals(email))).getSingleOrNull();

  // Get user by id
  Future<User?> getUserById(int id) =>
      (select(users)..where((u) => u.id.equals(id))).getSingleOrNull();

  // Get all students
  Future<List<User>> getAllStudents() =>
      (select(users)..where((u) => u.role.equals('student'))).get();

  // Get all teachers
  Future<List<User>> getAllTeachers() =>
      (select(users)..where((u) => u.role.equals('teacher'))).get();

  // Save face embedding for a user
  Future<void> saveUserEmbedding(int userId, String embeddingJson) async {
    await (update(users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        embedding: Value(embeddingJson),
        isFaceRegistered: const Value(true),
      ),
    );
  }

  // Get embedding for a user
  Future<String?> getUserEmbedding(int userId) async {
    final user = await getUserById(userId);
    return user?.embedding;
  }

  // ── Subjects ─────────────────────────────────────────────────────────────

  Future<int> insertSubject(SubjectsCompanion subject) =>
      into(subjects).insert(subject);

  Future<List<Subject>> getAllSubjects() => select(subjects).get();

  Future<List<Subject>> getSubjectsByTeacher(int teacherId) =>
      (select(subjects)..where((s) => s.teacherId.equals(teacherId))).get();

  // ── Enrollments ──────────────────────────────────────────────────────────

  Future<int> enrollStudent(int studentId, int subjectId) =>
      into(enrollments).insert(
        EnrollmentsCompanion.insert(
          studentId: studentId,
          subjectId: subjectId,
        ),
      );

  // Get all students enrolled in a subject
  Future<List<User>> getStudentsInSubject(int subjectId) async {
    final query = select(enrollments).join([
      innerJoin(users, users.id.equalsExp(enrollments.studentId)),
    ])..where(enrollments.subjectId.equals(subjectId));

    final rows = await query.get();
    return rows.map((r) => r.readTable(users)).toList();
  }

  // ── Attendance Sessions ───────────────────────────────────────────────────

  Future<int> createSession(AttendanceSessionsCompanion session) =>
      into(attendanceSessions).insert(session);

  Future<AttendanceSession?> getOpenSession(int subjectId) =>
      (select(attendanceSessions)
        ..where((s) =>
        s.subjectId.equals(subjectId) & s.status.equals('open')))
          .getSingleOrNull();

  Future<void> closeSession(int sessionId, String endTime) async {
    await (update(attendanceSessions)
      ..where((s) => s.id.equals(sessionId)))
        .write(AttendanceSessionsCompanion(
      status: const Value('closed'),
      endTime: Value(endTime),
    ));
  }

  Future<List<AttendanceSession>> getSessionsBySubject(int subjectId) =>
      (select(attendanceSessions)
        ..where((s) => s.subjectId.equals(subjectId))
        ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .get();

  // ── Attendance Records ────────────────────────────────────────────────────

  Future<int> markAttendance(AttendanceRecordsCompanion record) =>
      into(attendanceRecords).insert(
        record,
        mode: InsertMode.insertOrIgnore, // prevents duplicate for same session
      );

  // Check if user already marked in this session
  Future<bool> isAlreadyMarked(int sessionId, int userId) async {
    final record = await (select(attendanceRecords)
      ..where((r) =>
      r.sessionId.equals(sessionId) & r.userId.equals(userId)))
        .getSingleOrNull();
    return record != null;
  }

  // Get attendance for a session
  Future<List<AttendanceRecord>> getSessionAttendance(int sessionId) =>
      (select(attendanceRecords)
        ..where((r) => r.sessionId.equals(sessionId)))
          .get();

  // Get attendance report for a student in a subject
  Future<List<AttendanceRecord>> getStudentAttendance(
      int userId, int subjectId) async {
    final sessions = await getSessionsBySubject(subjectId);
    final sessionIds = sessions.map((s) => s.id).toList();

    return (select(attendanceRecords)
      ..where((r) =>
      r.userId.equals(userId) &
      r.sessionId.isIn(sessionIds)))
        .get();
  }

  // ── Face Logs ─────────────────────────────────────────────────────────────

  Future<int> insertFaceLog(FaceLogsCompanion log) =>
      into(faceLogs).insert(log);

  Future<List<FaceLog>> getFaceLogsByUser(int userId) =>
      (select(faceLogs)..where((l) => l.userId.equals(userId))).get();
}

// ── DB connection ──────────────────────────────────────────────────────────

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'attendance.db'));
    return NativeDatabase.createInBackground(file);
  });
}