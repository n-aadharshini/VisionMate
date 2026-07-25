import 'package:flutter/material.dart';
import '../../features/flow/flow_screens.dart';
import '../../features/main/main_screens.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final Widget page = switch (settings.name) {
      '/' => const SplashScreen(), '/welcome' => const WelcomeScreen(), '/permissions' => const PermissionsScreen(), '/sign-in' => const SignInScreen(),
      '/home' => const HomeScreen(), '/speak' => const SpeakScreen(), '/listening' => const ListeningScreen(), '/processing' => const ProcessingScreen(),
      '/read' => const ReadScreen(), '/navigate' => const NavigateScreen(), '/indoor-navigation' => const IndoorNavigationScreen(), '/travel' => const TravelScreen(),
      '/help' => const HelpScreen(), '/sos' => const SosScreen(), '/profile' => const ProfileScreen(), '/settings' => const SettingsScreen(),
      '/history' => const HistoryScreen(), '/notifications' => const NotificationsScreen(), '/offline' => const OfflineScreen(), '/arrived' => const ArrivedScreen(), '/microinteractions' => const MicrointeractionsScreen(), _ => const SplashScreen(),
    };
    return PageRouteBuilder(settings: settings, pageBuilder: (_, a, _) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic), child: page), transitionDuration: const Duration(milliseconds: 260));
  }
}
