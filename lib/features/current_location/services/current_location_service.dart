import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/location_model.dart';

class CurrentLocationService {
  static CurrentLocation? _lastSuccessfulLocation;

  Future<CurrentLocation> fetch() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      throw const CurrentLocationException('GPS is disabled. Please enable Location Services.');
    }
    final permission = await Permission.locationWhenInUse.request();
    if (permission.isPermanentlyDenied) {
      throw const CurrentLocationException('Location permission is permanently denied. Open Settings to allow it.');
    }
    if (!permission.isGranted && !permission.isLimited) {
      throw const CurrentLocationException('Location permission was denied.');
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 15));
      return _remember(
        CurrentLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        updatedAt: DateTime.now(),
        ),
      );
    } on CurrentLocationException {
      rethrow;
    } catch (_) {
      final cached = _lastSuccessfulLocation;
      if (cached != null) return cached;

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return _remember(
          CurrentLocation(
            latitude: lastKnown.latitude,
            longitude: lastKnown.longitude,
            accuracyMeters: lastKnown.accuracy,
            updatedAt: DateTime.now(),
          ),
        );
      }
      throw const CurrentLocationException('Unable to determine your current location. Please enable GPS.');
    }
  }

  CurrentLocation _remember(CurrentLocation location) {
    _lastSuccessfulLocation = location;
    return location;
  }
}

class CurrentLocationException implements Exception {
  const CurrentLocationException(this.message);
  final String message;
}
