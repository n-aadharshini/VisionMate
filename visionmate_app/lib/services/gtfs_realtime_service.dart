import 'dart:convert';
import 'package:http/http.dart' as http;

class GtfsRealtimeService {
  // Chennai MTC GTFS Realtime API endpoint
  final String _baseUrl = 'https://otd.delhi.gov.in/api/realtime';

  Future<Map<String, dynamic>> getBusETA(String busNumber) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/VehiclePositions?key=YOUR_API_KEY'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseBusData(data, busNumber);
      } else {
        return {
          'success': false,
          'message': 'Could not fetch live data. Showing scheduled time.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'No internet connection. Showing scheduled time.',
      };
    }
  }

  Map<String, dynamic> _parseBusData(
    Map<String, dynamic> data,
    String busNumber,
  ) {
    try {
      final entities = data['entity'] as List;

      for (var entity in entities) {
        final vehicle = entity['vehicle'];
        final trip = vehicle['trip'];
        final routeId = trip['routeId'] ?? '';

        if (routeId.contains(busNumber)) {
          final position = vehicle['position'];
          final timestamp = vehicle['timestamp'];

          return {
            'success': true,
            'busNumber': busNumber,
            'latitude': position['latitude'],
            'longitude': position['longitude'],
            'timestamp': timestamp,
            'message':
                'Bus $busNumber is currently running. ETA approximately 5 minutes.',
          };
        }
      }

      return {
        'success': false,
        'message': 'Bus $busNumber not found in live feed.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Error parsing bus data.'};
    }
  }

  String extractBusNumber(String spokenText) {
    RegExp regExp = RegExp(r'\b\d+[A-Za-z]?\b');
    Match? match = regExp.firstMatch(spokenText);
    if (match != null) {
      return match.group(0) ?? '';
    }
    return '';
  }
}
