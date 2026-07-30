import 'intent_type.dart';

class VisionMateResponse {
  const VisionMateResponse({
    required this.intent,
    required this.destination,
    required this.reply,
    required this.confidence,
    required this.source,
    this.isFallback = false,
  });

  final IntentType intent;
  final String? destination;
  final String reply;
  final double confidence;
  final String source;
  final bool isFallback;
  String get response => reply;

  factory VisionMateResponse.fromGroqJson(Map<String, dynamic> json, {bool isFallback = false, String source = 'groq'}) {
    final intent = switch (json['intent']?.toString().toLowerCase()) {
      'navigate' => IntentType.navigate, 'read' => IntentType.read,
      'travel' => IntentType.travel, 'help' => IntentType.help, _ => IntentType.chat,
    };
    final destination = json['destination']?.toString().trim();
    final reply = (json['reply'] ?? json['response'] ?? '').toString().trim();
    final confidence = json['confidence'] is num ? (json['confidence'] as num).toDouble() : double.tryParse('${json['confidence']}') ?? 0;
    return VisionMateResponse(intent: intent, destination: destination == null || destination.isEmpty || destination == 'null' ? null : destination, reply: reply, confidence: confidence, source: source, isFallback: isFallback);
  }
}
