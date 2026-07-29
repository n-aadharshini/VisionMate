import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/bus_stop.dart';
import '../services/geofence_service.dart';
import '../services/gps_service.dart';

/// Loads and queries stops.json.
///
/// This is intentionally the only place that knows the asset path and
/// JSON shape for stops — JourneyPlannerService only ever calls
/// [nearestStop] and never touches the file directly.
class StopsRepository {
  StopsRepository({
    required GeofenceService geofenceService,
    String assetPath = 'assets/bus_data/stops.json',
  })  : _geofence = geofenceService,
        _assetPath = assetPath;

  final GeofenceService _geofence;
  final String _assetPath;

  List<BusStop>? _cache;

  /// Loads once and caches. Safe to call repeatedly (e.g. at the start of
  /// every `planJourney`) — subsequent calls are free.
  Future<List<BusStop>> loadAll() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw) as List<dynamic>;
    final stops = decoded
        .map((e) => BusStop.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);

    _cache = stops;
    return stops;
  }

  /// Finds the closest stop to (lat, lng). Returns null only if stops.json
  /// is empty — callers should treat that as a data problem, not a normal
  /// "no stop nearby" case, since VisionMate's coverage area is assumed to
  /// always have at least one stop.
  ///
  /// [maxDistanceMeters] lets callers reject a "nearest" stop that's still
  /// unreasonably far (e.g. destination well outside the covered area).
  Future<BusStop?> nearestStop(
    double lat,
    double lng, {
    double? maxDistanceMeters,
  }) async {
    final stops = await loadAll();
    if (stops.isEmpty) return null;

    final queryPoint = GpsPosition(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
    );

    BusStop? best;
    double bestDistance = double.infinity;

    for (final stop in stops) {
      final distance = _geofence.distanceMeters(
        queryPoint,
        stop.latitude,
        stop.longitude,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        best = stop;
      }
    }

    if (maxDistanceMeters != null && bestDistance > maxDistanceMeters) {
      return null;
    }
    return best;
  }

  /// Clears the cache — mainly useful in tests, or if stops.json is ever
  /// hot-swapped (e.g. downloaded update) during a long-running session.
  void clearCache() => _cache = null;
}
