class ChatResult {
  const ChatResult({
    required this.reply,
    required this.intent,
    this.destination,
    required this.confidence,
    required this.source,
    this.isFallback = false,
  });

  final String reply;
  final String intent;
  final String? destination;
  final double confidence;
  final String source;
  final bool isFallback;
}

abstract class ChatProvider {
  Future<ChatResult> chat(String text, {List<Map<String, String>> history = const []});
}
