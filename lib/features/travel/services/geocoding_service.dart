/// A geocoded destination: display name (as it should be spoken back)
/// plus coordinates.
class GeocodedPlace {
  const GeocodedPlace({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  final String displayName;
  final double latitude;
  final double longitude;
}

/// Resolves the destination string extracted from speech ("Agni College",
/// "Chennai Central", "home") into coordinates.
///
/// Kept as its own service (not folded into JourneyPlannerService) because
/// it has a genuinely different dependency: an external geocoding API
/// call, versus JourneyPlannerService's pure local stop/route matching.
/// Wired for real in Phase 4 using the Google Geocoding API (same API key
/// as Directions). "Take me home" resolves via a saved-places lookup
/// rather than geocoding — that branch is handled by the caller, not
/// this service.
abstract class GeocodingService {
  Future<GeocodedPlace?> geocode(String query);
}

class StubGeocodingService implements GeocodingService {
  @override
  Future<GeocodedPlace?> geocode(String query) {
    throw UnimplementedError(
      'GeocodingService is wired in Phase 4 (Google Geocoding API).',
    );
  }
}
