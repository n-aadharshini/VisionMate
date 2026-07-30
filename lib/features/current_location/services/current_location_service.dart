import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/location_model.dart';

class CurrentLocationService {
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
      return CurrentLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        updatedAt: DateTime.now(),
      );
    } on CurrentLocationException {
      rethrow;
    } catch (_) {
      throw const CurrentLocationException('Unable to determine your current location. Please enable GPS.');
    }
  }
}

class CurrentLocationException implements Exception {
  const CurrentLocationException(this.message);
  final String message;
}
