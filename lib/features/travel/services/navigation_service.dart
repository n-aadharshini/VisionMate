/// One speakable step of walking guidance.
class NavigationStep {
  const NavigationStep({
    required this.instruction,
    required this.latitude,
    required this.longitude,
  });

  final String instruction;
  final double latitude;
  final double longitude;
}

/// Thin wrapper over the Google Directions API — walking guidance only.
///
/// Per the spec, VisionMate never re-implements a navigation engine: this
/// service's only job is translating Directions API steps into speakable
/// instructions ("Walk straight", "Turn left", "Cross road carefully").
/// Wired in Phase 4.
abstract class NavigationService {
  Future<List<NavigationStep>> getWalkingDirections({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  });
}

class StubNavigationService implements NavigationService {
  @override
  Future<List<NavigationStep>> getWalkingDirections({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    throw UnimplementedError(
      'NavigationService is wired in Phase 4 (Google Directions API).',
    );
  }
}
