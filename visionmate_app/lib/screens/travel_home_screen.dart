import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';
import '../services/gtfs_realtime_service.dart';
import 'travel_result_screen.dart';

class TravelHomeScreen extends StatefulWidget {
  const TravelHomeScreen({super.key});

  @override
  State<TravelHomeScreen> createState() => _TravelHomeScreenState();
}

class _TravelHomeScreenState extends State<TravelHomeScreen> {
  final SpeechService _speechService = SpeechService();
  final TtsService _ttsService = TtsService();
  final GtfsRealtimeService _gtfsService = GtfsRealtimeService();

  bool _isListening = false;
  String _statusText = 'Press the button and speak your bus query';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _ttsService.init();
    await _speechService.init();
    await _ttsService.speak(
      'Welcome to VisionMate Travel. Press the button and say your bus number.',
    );
  }

  Future<void> _startListening() async {
    setState(() {
      _isListening = true;
      _statusText = 'Listening... Speak your bus number';
    });

    await _ttsService.speak('Listening. Say your bus number.');

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 200);
    }

    String spokenText = await _speechService.listen();

    setState(() {
      _isListening = false;
      _statusText = 'Processing...';
    });

    if (spokenText.isEmpty) {
      setState(() {
        _statusText = 'Could not hear you. Please try again.';
      });
      await _ttsService.speak('Could not hear you. Please try again.');
      return;
    }

    String busNumber = _gtfsService.extractBusNumber(spokenText);

    if (busNumber.isEmpty) {
      setState(() {
        _statusText = 'No bus number found. Please say a bus number.';
      });
      await _ttsService.speak('No bus number detected. Please try again.');
      return;
    }

    setState(() {
      _statusText = 'Searching for bus $busNumber...';
    });

    await _ttsService.speak('Searching for bus $busNumber. Please wait.');

    Map<String, dynamic> result = await _gtfsService.getBusETA(busNumber);

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              TravelResultScreen(busNumber: busNumber, result: result),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'VisionMate Travel',
          style: TextStyle(color: Colors.white, fontSize: 22),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                _statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: _isListening ? null : _startListening,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening ? Colors.red : Colors.blue,
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  size: 80,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              _isListening ? 'Listening...' : 'Tap to speak',
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
