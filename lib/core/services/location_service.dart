import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

/// Simple value object representing a captured location point.
class SosLocation {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final String? readableAddress;

  const SosLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.readableAddress,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'readableAddress': readableAddress,
  };

  factory SosLocation.fromJson(Map<String, dynamic> json) => SosLocation(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    accuracy: (json['accuracy'] as num?)?.toDouble(),
    readableAddress: json['readableAddress'] as String?,
  );

  @override
  String toString() => 'lat: $latitude, lng: $longitude';

  SosLocation withReadableAddress(String? address) => SosLocation(
    latitude: latitude,
    longitude: longitude,
    accuracy: accuracy,
    readableAddress: address,
  );
}

/// Wraps the `geolocator` package so the rest of the app never talks
/// to the plugin directly.
class LocationService {
  final Geocoding _geocoding = Geocoding();
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

  /// Uses the device geocoder and never holds up an SOS for more than 5s.
  Future<String?> getReadableAddress(SosLocation location) async {
    try {
      final placemarks = await _geocoding
          .placemarkFromCoordinates(location.latitude, location.longitude)
          .timeout(const Duration(seconds: 5));
      if (placemarks.isEmpty) return null;
      final place = placemarks.first;
      final parts = [
        place.street,
        place.subLocality,
        place.locality,
        place.subAdministrativeArea,
      ].whereType<String>().map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
      return parts.isEmpty ? null : parts.toSet().join(', ');
    } catch (_) {
      return null;
    }
  }
}

class LocationServiceException implements Exception {
  final String message;
  const LocationServiceException(this.message);

  @override
  String toString() => 'LocationServiceException: $message';
}
