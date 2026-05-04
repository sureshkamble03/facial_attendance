abstract class AttendanceEvent {}

class MarkAttendanceEvent extends AttendanceEvent {
  final String imagePath;
  MarkAttendanceEvent(this.imagePath);
}