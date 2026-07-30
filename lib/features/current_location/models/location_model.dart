class CurrentLocation {
  const CurrentLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.updatedAt,
    this.address,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime updatedAt;
  final String? address;

  String get mapsUrl => 'https://www.google.com/maps?q=$latitude,$longitude';

  CurrentLocation withAddress(String? value) => CurrentLocation(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    updatedAt: updatedAt,
    address: value,
  );
}
