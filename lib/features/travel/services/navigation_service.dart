import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/travel_exception.dart';

/// One ordered, speakable step in a walking route.
///
/// [latitude] and [longitude] identify the end of the step. The travel
/// controller uses that point to decide when it is time to announce the next
/// instruction. [remainingDistanceMeters] is the route distance remaining
/// *before* this step begins, when OSRM makes it available.
class NavigationStep {
  const NavigationStep({
    required this.instruction,
    required this.latitude,
    required this.longitude,
    this.distanceMeters,
    this.remainingDistanceMeters,
  });

  final String instruction;
  final double latitude;
  final double longitude;
  final double? distanceMeters;
  final double? remainingDistanceMeters;
}

/// A geographic point on the returned route geometry.
class RoutePoint {
  const RoutePoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

/// A complete walking route: ordered instructions plus the route line used
/// for off-route detection.
class WalkingRoute {
  const WalkingRoute({
    required this.steps,
    required this.points,
    this.totalDistanceMeters,
  });

  final List<NavigationStep> steps;
  final List<RoutePoint> points;
  final double? totalDistanceMeters;
}

/// Fetches ordered walking instructions for a route.
abstract class NavigationService {
  Future<List<NavigationStep>> getWalkingDirections({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  });

  /// Returns instructions and route geometry. Providers written before
  /// rerouting can keep implementing [getWalkingDirections]; their step
  /// endpoints are used as a conservative fallback route line.
  Future<WalkingRoute> getWalkingRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    final steps = await getWalkingDirections(
      fromLat: fromLat,
      fromLng: fromLng,
      toLat: toLat,
      toLng: toLng,
    );
    return WalkingRoute(
      steps: steps,
      points: steps
          .map((step) => RoutePoint(
                latitude: step.latitude,
                longitude: step.longitude,
              ))
          .toList(growable: false),
    );
  }

  /// Releases resources held by a provider. Test doubles need not override it.
  void dispose() {}
}

