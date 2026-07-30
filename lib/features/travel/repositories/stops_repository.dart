import 'dart:convert';

import 'package:flutter/foundation.dart';
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
    this.assetPath = 'assets/bus_data/stops.json',
  }) : _geofence = geofenceService;

  final GeofenceService _geofence;
  final String assetPath;

  List<BusStop>? _cache;

  /// Loads once and caches. Safe to call repeatedly (e.g. at the start of
  /// every `planJourney`) — subsequent calls are free.
  Future<List<BusStop>> loadAll() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as List<dynamic>;
    final stops = decoded
        .map((e) => BusStop.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);

    debugPrint(
      '[TRAVEL_STOPS] Loaded ${stops.length} stops from $assetPath. '
      'Samples: ${stops.take(3).map((stop) => stop.name).join(' | ')}',
    );
    _cache = stops;
    return stops;
  }

  /// Finds a dataset stop from a spoken or typed destination. It deliberately
  /// supports partial STT output such as "college of technology" by comparing
  /// normalised names and aliases in both directions, then using meaningful
  /// token overlap when neither string fully contains the other.
  Future<BusStop?> findByDestinationQuery(String query) async {
    final normalisedQuery = _normalise(query);
    if (normalisedQuery.isEmpty) return null;

    final queryTokens = _meaningfulTokens(normalisedQuery);
    if (queryTokens.isEmpty) return null;

    BusStop? best;
    var bestScore = 0.0;
    for (final stop in await loadAll()) {
      for (final candidate in <String>[stop.name, ...stop.aliases]) {
        final score = _matchScore(normalisedQuery, queryTokens, candidate);
        if (score > bestScore) {
          best = stop;
          bestScore = score;
        }
      }
    }

    if (best != null) {
      debugPrint(
        '[TRAVEL_STOPS] Matched "$query" to "${best.name}" '
        '(score=${bestScore.toStringAsFixed(2)}).',
      );
    } else {
      debugPrint('[TRAVEL_STOPS] No local stop match for "$query".');
    }
    return best;
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

  String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\b(bus\s+stand|bus\s+stop|busstop|stop|stand)\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  Set<String> _meaningfulTokens(String value) => value
      .split(' ')
      .where((token) => token.length > 1 && !_ignoredTokens.contains(token))
      .toSet();

  double _matchScore(
    String normalisedQuery,
    Set<String> queryTokens,
    String candidate,
  ) {
    final normalisedCandidate = _normalise(candidate);
    if (normalisedCandidate.isEmpty) return 0;
    if (normalisedCandidate == normalisedQuery) return 1.0;
    if (normalisedCandidate.contains(normalisedQuery) ||
        normalisedQuery.contains(normalisedCandidate)) {
      return 0.95;
    }

    final candidateTokens = _meaningfulTokens(normalisedCandidate);
    final shared = queryTokens.intersection(candidateTokens);
    final minimumShared = queryTokens.length == 1 ? 1 : 2;
    if (shared.length < minimumShared) return 0;
    return shared.length / queryTokens.length;
  }

  static const _ignoredTokens = <String>{
    'a', 'an', 'and', 'at', 'for', 'from', 'go', 'i', 'in', 'me', 'my',
    'near', 'please', 'take', 'the', 'to', 'where', 'you',
  };
}
