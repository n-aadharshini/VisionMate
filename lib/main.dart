import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'features/assistant/services/conversation_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const VisionMateApp());
}

class VisionMateApp extends StatefulWidget {
  const VisionMateApp({super.key});

  @override
  State<VisionMateApp> createState() => _VisionMateAppState();
}

class _VisionMateAppState extends State<VisionMateApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final ConversationController _conversationController;
  late final StreamSubscription<NavigationRequest> _navigationSubscription;

  @override
  void initState() {
    super.initState();
    // A real error callback, instead of none: previously the controller
    // was constructed with no onError, so STT/Groq/TTS/channel failures
    // had nowhere to go and were effectively silent in production. This
    // at minimum puts them in the observatory/log output; screens that
    // want to show something to the user subscribe to
    // `_conversationController.errors` themselves (see SpeakScreen).
    _conversationController = ConversationController(
      onError: _handleConversationError,
    );
    _navigationSubscription = _conversationController.navigationRequests.listen(
      (request) {
        _navigatorKey.currentState?.pushNamed(
          request.routeName,
          arguments: request.arguments,
        );
      },
    );
  }

  void _handleConversationError(Object error) {
    developer.log(
      'Conversation error: $error',
      name: 'VisionMate',
      level: 1000, // SEVERE
    );
  }

  @override
  void dispose() {
    _navigationSubscription.cancel();
    _conversationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConversationControllerScope(
      controller: _conversationController,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'VisionMate',
        theme: AppTheme.dark,
        initialRoute: AppRoutes.splash,
        onGenerateRoute: AppRoutes.onGenerateRoute,
        builder: (context, child) => Stack(
          children: [
            if (child != null) child,
            const ConversationStateIndicator(),
          ],
        ),
      ),
    );
  }
}
