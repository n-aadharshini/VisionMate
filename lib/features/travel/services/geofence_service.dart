import 'dart:math';

import 'gps_service.dart';

/// Distance and geofence math against a [GpsPosition].
///
/// Unlike the other services in this folder, this one has no platform
/// dependency (no GPS hardware, no HTTP) — it's pure arithmetic — so it's
/// fully implemented here in Phase 1 rather than stubbed, and is
/// unit-testable immediately.
abstract class GeofenceService {
  double distanceMeters(GpsPosition from, double lat, double lng);
  bool isWithinRadius(
    GpsPosition position,
    double lat,
    double lng,
    double radiusMeters,
  );
}

/// Standard great-circle distance calculation. Accurate to within a few
/// meters at city scale, which is more than sufficient for a ~20m
/// bus-stop geofence.
class HaversineGeofenceService implements GeofenceService {
  static const double _earthRadiusMeters = 6371000;

  @override
  double distanceMeters(GpsPosition from, double lat, double lng) {
    final lat1 = _toRadians(from.latitude);
    final lat2 = _toRadians(lat);
    final dLat = _toRadians(lat - from.latitude);
    final dLng = _toRadians(lng - from.longitude);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  @override
  bool isWithinRadius(
    GpsPosition position,
    double lat,
    double lng,
    double radiusMeters,
  ) {
    return distanceMeters(position, lat, lng) <= radiusMeters;
  }

  double _toRadians(double degrees) => degrees * pi / 180;
}
