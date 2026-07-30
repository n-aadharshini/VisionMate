import '../models/intent_type.dart';
import '../models/vision_mate_response.dart';

class KeywordIntentClassifier {
  VisionMateResponse classify(String input) {
    final text = input.trim();
    final normalized = text.toLowerCase();
    final destination = _extractDestination(text);

    if (_containsAny(normalized, const ['hello', ' hi', 'how are you', 'what\'s up', 'whats up', 'joke', 'bored'])) {
      final reply = normalized.contains('joke')
          ? 'Why did the phone go to school? It wanted to be smarter.'
          : normalized.contains('bored')
              ? 'Let’s make things interesting. Want a joke, a quick chat, or help planning somewhere to go?'
              : 'Hi! I’m here with you. How can I help today?';
      return VisionMateResponse(intent: IntentType.chat, destination: null, reply: reply, confidence: 0.6, source: 'keyword', isFallback: true);
    }

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
        isFallback: true,
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
        isFallback: true,
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
        isFallback: true,
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
        isFallback: true,
      );
    }

    return const VisionMateResponse(
      intent: IntentType.chat,
      destination: null,
      reply:
          'I’m sorry, I didn’t quite catch that. Please try saying it again.',
      confidence: 0.3,
      source: 'keyword',
      isFallback: true,
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
