import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class EmergencyLocation {
  const EmergencyLocation(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
  String get mapsUrl => 'https://www.google.com/maps?q=$latitude,$longitude';
}

class EmergencyLocationService {
  Future<EmergencyLocation> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const EmergencyLocationException('GPS is turned off.');
    }
    final permission = await Permission.locationWhenInUse.request();
    if (!permission.isGranted && !permission.isLimited) {
      throw const EmergencyLocationException('Location permission was denied.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 15));
    return EmergencyLocation(position.latitude, position.longitude);
  }
}

class EmergencyLocationException implements Exception {
  const EmergencyLocationException(this.message);
  final String message;
}
