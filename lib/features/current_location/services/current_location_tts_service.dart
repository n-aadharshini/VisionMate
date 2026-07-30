import 'package:flutter_tts/flutter_tts.dart';

import '../models/location_model.dart';

class CurrentLocationTtsService {
  CurrentLocationTtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();
  final FlutterTts _tts;

  Future<void> announce(CurrentLocation location) {
    final address = location.address;
    final message = address == null || address.isEmpty
        ? 'Your current coordinates are latitude ${location.latitude} and longitude ${location.longitude}.'
        : 'You are currently near $address.';
    return _tts.speak(message);
  }

  Future<void> error(String message) => _tts.speak(message);
  Future<void> dispose() => _tts.stop();
}
