class MatchResult {
  final int userId;
  final String userName;
  final double distance;        // Lower = better match
  final double similarity;      // Higher = better match (0 to 1)

  MatchResult({
    required this.userId,
    required this.userName,
    required this.distance,
  }) : similarity = 1 - distance;

  bool get isGoodMatch => similarity > 0.4; // Adjust threshold as needed
}