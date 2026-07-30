import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/bus_route.dart';

/// Loads and queries routes.json.
///
/// The one non-trivial query this answers is [findConnectingRoute]:
/// given a boarding stop and an alighting stop, which route (if any)
/// serves both, in the correct direction (alighting stop comes AFTER
/// boarding stop on that route)? A route that passes both stops in the
/// wrong order is not usable and must be rejected.
class RoutesRepository {
  RoutesRepository({this.assetPath = 'assets/bus_data/routes.json'});

  final String assetPath;
  List<BusRoute>? _cache;

  Future<List<BusRoute>> loadAll() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as List<dynamic>;
    final routes = decoded
        .map((e) => BusRoute.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);

    _cache = routes;
    return routes;
  }

  /// Returns the first route that serves [boardingStopId] and then, later
  /// in its stop order, [alightingStopId]. If multiple routes qualify,
  /// the one with the fewest stops between boarding and alighting wins —
  /// a reasonable proxy for "shortest ride" without needing live traffic
  /// or transfer data.
  Future<BusRoute?> findConnectingRoute(
    String boardingStopId,
    String alightingStopId,
  ) async {
    final routes = await loadAll();

    BusRoute? best;
    int bestStopSpan = 1 << 30;

    for (final route in routes) {
      final span = route.stopsBetween(boardingStopId, alightingStopId);
      // stopsBetween returns -1 if either stop isn't on this route, or if
      // alighting comes before boarding (wrong direction) — both are
      // rejected by requiring span > 0.
      if (span > 0 && span < bestStopSpan) {
        bestStopSpan = span;
        best = route;
      }
    }

    return best;
  }

  void clearCache() => _cache = null;
}
