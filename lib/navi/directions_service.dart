import 'dart:convert';
import 'package:http/http.dart' as http;

class DirectionsService {
  /// Finds the nearest place matching a keyword (e.g. "hospital", "pharmacy")
  /// using OpenStreetMap's free Nominatim search API.
  Future<Map<String, dynamic>> findNearestPlace(
    double lat,
    double lng,
    String keyword,
  ) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=$keyword'
      '&format=json'
      '&limit=1'
      '&lat=$lat&lon=$lng',
    );

    final response = await http.get(
      url,
      headers: {'User-Agent': 'VisionMateApp/1.0'}, // required by Nominatim
    );

    final data = jsonDecode(response.body) as List;

    if (data.isEmpty) {
      throw Exception('No place found nearby for "$keyword"');
    }

    final result = data[0];
    return {
      'name': result['display_name'],
      'lat': double.parse(result['lat']),
      'lng': double.parse(result['lon']),
    };
  }

  /// Gets walking directions between two coordinates using free OSRM routing.
  Future<List<Map<String, dynamic>>> getWalkingSteps(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/foot/'
      '$originLng,$originLat;$destLng,$destLat'
      '?overview=false&steps=true',
    );

    final response = await http.get(url);
    final data = jsonDecode(response.body);

    if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty) {
      throw Exception('Could not calculate a walking route');
    }

    final legs = data['routes'][0]['legs'][0]['steps'] as List;

    return legs.map((step) {
      final maneuver = step['maneuver'];
      final instruction = _buildInstruction(
        maneuver['type'] as String,
        maneuver['modifier'] as String?,
        step['name'] as String?,
      );

      return {
        'instruction': instruction,
        'lat': maneuver['location'][1] as double,
        'lng': maneuver['location'][0] as double,
      };
    }).toList();
  }

  /// OSRM gives raw maneuver types instead of ready sentences like Google does,
  /// so we build a simple human-readable instruction ourselves.
  String _buildInstruction(String type, String? modifier, String? roadName) {
    final road = (roadName != null && roadName.isNotEmpty)
        ? " onto $roadName"
        : "";

    switch (type) {
      case 'depart':
        return "Start walking$road";
      case 'arrive':
        return "You have arrived at your destination";
      case 'turn':
        return "Turn ${modifier ?? 'ahead'}$road";
      case 'continue':
        return "Continue straight$road";
      default:
        return "Proceed$road";
    }
  }
}
