import 'package:flutter/material.dart';

import 'journey_screen.dart';

/// Registered at `/travel`. Reached either from the "Travel" quick mode
/// chip (no destination argument) or from a voice `travel` intent (e.g.
/// "which bus goes to T Nagar") — same underlying journey flow as
/// NavigateScreen, just a different entry point/title, per the spec's
/// intent examples treating "navigate" and "travel" phrasing the same way
/// once a destination is known.
class TravelScreen extends StatelessWidget {
  const TravelScreen({super.key});

  @override
  Widget build(BuildContext context) => const JourneyScreen(title: 'Travel');
}
