import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LandmarkCheckInResult {
  const LandmarkCheckInResult({
    required this.message,
    required this.usedGpsFallback,
    this.photoPath,
    this.latitude,
    this.longitude,
  });

  final String message;
  final bool usedGpsFallback;
  final String? photoPath;
  final double? latitude;
  final double? longitude;
}

/// Combines a photo captured by [CameraCaptureScreen] with an optional GPS fix.
/// Camera capture remains usable even when location is unavailable.
class LandmarkCheckInService {
  Future<LandmarkCheckInResult> checkInWithCapturedPhoto(
    String photoPath,
  ) async {
    try {
      final position = await _currentPosition();
      return LandmarkCheckInResult(
        photoPath: photoPath,
        latitude: position.latitude,
        longitude: position.longitude,
        usedGpsFallback: true,
        message:
            'Thanks, I captured the photo and checked your GPS location. I’ll use both to help keep you roughly on route.',
      );
    } catch (error, stackTrace) {
      debugPrint('GPS check-in failed after camera capture: $error\n$stackTrace');
      return LandmarkCheckInResult(
        photoPath: photoPath,
        usedGpsFallback: true,
        message:
            'Thanks, I captured the photo. I could not check GPS right now, so I’ll keep the camera result ready and use route guidance when location is available.',
      );
    }
  }

  Future<Position> _currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Location services are disabled.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission was not granted.');
    }

    return Geolocator.getCurrentPosition();
  }
}
