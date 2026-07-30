import 'package:geocoding/geocoding.dart';

import '../models/location_model.dart';

class CurrentGeocodingService {
  CurrentGeocodingService({Geocoding? geocoding}) : _geocoding = geocoding ?? Geocoding();
  final Geocoding _geocoding;

  Future<String?> addressFor(CurrentLocation location) async {
    try {
      final places = await _geocoding
          .placemarkFromCoordinates(location.latitude, location.longitude)
          .timeout(const Duration(seconds: 5));
      if (places.isEmpty) return null;
      final place = places.first;
      final parts = [
        place.name,
        place.street,
        place.subLocality,
        place.locality,
        place.administrativeArea,
        place.country,
        place.postalCode,
      ].whereType<String>().map((part) => part.trim()).where((part) => part.isNotEmpty).toSet();
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      return null;
    }
  }
}
