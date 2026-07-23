import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../services/tts_service.dart';

class TravelResultScreen extends StatefulWidget {
  final String busNumber;
  final Map<String, dynamic> result;

  const TravelResultScreen({
    super.key,
    required this.busNumber,
    required this.result,
  });

  @override
  State<TravelResultScreen> createState() => _TravelResultScreenState();
}

class _TravelResultScreenState extends State<TravelResultScreen> {
  final TtsService _ttsService = TtsService();
  bool _reminderSet = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _ttsService.init();
    await _speakResult();
  }

  Future<void> _speakResult() async {
    String message = widget.result['message'] ?? 'No result found.';
    await _ttsService.speak(message);
  }

  Future<void> _setReminder() async {
    setState(() {
      _reminderSet = true;
    });

    await _ttsService.speak(
      'Reminder set. I will alert you when bus ${widget.busNumber} is approaching.',
    );

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 300);
    }

    // simulate bus approaching after 5 seconds for testing
    await Future.delayed(Duration(seconds: 5));

    if (mounted) {
      await _ttsService.speak(
        'Alert! Bus ${widget.busNumber} is approaching. Please move to the boarding area.',
      );

      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool success = widget.result['success'] ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Bus Result',
          style: TextStyle(color: Colors.white, fontSize: 22),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // bus number display
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: success ? Colors.green : Colors.red,
                ),
                child: Center(
                  child: Text(
                    widget.busNumber,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // result message
              Text(
                widget.result['message'] ?? 'No result found.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20),
              ),

              const SizedBox(height: 40),

              // remind me button
              if (success && !_reminderSet)
                GestureDetector(
                  onTap: _setReminder,
                  child: Container(
                    width: double.infinity,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        'Set Reminder',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

              if (_reminderSet)
                const Text(
                  'Reminder Active ✅',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

              const SizedBox(height: 24),

              // go back button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text(
                      'Search Again',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
