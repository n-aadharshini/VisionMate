class BusRoute {
  final String routeId;
  final String routeNumber;
  final String routeName;
  final String arrivalTime;
  final String stopName;

  BusRoute({
    required this.routeId,
    required this.routeNumber,
    required this.routeName,
    required this.arrivalTime,
    required this.stopName,
  });

  factory BusRoute.fromJson(Map<String, dynamic> json) {
    return BusRoute(
      routeId: json['route_id'] ?? '',
      routeNumber: json['route_short_name'] ?? '',
      routeName: json['route_long_name'] ?? '',
      arrivalTime: json['arrival_time'] ?? '',
      stopName: json['stop_name'] ?? '',
    );
  }
}
