/// A single entry from routes.json: a route number and its ordered list of
/// stop ids. Order matters for selecting a route that serves the boarding
/// stop before the alighting stop.
class BusRoute {
  const BusRoute({
    required this.routeNumber,
    required this.orderedStopIds,
  });

  final String routeNumber;
  final List<String> orderedStopIds;

  factory BusRoute.fromJson(Map<String, dynamic> json) {
    return BusRoute(
      routeNumber: json['routeNumber'] as String,
      orderedStopIds:
          List<String>.from(json['orderedStopIds'] as List? ?? const []),
    );
  }

  Map<String, dynamic> toJson() => {
        'routeNumber': routeNumber,
        'orderedStopIds': orderedStopIds,
      };

  int indexOfStop(String stopId) => orderedStopIds.indexOf(stopId);

  /// Positive if [toStopId] comes after [fromStopId] on this route.
  /// Returns -1 if either stop isn't on this route.
  int stopsBetween(String fromStopId, String toStopId) {
    final fromIndex = indexOfStop(fromStopId);
    final toIndex = indexOfStop(toStopId);
    if (fromIndex == -1 || toIndex == -1) return -1;
    return toIndex - fromIndex;
  }

  @override
  String toString() => 'BusRoute($routeNumber, ${orderedStopIds.length} stops)';
}
