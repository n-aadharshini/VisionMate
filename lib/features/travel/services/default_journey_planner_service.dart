import '../models/journey_plan.dart';
import '../models/travel_exception.dart';
import '../repositories/routes_repository.dart';
import '../repositories/stops_repository.dart';
import 'geocoding_service.dart';
import 'geofence_service.dart';
import 'gps_service.dart';
import 'journey_planner_service.dart';

/// Real implementation of [JourneyPlannerService]. This is the Phase 2
/// piece that turns "current GPS + a spoken destination" into a
/// [JourneyPlan], by combining:
///
///  1. [GeocodingService]   — destination string -> coordinates
///  2. [StopsRepository]    — nearest boarding stop / alighting stop
///  3. [RoutesRepository]   — a route connecting those two stops, in order
///  4. [GeofenceService]    — the straight-line distances used for the
///                            walk-only decision and the spoken summary
///
/// Timetable and live-bus tracking are intentionally outside the current
/// travel scope, so planning stays a pure "what's the route" concern.
class DefaultJourneyPlannerService implements JourneyPlannerService {
  DefaultJourneyPlannerService({
    required GeocodingService geocodingService,
    required StopsRepository stopsRepository,
    required RoutesRepository routesRepository,
    required GeofenceService geofenceService,
    this.walkOnlyThresholdMeters = 800,
    this.maxStopSearchRadiusMeters = 2000,
  })  : _geocoding = geocodingService,
        _stops = stopsRepository,
        _routes = routesRepository,
        _geofence = geofenceService;

  final GeocodingService _geocoding;
  final StopsRepository _stops;
  final RoutesRepository _routes;
  final GeofenceService _geofence;

  /// If the destination is within this distance, skip the bus entirely
  /// and just walk (per spec STATE 1: "Decide walk-only or bus").
  final double walkOnlyThresholdMeters;

  /// A "nearest stop" further than this from either endpoint is treated
  /// as "no coverage here" rather than a usable match.
  final double maxStopSearchRadiusMeters;

  @override
  Future<JourneyPlan> planJourney({
    required double currentLat,
    required double currentLng,
    required String destinationQuery,
  }) async {
    final place = await _geocoding.geocode(destinationQuery);
    if (place == null) {
      throw TravelException(
        'destination_not_found',
        "I couldn't find $destinationQuery. Could you say that again?",
      );
    }

    final origin = GpsPosition(
      latitude: currentLat,
      longitude: currentLng,
      timestamp: DateTime.now(),
    );
    final directDistance = _geofence.distanceMeters(
      origin,
      place.latitude,
      place.longitude,
    );

    if (directDistance <= walkOnlyThresholdMeters) {
      return JourneyPlan(
        destinationName: place.displayName,
        destinationLat: place.latitude,
        destinationLng: place.longitude,
        totalDistanceMeters: directDistance,
        walkOnly: true,
      );
    }

    final boardingStop = await _stops.nearestStop(
      currentLat,
      currentLng,
      maxDistanceMeters: maxStopSearchRadiusMeters,
    );
    if (boardingStop == null) {
      throw TravelException(
        'no_nearby_stop',
        "I couldn't find a bus stop near you.",
      );
    }

    final alightingStop = await _stops.nearestStop(
      place.latitude,
      place.longitude,
      maxDistanceMeters: maxStopSearchRadiusMeters,
    );
    if (alightingStop == null) {
      throw TravelException(
        'no_nearby_stop',
        "I couldn't find a bus stop near ${place.displayName}.",
      );
    }

    final route = await _routes.findConnectingRoute(
      boardingStop.id,
      alightingStop.id,
    );
    if (route == null) {
      throw TravelException(
        'no_route_found',
        "I couldn't find a direct bus route to ${place.displayName}.",
      );
    }

    return JourneyPlan(
      destinationName: place.displayName,
      destinationLat: place.latitude,
      destinationLng: place.longitude,
      totalDistanceMeters: directDistance,
      boardingStop: boardingStop,
      alightingStop: alightingStop,
      route: route,
      walkOnly: false,
    );
  }
}
