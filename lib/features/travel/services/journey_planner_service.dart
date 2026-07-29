import '../models/journey_plan.dart';

/// Turns "current GPS + a destination the user said out loud" into a
/// [JourneyPlan]: nearest boarding stop, nearest alighting stop, best
/// route, and the walk-only decision.
///
/// Real implementation (Phase 3) needs: a geocoder for the destination
/// string, the stops/routes repositories, and a nearest-stop search — all
/// deliberately kept out of TravelController, which only ever sees the
/// resulting [JourneyPlan].
abstract class JourneyPlannerService {
  Future<JourneyPlan> planJourney({
    required double currentLat,
    required double currentLng,
    required String destinationQuery,
  });
}

class StubJourneyPlannerService implements JourneyPlannerService {
  @override
  Future<JourneyPlan> planJourney({
    required double currentLat,
    required double currentLng,
    required String destinationQuery,
  }) {
    throw UnimplementedError(
      'JourneyPlannerService is wired in Phase 3 '
      '(needs stops.json/routes.json/schedule.json + geocoding).',
    );
  }
}
