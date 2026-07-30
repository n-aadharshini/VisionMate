import 'package:flutter/material.dart';
import '../../features/flow/flow_screens.dart';
import '../../features/main/main_screens.dart';
import '../../features/camera/read_mode_screen.dart';
import '../../features/travel/state_machine/screens/navigate_screen.dart'
    as travel;
import '../../features/travel/state_machine/screens/travel_screen.dart'
    as travel;

abstract final class AppRoutes {
  static const home = '/home';
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final Widget page = switch (settings.name) {
      '/home' => const HomeScreen(),
      '/speak' => const SpeakScreen(),
      '/processing' => const ProcessingScreen(),
      '/read' => const ReadModeScreen(),
      '/navigate' => const travel.NavigateScreen(),
      '/navigate/live' => const travel.LiveNavigateScreen(),
      '/indoor-navigation' => const IndoorNavigationScreen(),
      '/travel' => const travel.TravelScreen(),
      '/travel/live' => const travel.LiveTravelScreen(),
      '/help' => const HelpScreen(),
      '/sos' => const SosScreen(),
      '/profile' => const ProfileScreen(),
      '/settings' => const SettingsScreen(),
      '/history' => const HistoryScreen(),
      '/notifications' => const NotificationsScreen(),
      '/offline' => const OfflineScreen(),
      '/arrived' => const ArrivedScreen(),
      '/microinteractions' => const MicrointeractionsScreen(),
      _ => const HomeScreen(),
    };
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (_, a, _) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
        child: page,
      ),
      transitionDuration: const Duration(milliseconds: 260),
    );
  }
}
