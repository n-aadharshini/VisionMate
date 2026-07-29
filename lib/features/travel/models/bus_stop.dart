/// A single entry from stops.json.
///
/// `routes` lists the route numbers that call at this stop, so
/// JourneyPlannerService can quickly filter "which stops near me serve a
/// route that also serves a stop near the destination".
class BusStop {
  const BusStop({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.routes,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final List<String> routes;

  factory BusStop.fromJson(Map<String, dynamic> json) {
    return BusStop(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      routes: List<String>.from(json['routes'] as List? ?? const []),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'routes': routes,
      };

  @override
  String toString() => 'BusStop($id, $name)';
}