/// OSRM Route-service implementation for walking routes.
///
/// OSRM uses longitude,latitude order in the path. This client requests route
/// steps plus GeoJSON geometries so every instruction has a reliable endpoint
/// for GPS-based progression. No GPS stream is created here; that remains the
/// TravelController's single responsibility. The default endpoint is the
/// OpenStreetMap public OSRM deployment prepared with its pedestrian profile;
/// that deployment retains `driving` as its URL segment even for foot routes.
class OsrmNavigationService implements NavigationService {
  OsrmNavigationService({
    http.Client? client,
    this.baseUrl = 'https://routing.openstreetmap.de/routed-foot/route/v1',
    this.profile = 'driving',
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final String baseUrl;
  final String profile;
  final Duration timeout;

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }

  @override
  Future<List<NavigationStep>> getWalkingDirections({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async =>
      (await getWalkingRoute(
        fromLat: fromLat,
        fromLng: fromLng,
        toLat: toLat,
        toLng: toLng,
      )).steps;

  @override
  Future<WalkingRoute> getWalkingRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    _validateCoordinate(fromLat, fromLng, 'your current location');
    _validateCoordinate(toLat, toLng, 'the destination');

    final coordinates = '$fromLng,$fromLat;$toLng,$toLat';
    final uri = Uri.parse('$baseUrl/$profile/$coordinates').replace(
      queryParameters: const {
        'steps': 'true',
        'overview': 'false',
        'geometries': 'geojson',
      },
    );

    http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const TravelException(
        'navigation_timeout',
        'I could not reach the walking directions service. Please check your connection and try again.',
      );
    } on http.ClientException {
      throw const TravelException(
        'navigation_network',
        'I cannot reach the walking directions service right now. Please check your internet connection.',
      );
    } catch (_) {
      throw const TravelException(
        'navigation_network',
        'I could not get walking directions right now. Please try again shortly.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const TravelException(
        'navigation_network',
        'The walking directions service is unavailable right now. Please try again shortly.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const TravelException(
        'navigation_response',
        'I received an unexpected walking-directions response. Please try again.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const TravelException(
        'navigation_response',
        'I received an unexpected walking-directions response. Please try again.',
      );
    }

    final code = decoded['code'];
    if (code != 'Ok') {
      final message = decoded['message'];
      throw TravelException(
        code == 'NoRoute' ? 'navigation_no_route' : 'navigation_response',
        code == 'NoRoute'
            ? 'I could not find a safe walking route to that destination.'
            : 'I could not get walking directions${message is String && message.isNotEmpty ? ': $message' : ''}.',
      );
    }

    final routes = decoded['routes'];
    if (routes is! List || routes.isEmpty || routes.first is! Map) {
      throw const TravelException(
        'navigation_no_route',
        'I could not find a walking route to that destination.',
      );
    }
    final route = Map<String, dynamic>.from(routes.first as Map);
    final totalDistance = _asDouble(route['distance']);
    final legs = route['legs'];
    if (legs is! List || legs.isEmpty) {
      throw const TravelException(
        'navigation_response',
        'The walking route did not include any usable steps. Please try again.',
      );
    }

    final rawSteps = <_RawStep>[];
    final routePoints = <RoutePoint>[];
    for (final legValue in legs) {
      if (legValue is! Map || legValue['steps'] is! List) continue;
      for (final stepValue in legValue['steps'] as List) {
        if (stepValue is! Map) continue;
        final step = Map<String, dynamic>.from(stepValue);
        final maneuver = step['maneuver'];
        if (maneuver is! Map) continue;
        final maneuverMap = Map<String, dynamic>.from(maneuver);
        _appendStepGeometry(routePoints, step);
        // Arrival is announced by TravelController only after its final GPS
        // geofence check, avoiding a premature or duplicate arrival message.
        if (maneuverMap['type'] == 'arrive') continue;
        final endpoint = _stepEndpoint(step);
        if (endpoint == null) continue;
        rawSteps.add(
          _RawStep(
            instruction: _instructionFor(maneuverMap, step['name']),
            latitude: endpoint.$1,
            longitude: endpoint.$2,
            distanceMeters: _asDouble(step['distance']),
          ),
        );
      }
    }

    if (rawSteps.isEmpty) {
      throw const TravelException(
        'navigation_no_steps',
        'I found the destination but could not get usable walking instructions.',
      );
    }

    var completedDistance = 0.0;
    final steps = rawSteps.map((rawStep) {
      final remaining = totalDistance == null
          ? null
          : math.max(0, totalDistance - completedDistance).toDouble();
      completedDistance += rawStep.distanceMeters ?? 0;
      return NavigationStep(
        instruction: _withDistance(rawStep.instruction, rawStep.distanceMeters),
        latitude: rawStep.latitude,
        longitude: rawStep.longitude,
        distanceMeters: rawStep.distanceMeters,
        remainingDistanceMeters: remaining,
      );
    }).toList(growable: false);
    if (routePoints.isEmpty) {
      routePoints.add(RoutePoint(latitude: fromLat, longitude: fromLng));
      routePoints.addAll(
        steps.map((step) =>
            RoutePoint(latitude: step.latitude, longitude: step.longitude)),
      );
    }
    return WalkingRoute(
      steps: steps,
      points: List.unmodifiable(routePoints),
      totalDistanceMeters: totalDistance,
    );
  }

  void _validateCoordinate(double latitude, double longitude, String name) {
    if (!latitude.isFinite || !longitude.isFinite || latitude.abs() > 90 || longitude.abs() > 180) {
      throw TravelException('navigation_invalid_coordinate', 'I do not have a valid $name for walking directions.');
    }
  }

  (double, double)? _stepEndpoint(Map<String, dynamic> step) {
    final geometry = step['geometry'];
    if (geometry is Map && geometry['coordinates'] is List) {
      final coordinates = geometry['coordinates'] as List;
      if (coordinates.isNotEmpty) return _coordinate(coordinates.last);
    }
    final intersections = step['intersections'];
    if (intersections is List && intersections.isNotEmpty && intersections.last is Map) {
      return _coordinate((intersections.last as Map)['location']);
    }
    return null;
  }

  void _appendStepGeometry(List<RoutePoint> points, Map<String, dynamic> step) {
    final geometry = step['geometry'];
    if (geometry is! Map || geometry['coordinates'] is! List) return;
    for (final coordinate in geometry['coordinates'] as List) {
      final point = _coordinate(coordinate);
      if (point == null) continue;
      if (points.isNotEmpty &&
          points.last.latitude == point.$1 &&
          points.last.longitude == point.$2) {
        continue;
      }
      points.add(RoutePoint(latitude: point.$1, longitude: point.$2));
    }
  }

  (double, double)? _coordinate(Object? value) {
    if (value is! List || value.length < 2) return null;
    final longitude = _asDouble(value[0]);
    final latitude = _asDouble(value[1]);
    if (latitude == null || longitude == null || latitude.abs() > 90 || longitude.abs() > 180) return null;
    return (latitude, longitude);
  }

  String _instructionFor(Map<String, dynamic> maneuver, Object? roadName) {
    final type = maneuver['type'] as String? ?? 'continue';
    final modifier = maneuver['modifier'] as String?;
    final exit = maneuver['exit'];
    final cleanRoadName = roadName is String ? roadName.trim() : '';
    final road = cleanRoadName.isNotEmpty ? ' onto $cleanRoadName' : '';
    switch (type) {
      case 'depart': return 'Start walking$road';
      case 'turn': return 'Turn ${modifier ?? 'ahead'}$road';
      case 'continue': return modifier == null || modifier == 'straight' ? 'Continue straight$road' : 'Continue ${modifier}$road';
      case 'merge': return 'Merge ${modifier ?? 'ahead'}$road';
      case 'fork': return 'Keep ${modifier ?? 'ahead'}$road';
      case 'roundabout': return exit is num ? 'At the roundabout, take exit ${exit.toInt()}$road' : 'Enter the roundabout$road';
      case 'end of road': return modifier == null ? 'At the end of the road' : 'At the end of the road, turn $modifier';
      case 'new name': return 'Continue straight$road';
      default: return 'Continue carefully$road';
    }
  }

  String _withDistance(String instruction, double? distanceMeters) {
    if (distanceMeters == null || distanceMeters < 5) return instruction;
    final rounded = distanceMeters >= 1000 ? '${(distanceMeters / 1000).toStringAsFixed(1)} kilometres' : '${distanceMeters.round()} metres';
    return 'Walk $rounded. $instruction.';
  }

  double? _asDouble(Object? value) => value is num ? value.toDouble() : double.tryParse('$value');
}

class _RawStep {
  const _RawStep({required this.instruction, required this.latitude, required this.longitude, required this.distanceMeters});
  final String instruction;
  final double latitude;
  final double longitude;
  final double? distanceMeters;
}
