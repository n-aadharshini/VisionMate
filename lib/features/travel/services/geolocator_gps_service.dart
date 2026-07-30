import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'gps_service.dart';

/// Real implementation of [GpsService] backed by the `geolocator` package.
///
/// Add to pubspec.yaml:
///   dependencies:
///     geolocator: ^13.0.0
///
/// Android manifest (`android/app/src/main/AndroidManifest.xml`) needs the
/// fine and coarse location `uses-permission` entries.
///
/// For background updates while the screen is off (needed for the
/// OnBus / countdown states in later phases), also add the background-location
/// `uses-permission` entry.
///
/// This class only wraps geolocator — it does NOT own permission-request
/// UI. Call [ensurePermissions] once (e.g. from the app's startup flow or
/// right before the first `startJourney`) and surface any denial to the
/// user via TTS the same way any other TravelException is surfaced.
class GeolocatorGpsService implements GpsService {
  GeolocatorGpsService({
    this.distanceFilterMeters = 5,
    this.desiredAccuracy = LocationAccuracy.high,
  });

  /// Minimum movement (meters) before a new update is emitted. Kept small
  /// (5m) since bus-stop geofences are ~20m radius and we don't want to
  /// miss the threshold crossing.
  final int distanceFilterMeters;
  final LocationAccuracy desiredAccuracy;

  StreamSubscription<Position>? _subscription;
  final _controller = StreamController<GpsPosition>.broadcast();

  @override
  Stream<GpsPosition> get positionStream => _controller.stream;

  /// Checks and requests location permission + service enablement.
  /// Throws a descriptive [StateError] if the user has permanently
  /// denied permission, so the caller can turn that into a
  /// [TravelException] and speak it.
  Future<void> ensurePermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw StateError('Location services are turned off on this device.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission was denied.');
    }
  }

  @override
  Future<GpsPosition> getCurrentPosition() async {
    await ensurePermissions();
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: desiredAccuracy),
    );
    return _toGpsPosition(position);
  }

  @override
  void startListening() {
    _subscription?.cancel();
    _subscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: desiredAccuracy,
        distanceFilter: distanceFilterMeters,
      ),
    ).listen(
      (position) => _controller.add(_toGpsPosition(position)),
      onError: (Object error, StackTrace stack) {
        // Swallow transient stream errors (e.g. a single bad fix) rather
        // than tearing down the subscription — TravelController treats
        // silence as "no update yet", not as a hard failure.
      },
    );
  }

  @override
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  GpsPosition _toGpsPosition(Position position) => GpsPosition(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: position.timestamp,
      );

  void dispose() {
    stopListening();
    _controller.close();
  }
}
