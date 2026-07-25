enum ChatRole { user, assistant }

/// A single bubble in the on-screen conversation.
///
/// Mutable by design: [text] is appended to in place while a transcript is
/// still partial (user speaking) or while the assistant's reply is still
/// streaming in — the controller mutates the same instance and calls
/// notifyListeners() rather than rebuilding the whole message list, so the
/// chat UI can update word-by-word/sentence-by-sentence.
class ChatMessage {
  ChatMessage({required this.role, required this.text, this.isPartial = false});

  final ChatRole role;
  String text;

  /// True while this bubble is still being filled in — a live partial
  /// transcript while the user is talking, or a reply that's still
  /// streaming in from the LLM. False once it's the final, settled text.
  bool isPartial;
}
