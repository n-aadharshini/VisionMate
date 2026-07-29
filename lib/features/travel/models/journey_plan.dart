import 'bus_route.dart';
import 'bus_stop.dart';

/// The output of JourneyPlannerService.planJourney — everything
/// TravelController needs to drive the rest of the journey, plus the
/// exact sentence TTS should speak once planning finishes.
///
/// `walkOnly` covers the "destination is close enough to just walk"
/// branch called out in the spec (STATE 1: "Decide walk-only or bus").
/// When true, boardingStop/alightingStop/route are genuinely absent
/// (nullable, not placeholders) and TravelController skips straight to
/// NavigateToDestination.
class JourneyPlan {
  const JourneyPlan({
    required this.destinationName,
    required this.destinationLat,
    required this.destinationLng,
    required this.totalDistanceMeters,
    this.boardingStop,
    this.alightingStop,
    this.route,
    this.walkOnly = false,
  }) : assert(
          walkOnly || (boardingStop != null && alightingStop != null && route != null),
          'Non-walk-only plans must carry a boarding stop, alighting stop, and route.',
        );

  final String destinationName;
  final double destinationLat;
  final double destinationLng;
  final BusStop? boardingStop;
  final BusStop? alightingStop;
  final BusRoute? route;
  final double totalDistanceMeters;
  final bool walkOnly;

  /// The single sentence TravelController hands to TTS right after
  /// planning completes. Kept here (not scattered in the controller) so
  /// wording changes don't touch orchestration logic.
  String get summarySpeech {
    final km = (totalDistanceMeters / 1000).toStringAsFixed(1);
    if (walkOnly) {
      return '$destinationName is $km kilometers away. '
          'It is close enough to walk. I will guide you there directly.';
    }
    return '$destinationName is $km kilometers away. '
        'Walk to ${boardingStop!.name}. '
        'Board Bus ${route!.routeNumber}. '
        'I will start guiding you.';
  }

  @override
  String toString() =>
      'JourneyPlan(to: $destinationName, walkOnly: $walkOnly, route: ${route?.routeNumber})';
}
