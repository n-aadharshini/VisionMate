import 'package:flutter/material.dart';

import 'conversation_session_controller.dart';

export 'conversation_session_controller.dart'
    show ConversationState, NavigationRequest;

/// Public name for the single app-wide conversation controller.
typedef ConversationController = ConversationSessionController;

/// Provides the one controller instance to every route below MaterialApp.
class ConversationControllerScope
    extends InheritedNotifier<ConversationController> {
  const ConversationControllerScope({
    super.key,
    required ConversationController controller,
    required super.child,
  }) : super(notifier: controller);

  static ConversationController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ConversationControllerScope>();
    assert(scope != null, 'ConversationControllerScope is missing.');
    return scope!.notifier!;
  }
}

/// Small root-level diagnostic label. It is intentionally always visible so
/// device testing can confirm the state machine without opening developer
/// tools.
class ConversationStateIndicator extends StatelessWidget {
  const ConversationStateIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final state = ConversationControllerScope.of(context).state;
    final label = switch (state) {
      ConversationState.idle => 'Idle',
      ConversationState.listening => 'Listening...',
      ConversationState.processing => 'Thinking...',
      ConversationState.speaking => 'Speaking...',
    };
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .72),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
