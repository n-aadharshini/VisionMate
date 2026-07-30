import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'persistent_voice_bar.dart';

class VisionMateScaffold extends StatelessWidget {
  const VisionMateScaffold({
    super.key,
    required this.body,
    this.rightAction,
    this.padded = true,
    this.appBar,
    this.extendBodyBehindAppBar = false,
  });

  final Widget body;
  final Widget? rightAction;
  final bool padded;
  final PreferredSizeWidget? appBar;
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) => ScreenBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: appBar,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      body: SafeArea(
        child: padded
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: body,
              )
            : body,
      ),
      bottomNavigationBar: PersistentVoiceBar(rightAction: rightAction),
    ),
  );
}
