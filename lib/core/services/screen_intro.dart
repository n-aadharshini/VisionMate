import '../../features/assistant/services/conversation_controller.dart';

abstract final class ScreenIntro {
  static final _introduced = <String>{};

  static void reset() {
    _introduced.clear();
  }

  static bool needsIntro(String route) => !_introduced.contains(route);

  static void markIntroduced(String route) {
    _introduced.add(route);
  }

  static void speakIntro(
    ConversationController controller,
    String route,
    String message,
  ) {
    if (_introduced.contains(route)) return;
    _introduced.add(route);
    controller.speak(message);
  }
}
