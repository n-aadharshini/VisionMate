import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'location_service.dart';
import 'directions_service.dart';
import 'tts_service.dart';
import 'speech_service.dart';

class NavigationController {
  final LocationService _locationService = LocationService();
  final DirectionsService _directionsService = DirectionsService();
  final TtsService _ttsService = TtsService();
  final SpeechService _speechService = SpeechService();

  List<Map<String, dynamic>> _steps = [];
  int _currentStepIndex = 0;
  StreamSubscription<Position>? _positionStream;

  /// Starts navigation to the nearest place matching [destinationKeyword]
  /// e.g. "hospital", "pharmacy", "bus stop"
  Future<void> startNavigation(String destinationKeyword) async {
    try {
      await _ttsService.speak("Finding the nearest $destinationKeyword");

      final currentPosition = await _locationService.getCurrentLocation();

      final place = await _directionsService.findNearestPlace(
        currentPosition.latitude,
        currentPosition.longitude,
        destinationKeyword,
      );

      final destLat = place['lat'] as double;
      final destLng = place['lng'] as double;
      final placeName = place['name'] as String;

      await _ttsService.speak("Found $placeName, calculating the route");

      _steps = await _directionsService.getWalkingSteps(
        currentPosition.latitude,
        currentPosition.longitude,
        destLat,
        destLng,
      );

      _currentStepIndex = 0;

      final stepCount = _steps.length;
      await _ttsService.speak(
        "Route ready. $stepCount steps to $placeName. Say start to begin, or cancel to stop.",
      );

      final confirmation = await _speechService.listenOnce();
      final lowerConfirmation = confirmation.toLowerCase();

      final isConfirmed =
          lowerConfirmation.contains('start') ||
          lowerConfirmation.contains('go') ||
          lowerConfirmation.contains('yes');

      if (!isConfirmed) {
        await _ttsService.speak("Okay, navigation cancelled.");
        return;
      }

      await _ttsService.speak("Starting navigation");

      if (_steps.isNotEmpty) {
        await _ttsService.speak(_steps[0]['instruction'] as String);
      }

      _positionStream = _locationService.getLiveLocationStream().listen(
        _checkProgress,
      );
    } catch (e) {
      await _ttsService.speak(
        "Sorry, I couldn't find a nearby $destinationKeyword or calculate a route. Please try again.",
      );
    }
  }

  bool _earlyWarningGiven = false;
  bool _finalWarningGiven = false;

  void _checkProgress(Position pos) {
    if (_currentStepIndex >= _steps.length) return;

    final step = _steps[_currentStepIndex];
    final double distance = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      step['lat'] as double,
      step['lng'] as double,
    );

    final instruction = _steps[_currentStepIndex]['instruction'] as String;

    if (distance <= 20 && distance > 8 && !_earlyWarningGiven) {
      _earlyWarningGiven = true;
      _ttsService.speak("In 20 meters, $instruction");
    } else if (distance <= 8 && !_finalWarningGiven) {
      _finalWarningGiven = true;
      _ttsService.speak(instruction);
    } else if (distance < 4) {
      _currentStepIndex++;
      _earlyWarningGiven = false;
      _finalWarningGiven = false;

      if (_currentStepIndex < _steps.length) {
        final nextInstruction =
            _steps[_currentStepIndex]['instruction'] as String;
        _ttsService.speak(nextInstruction);
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

  /// Speaks all navigation steps once, useful for demos/testing without physically walking.
  Future<void> previewRoute(String destinationKeyword) async {
    try {
      final currentPosition = await _locationService.getCurrentLocation();

      final place = await _directionsService.findNearestPlace(
        currentPosition.latitude,
        currentPosition.longitude,
        destinationKeyword,
      );

      final destLat = place['lat'] as double;
      final destLng = place['lng'] as double;
      final placeName = place['name'] as String;

      final steps = await _directionsService.getWalkingSteps(
        currentPosition.latitude,
        currentPosition.longitude,
        destLat,
        destLng,
      );

      await _ttsService.speak("Route to $placeName has ${steps.length} steps.");
      for (final step in steps) {
        await _ttsService.speak(step['instruction'] as String);
      }
    } catch (e) {
      await _ttsService.speak(
        "Sorry, I couldn't find a nearby $destinationKeyword, or there was a connection issue. "
        "Please check your internet and try again.",
      );
    }
  }
}
