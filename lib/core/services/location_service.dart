import '../../features/current_location/services/current_geocoding_service.dart';
import '../../features/current_location/services/current_location_service.dart';

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

/// Deprecated compatibility adapter. It delegates to the Current Location
/// feature; it does not maintain a second GPS or reverse-geocoding path.
@Deprecated('Use CurrentLocationService and CurrentGeocodingService instead.')
class LocationService {
  LocationService({
    CurrentLocationService? currentLocationService,
    CurrentGeocodingService? currentGeocodingService,
  }) : _currentLocationService =
           currentLocationService ?? CurrentLocationService(),
       _currentGeocodingService =
           currentGeocodingService ?? CurrentGeocodingService();

  final CurrentLocationService _currentLocationService;
  final CurrentGeocodingService _currentGeocodingService;

  Future<SosLocation> getCurrentLocation() async {
    final current = await _currentLocationService.fetch();
    final address = await _currentGeocodingService.addressFor(current);
    return SosLocation(
      latitude: current.latitude,
      longitude: current.longitude,
      accuracy: current.accuracyMeters,
      readableAddress: address,
    );
  }

  /// Compatibility fallback for older SOS controllers. The shared Current
  /// Location service only exposes a fresh GPS fix, so no stale location is
  /// returned when that fix fails.
  Future<SosLocation?> getLastKnownLocation() async => null;
}
