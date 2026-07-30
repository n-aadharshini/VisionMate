import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;

import '../../../core/services/location_service.dart' as loc;
import '../models/travel_exception.dart';
import 'gps_service.dart';

class GeolocatorGpsService implements GpsService {
  GeolocatorGpsService({
    this.distanceFilterMeters = 5,
    this.desiredAccuracy = geo.LocationAccuracy.high,
    this.locationTimeout = const Duration(seconds: 15),
    loc.LocationServiceInterface? locationService,
  }) : _locationService = locationService ?? loc.GeolocatorLocationService();

  final int distanceFilterMeters;
  final geo.LocationAccuracy desiredAccuracy;
  final Duration locationTimeout;
  final loc.LocationServiceInterface _locationService;

  StreamSubscription<geo.Position>? _subscription;
  final _controller = StreamController<GpsPosition>.broadcast();

  @override
  Stream<GpsPosition> get positionStream => _controller.stream;

  @override
  Future<GpsPosition> getCurrentPosition() async {
    final result = await _locationService.getCurrentLocation(
      accuracy: desiredAccuracy,
      timeout: locationTimeout,
    );
    return switch (result) {
      loc.LocationSuccess(:final position) => position,
      loc.LocationPermissionDenied() => throw TravelException(
          'location_permission_denied',
          loc.describeLocationResult(result),
        ),
      loc.LocationPermissionDeniedForever() => throw TravelException(
          'location_permission_denied_forever',
          loc.describeLocationResult(result),
        ),
      loc.LocationServiceDisabled() => throw TravelException(
          'location_service_disabled',
          loc.describeLocationResult(result),
        ),
      loc.LocationTimeout() => throw TravelException(
          'location_timeout',
          loc.describeLocationResult(result),
        ),
    };
  }

  @override
  void startListening() {
    _subscription?.cancel();
    _subscription = geo.Geolocator.getPositionStream(
      locationSettings: geo.LocationSettings(
        accuracy: desiredAccuracy,
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

  GpsPosition _toGpsPosition(geo.Position position) => GpsPosition(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: position.timestamp,
      );

  void dispose() {
    stopListening();
    _controller.close();
    _locationService.dispose();
  }
}
