import '../models/intent_type.dart';
import '../models/vision_mate_response.dart';

class KeywordIntentClassifier {
  VisionMateResponse classify(String input) {
    final text = input.trim();
    final normalized = text.toLowerCase();
    final destination = _extractDestination(text);

    if (_containsAny(normalized, const [
      'help',
      'sos',
      'emergency',
      'fell',
      'fall',
      'danger',
      'unsafe',
    ])) {
      return const VisionMateResponse(
        intent: IntentType.help,
        destination: null,
        reply: 'I’m here with you. Opening help options now.',
        confidence: 0.8,
        source: 'keyword',
      );
    }

    if (_containsAny(normalized, const [
      'read',
      'what does this say',
      'what is this text',
      'scan this',
      'read this',
      'text',
      'label',
    ])) {
      return const VisionMateResponse(
        intent: IntentType.read,
        destination: null,
        reply: 'Okay, point the camera at the text and I’ll read it for you.',
        confidence: 0.75,
        source: 'keyword',
      );
    }

    if (_containsAny(normalized, const [
      'bus',
      'eta',
      'arrive',
      'arrival',
      'train',
      'metro',
      'travel',
      'ticket',
    ])) {
      return VisionMateResponse(
        intent: IntentType.travel,
        destination: destination,
        reply: destination == null
            ? 'Sure, I’ll help you plan your journey.'
            : 'Sure, I’ll help you find travel options for $destination.',
        confidence: 0.75,
        source: 'keyword',
      );
    }

    if (_containsAny(normalized, const [
      'navigate',
      'take me to',
      'where is',
      'directions',
      'direction',
      'reach',
      'route',
      'way to',
    ])) {
      return VisionMateResponse(
        intent: IntentType.navigate,
        destination: destination,
        reply: destination == null
            ? 'Sure, where would you like to go?'
            : 'Sure, let’s get you to $destination.',
        confidence: 0.75,
        source: 'keyword',
      );
    }

    return const VisionMateResponse(
      intent: IntentType.unknown,
      destination: null,
      reply:
          'I’m sorry, I didn’t quite catch that. Please try saying it again.',
      confidence: 0.3,
      source: 'keyword',
    );
  }

  bool _containsAny(String text, List<String> keywords) {
    return keywords.any(text.contains);
  }

  String? _extractDestination(String input) {
    final match = RegExp(
      r'\b(?:to|for|reach)\s+(.+?)(?:[?.!,]|$)',
      caseSensitive: false,
    ).firstMatch(input);
    final destination = match?.group(1)?.trim();
    return destination == null || destination.isEmpty ? null : destination;
  }
}
