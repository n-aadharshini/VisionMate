import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'location_service.dart';
import 'directions_service.dart';
import 'tts_service.dart';

class NavigationController {
  final LocationService _locationService = LocationService();
  final DirectionsService _directionsService = DirectionsService();
  final TtsService _ttsService = TtsService();

  List<Map<String, dynamic>> _steps = [];
  int _currentStepIndex = 0;
  StreamSubscription<Position>? _positionStream;

  /// Starts navigation to the nearest place matching [destinationKeyword]
  /// e.g. "hospital", "pharmacy", "bus stop"
  Future<void> startNavigation(String destinationKeyword) async {
    try {
      final currentPosition = await _locationService.getCurrentLocation();

      final place = await _directionsService.findNearestPlace(
        currentPosition.latitude,
        currentPosition.longitude,
        destinationKeyword,
      );

      final destLat = place['geometry']['location']['lat'] as double;
      final destLng = place['geometry']['location']['lng'] as double;
      final placeName = place['name'] as String;

      _steps = await _directionsService.getWalkingSteps(
        currentPosition.latitude,
        currentPosition.longitude,
        destLat,
        destLng,
      );

      _currentStepIndex = 0;

      await _ttsService.speak("Starting navigation to $placeName");

      if (_steps.isNotEmpty) {
        await _ttsService.speak(_steps[0]['instruction'] as String);
      }

      _positionStream = _locationService.getLiveLocationStream().listen(
        _checkProgress,
      );
    } catch (e) {
      await _ttsService.speak(
        "Sorry, navigation could not start. ${e.toString()}",
      );
    }
  }

  void _checkProgress(Position pos) {
    if (_currentStepIndex >= _steps.length) return;

    final step = _steps[_currentStepIndex];
    final double distance = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      step['lat'] as double,
      step['lng'] as double,
    );

    if (distance < 10) {
      _currentStepIndex++;

      if (_currentStepIndex < _steps.length) {
        _ttsService.speak(_steps[_currentStepIndex]['instruction'] as String);
      } else {
        _ttsService.speak("You have arrived at your destination");
        stopNavigation();
      }
    }
  }

  /// Stops navigation and cancels location tracking
  void stopNavigation() {
    _positionStream?.cancel();
    _positionStream = null;
  }
}
