import 'dart:async';
import 'package:flutter/foundation.dart';
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

 
  bool _isRecalculating = false;
  String _currentDestinationKeyword = '';
  VoidCallback? onArrived;
  List<Map<String, double>> _polyline = [];

  /// Starts navigation to the nearest place matching [destinationKeyword]
  /// e.g. "hospital", "pharmacy", "bus stop"
 Future<void> startNavigation(String destinationKeyword) async {
    try {
      _currentDestinationKeyword = destinationKeyword;

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

      final routeData = await _directionsService.getWalkingSteps(
        currentPosition.latitude,
        currentPosition.longitude,
        destLat,
        destLng,
      );

      _steps = routeData['steps'] as List<Map<String, dynamic>>;
      final distanceMeters = routeData['distanceMeters'] as double;
      final durationSeconds = routeData['durationSeconds'] as double;
      _polyline = (routeData['polyline'] as List)
          .map((p) => Map<String, double>.from(p as Map))
          .toList();

      _currentStepIndex = 0;

      final stepCount = _steps.length;
      final distanceText = distanceMeters >= 1000
          ? "${(distanceMeters / 1000).toStringAsFixed(1)} kilometers"
          : "${distanceMeters.round()} meters";
      final minutes = (durationSeconds / 60).round();

      bool isConfirmed = false;
      int attempts = 0;

      while (!isConfirmed && attempts < 3) {
        attempts++;
        await _ttsService.speak(
          "Route ready. $stepCount steps to $placeName. "
          "About $distanceText, $minutes minutes walking. "
          "Say start to begin, or cancel to stop.",
        );

        final confirmation = await _speechService.listenOnce();
        final lower = confirmation.toLowerCase().trim();

        if (lower.isEmpty) {
          // Didn't catch anything - retry without treating it as "no"
          await _ttsService.speak("I didn't catch that.");
          continue;
        }

        final saidStart = lower.contains('start') ||
            lower.contains('go') ||
            lower.contains('yes') ||
            lower.contains('yeah') ||
            lower.contains('yep') ||
            lower.contains('sure') ||
            lower.contains('okay') ||
            lower.contains('ok');

        final saidCancel = lower.contains('cancel') ||
            lower.contains('stop') ||
            lower.contains('no');

        if (saidStart) {
          isConfirmed = true;
        } else if (saidCancel) {
          await _ttsService.speak("Okay, navigation cancelled.");
          return;
        } else {
          await _ttsService.speak("Sorry, please say start or cancel.");
        }
      }

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

  void _checkProgress(Position pos) async {
    if (_currentStepIndex >= _steps.length || _isRecalculating) return;

    final step = _steps[_currentStepIndex];
    final double distance = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      step['lat'] as double,
      step['lng'] as double,
    );

    // Deviation detection: if distance keeps growing over several updates, we're off route
    // Deviation detection: check actual distance from the route path itself
    final distanceFromRoute = _distanceToRoute(pos);

    if (distanceFromRoute > 30) {
      _isRecalculating = true;
      await _ttsService.speak("You seem to have gone off route. Recalculating.");
      await _recalculateRoute(pos);
      _isRecalculating = false;
      return;
    }

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
        await _ttsService.speak("You have arrived at your destination");
        stopNavigation();
        onArrived?.call();
      }
    }
  }

  Future<void> _recalculateRoute(Position pos) async {
    try {
      final place = await _directionsService.findNearestPlace(
        pos.latitude,
        pos.longitude,
        _currentDestinationKeyword,
      );

      final destLat = place['lat'] as double;
      final destLng = place['lng'] as double;

      final routeData = await _directionsService.getWalkingSteps(
        pos.latitude,
        pos.longitude,
        destLat,
        destLng,
      );

      _steps = routeData['steps'] as List<Map<String, dynamic>>;
      _currentStepIndex = 0;
      

      if (_steps.isNotEmpty) {
        await _ttsService.speak(
          "New route found. ${_steps[0]['instruction']}",
        );
      }
    } catch (e) {
      await _ttsService.speak("Could not recalculate the route.");
    }
  }

/// Returns the shortest distance (in meters) from the user's current
  /// position to the nearest segment of the planned route polyline.
  double _distanceToRoute(Position pos) {
    if (_polyline.length < 2) return 0;

    double minDistance = double.infinity;

    for (int i = 0; i < _polyline.length - 1; i++) {
      final a = _polyline[i];
      final b = _polyline[i + 1];

      final distance = _distanceToSegment(
        pos.latitude,
        pos.longitude,
        a['lat']!,
        a['lng']!,
        b['lat']!,
        b['lng']!,
      );

      if (distance < minDistance) minDistance = distance;
    }

    return minDistance;
  }

  /// Approximates the distance from point P to the segment AB using
  /// simple linear interpolation, then measures with Geolocator's
  /// accurate great-circle distance formula.
  double _distanceToSegment(
    double pLat, double pLng,
    double aLat, double aLng,
    double bLat, double bLng,
  ) {
    final dLat = bLat - aLat;
    final dLng = bLng - aLng;

    if (dLat == 0 && dLng == 0) {
      return Geolocator.distanceBetween(pLat, pLng, aLat, aLng);
    }

    final t = (((pLat - aLat) * dLat) + ((pLng - aLng) * dLng)) /
        ((dLat * dLat) + (dLng * dLng));

    final clampedT = t.clamp(0.0, 1.0);

    final closestLat = aLat + clampedT * dLat;
    final closestLng = aLng + clampedT * dLng;

    return Geolocator.distanceBetween(pLat, pLng, closestLat, closestLng);
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

      final routeData = await _directionsService.getWalkingSteps(
        currentPosition.latitude,
        currentPosition.longitude,
        destLat,
        destLng,
      );

      final steps = routeData['steps'] as List<Map<String, dynamic>>;

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
