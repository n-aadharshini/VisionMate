import 'package:flutter/material.dart';
import '../../features/flow/flow_screens.dart';
import '../../features/main/main_screens.dart';
import '../../features/camera/read_mode_screen.dart';
import '../../features/scene/scene_mode_screen.dart';
import '../../features/travel/state_machine/screens/navigate_screen.dart'
    as travel;
import '../../features/travel/state_machine/screens/travel_screen.dart'
    as travel;

abstract final class AppRoutes {
  static const home = '/home';
  static const transitionDuration = Duration(milliseconds: 300);

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final Widget page = switch (settings.name) {
      '/' => const SplashScreen(),
      '/splash' => const SplashScreen(),
      '/home' => const HomeScreen(),
      '/speak' => const SpeakScreen(),
      '/processing' => const ProcessingScreen(),
      '/read' => const ReadModeScreen(),
      '/describe' => const SceneModeScreen(),
      '/navigate' => const travel.NavigateScreen(),
      '/navigate/live' => const travel.NavigateScreen(),
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
      pageBuilder: (_, a, _) => page,
      transitionsBuilder: (_, a, _, child) =>
          _SharedAxisZTransition(a: a, child: child),
      transitionDuration: transitionDuration,
      reverseTransitionDuration: transitionDuration,
    );
  }
}

class _SharedAxisZTransition extends StatelessWidget {
  const _SharedAxisZTransition({required this.a, required this.child});

  final Animation<double> a;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) return child;

    return AnimatedBuilder(
      animation: a,
      builder: (context, child) {
        final scale = 0.92 + (0.08 * a.value);
        final opacity = a.value;
        final translateY = (1.0 - a.value) * 40.0;
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, translateY),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: child,
    );
  }
}
