import 'package:flutter/material.dart';

import 'journey_screen.dart';

/// Registered at `/navigate`. Reached either from the "Navigate" quick
/// mode chip (no destination argument) or from a voice `navigate` intent
/// via ConversationSessionController's NavigationRequest (destination
/// argument present) — see main.dart's navigationRequests listener.
class NavigateScreen extends StatelessWidget {
  const NavigateScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const JourneyScreen(title: 'Navigate');
}
