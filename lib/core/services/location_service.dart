import 'package:geolocator/geolocator.dart';

/// Simple value object representing a captured location point.
class SosLocation {
  final double latitude;
  final double longitude;
  final double? accuracy;

  const SosLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
  };

  factory SosLocation.fromJson(Map<String, dynamic> json) => SosLocation(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    accuracy: (json['accuracy'] as num?)?.toDouble(),
  );

  @override
  String toString() => 'lat: $latitude, lng: $longitude';
}

/// Wraps the `geolocator` package so the rest of the app never talks
/// to the plugin directly.
class LocationService {
  Future<bool> isLocationServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  /// Fetches the current device location.
  /// Throws a [LocationServiceException] on failure so callers can
  /// decide how to surface it (e.g. still send SOS without location).
  Future<SosLocation> getCurrentLocation() async {
    try {
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const LocationServiceException(
          'Location services are disabled on this device.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      ).timeout(const Duration(seconds: 15));
      return SosLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } on LocationServiceException {
      rethrow;
    } catch (e) {
      throw LocationServiceException('Failed to get current location: $e');
    }
  }

  /// Attempts to get the last known location as a fast fallback.
  Future<SosLocation?> getLastKnownLocation() async {
    final position = await Geolocator.getLastKnownPosition();
    if (position == null) return null;
    return SosLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  }
}

class LocationServiceException implements Exception {
  final String message;
  const LocationServiceException(this.message);

  @override
  String toString() => 'LocationServiceException: $message';
}
