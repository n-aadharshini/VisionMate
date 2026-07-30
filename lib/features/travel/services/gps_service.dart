import 'dart:async';

import '../../../core/services/location_service.dart';

export '../../../core/services/location_service.dart' show GpsPosition;

abstract class GpsService {
  Stream<GpsPosition> get positionStream;
  Future<GpsPosition> getCurrentPosition();
  void startListening();
  void stopListening();
}

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
