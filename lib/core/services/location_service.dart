import 'dart:async';

import 'package:geolocator/geolocator.dart';

sealed class LocationResult {
  const LocationResult();
}

class LocationSuccess extends LocationResult {
  const LocationSuccess(this.position);
  final GpsPosition position;
}

class LocationPermissionDenied extends LocationResult {
  const LocationPermissionDenied();
}

class LocationPermissionDeniedForever extends LocationResult {
  const LocationPermissionDeniedForever();
}

class LocationServiceDisabled extends LocationResult {
  const LocationServiceDisabled();
}

class LocationTimeout extends LocationResult {
  const LocationTimeout();
}

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

abstract class LocationServiceInterface {
  Future<LocationResult> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration timeout = const Duration(seconds: 15),
  });

  Stream<GpsPosition> get positionStream;
  void startListening({int distanceFilterMeters = 5, LocationAccuracy accuracy = LocationAccuracy.high});
  void stopListening();
  void dispose();
}

class GeolocatorLocationService implements LocationServiceInterface {
  StreamSubscription<Position>? _subscription;
  final _controller = StreamController<GpsPosition>.broadcast();

  @override
  Stream<GpsPosition> get positionStream => _controller.stream;

  @override
  Future<LocationResult> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const LocationServiceDisabled();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return const LocationPermissionDenied();
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationPermissionDeniedForever();
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: timeout,
        ),
      ).timeout(timeout);
      return LocationSuccess(_toGpsPosition(position));
    } on TimeoutException {
      return const LocationTimeout();
    } catch (_) {
      return const LocationTimeout();
    }
  }

  @override
  void startListening({int distanceFilterMeters = 5, LocationAccuracy accuracy = LocationAccuracy.high}) {
    _subscription?.cancel();
    _subscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
      ),
    ).listen(
      (position) => _controller.add(_toGpsPosition(position)),
      onError: (_) {},
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

  @override
  void dispose() {
    stopListening();
    _controller.close();
  }
}

String describeLocationResult(LocationResult result) => switch (result) {
      LocationSuccess() => '',
      LocationPermissionDenied() => 'I need location permission to help you navigate. Please allow it in the next prompt.',
      LocationPermissionDeniedForever() => 'Location access is turned off for VisionMate. Please enable it in your phone\'s app settings.',
      LocationServiceDisabled() => 'Your phone\'s location service is turned off. Please turn on GPS to continue.',
      LocationTimeout() => 'I\'m having trouble getting a GPS signal. Try moving somewhere with a clearer view of the sky.',
    };
