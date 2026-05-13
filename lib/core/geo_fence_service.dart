// lib/core/geo_fence_service.dart
//
// GeoFenceService — fetches device GPS and checks whether the user
// is inside any of the admin-configured allowed zones.
//
// Dependencies (add to pubspec.yaml):
//   geolocator: ^11.0.0
//   permission_handler: ^11.0.0

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../local_database/app_database.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Result model
// ─────────────────────────────────────────────────────────────────────────────
class GeoCheckResult {
  final bool allowed;
  final String message;
  final double? latitude;
  final double? longitude;
  final String? matchedZoneName;
  final double? distanceMeters; // distance to nearest zone centre

  const GeoCheckResult({
    required this.allowed,
    required this.message,
    this.latitude,
    this.longitude,
    this.matchedZoneName,
    this.distanceMeters,
  });

  @override
  String toString() => 'GeoCheckResult(allowed: $allowed, message: $message, '
      'zone: $matchedZoneName, dist: ${distanceMeters?.toStringAsFixed(1)}m)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────
class GeoFenceService {

  /// Request permission and get current position.
  /// Throws a descriptive [Exception] if anything blocks location access.
  Future<Position> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception(
        'Location services are disabled. '
        'Please enable GPS in your device settings.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception(
          'Location permission denied. '
          'Please allow location access to mark attendance.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. '
        'Please enable it from App Settings → Permissions.',
      );
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
  }

  /// Check if [position] falls within any of the [zones].
  /// Returns the first matching zone result, or a denial if none match.
  GeoCheckResult checkZones(Position position, List<GeoZone> zones) {
    if (zones.isEmpty) {
      // No zones configured → block (admin hasn't set up zones yet)
      return GeoCheckResult(
        allowed: false,
        message: 'No attendance zones configured. '
            'Please ask your admin to set up a location zone.',
        latitude: position.latitude,
        longitude: position.longitude,
      );
    }

    final activeZones = zones.where((z) => z.isActive).toList();

    if (activeZones.isEmpty) {
      return GeoCheckResult(
        allowed: false,
        message: 'All location zones are currently inactive. '
            'Contact your admin.',
        latitude: position.latitude,
        longitude: position.longitude,
      );
    }

    // Find the nearest zone and check if inside it
    GeoZone? nearestZone;
    double nearestDistance = double.infinity;

    for (final zone in activeZones) {
      final dist = _distanceMeters(
        position.latitude, position.longitude,
        zone.latitude, zone.longitude,
      );
      if (dist < nearestDistance) {
        nearestDistance = dist;
        nearestZone = zone;
      }
      if (dist <= zone.radiusMeters) {
        debugPrint('✅ Inside zone "${zone.name}" — ${dist.toStringAsFixed(1)}m from centre');
        return GeoCheckResult(
          allowed: true,
          message: 'Location verified: ${zone.name}',
          latitude: position.latitude,
          longitude: position.longitude,
          matchedZoneName: zone.name,
          distanceMeters: dist,
        );
      }
    }

    // Outside all zones
    final nearest = nearestZone!;
    final gap = (nearestDistance - nearest.radiusMeters).toStringAsFixed(0);
    debugPrint('❌ Outside all zones. Nearest: "${nearest.name}" '
        '${nearestDistance.toStringAsFixed(1)}m away');

    return GeoCheckResult(
      allowed: false,
      message: 'You are ${gap}m outside "${nearest.name}". '
          'Move closer to mark attendance.',
      latitude: position.latitude,
      longitude: position.longitude,
      matchedZoneName: nearest.name,
      distanceMeters: nearestDistance,
    );
  }

  /// Convenience: get position AND check zones in one call.
  /// Returns a [GeoCheckResult] — never throws; errors become denied results.
  Future<GeoCheckResult> verifyLocation(List<GeoZone> zones) async {
    try {
      final position = await getCurrentPosition();
      return checkZones(position, zones);
    } on Exception catch (e) {
      debugPrint('❌ GeoFence error: $e');
      return GeoCheckResult(
        allowed: false,
        message: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Haversine formula — returns distance in metres between two coordinates.
  double _distanceMeters(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const r = 6371000.0; // Earth radius in metres
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _rad(double deg) => deg * pi / 180;
}
