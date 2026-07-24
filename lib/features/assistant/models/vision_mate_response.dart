import 'intent_type.dart';

class VisionMateResponse {
  const VisionMateResponse({
    required this.intent,
    required this.destination,
    required this.reply,
    required this.confidence,
    required this.source,
  });

  final IntentType intent;
  final String? destination;
  final String reply;
  final double confidence;
  final String source;
}
