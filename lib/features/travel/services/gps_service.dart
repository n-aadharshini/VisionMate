import 'dart:async';

/// A single GPS fix.
class GpsPosition {
  const GpsPosition({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;
}

/// Continuous location updates, consumed by TravelController.
///
/// Implemented for real in Phase 2 using the `geolocator` package. Kept as
/// an interface so TravelController (and its tests) never import
/// `geolocator` directly — only this abstraction.
abstract class GpsService {
  /// Emits a new [GpsPosition] on every location update once
  /// [startListening] has been called.
  Stream<GpsPosition> get positionStream;

  /// One-shot fix, used at the start of planning.
  Future<GpsPosition> getCurrentPosition();

  void startListening();
  void stopListening();
}

/// Phase 1 placeholder. Compiles and can be constructor-injected today;
/// throws only when actually called, which happens the moment a real
/// journey is attempted — by design, so Phase 1 code is honest about what
/// isn't wired yet instead of silently no-op'ing.
class StubGpsService implements GpsService {
  final _controller = StreamController<GpsPosition>.broadcast();

  @override
  Stream<GpsPosition> get positionStream => _controller.stream;

  @override
  Future<GpsPosition> getCurrentPosition() {
    throw UnimplementedError('GpsService is wired in Phase 2 (geolocator).');
  }

  @override
  void startListening() {}

  @override
  void stopListening() {}
}
