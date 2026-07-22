import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ScreenBackground extends StatelessWidget {
  final Widget child;
  const ScreenBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.82, -.88), radius: 1.28,
            colors: [Color(0xFF12356A), AppColors.background, AppColors.background],
          ),
        ),
        child: child,
      );
}

class AppPage extends StatelessWidget {
  final Widget child;
  final bool padded;
  const AppPage({super.key, required this.child, this.padded = true});
  @override
  Widget build(BuildContext context) => ScreenBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(child: padded ? Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child) : child),
        ),
      );
}

class GlowOrb extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool active;
  const GlowOrb({super.key, required this.icon, this.size = 132, this.active = false});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 380), width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [Color(0xFF55E2FF), Color(0xFF2079EC), Color(0xFF12296A)]),
          boxShadow: [BoxShadow(color: AppColors.cyan.withOpacity(active ? .64 : .26), blurRadius: active ? 42 : 22, spreadRadius: active ? 8 : 1)],
        ),
        child: Icon(icon, color: Colors.white, size: size * .3),
      );
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  const AppCard({super.key, required this.child, this.padding, this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: color ?? AppColors.surface.withOpacity(.92), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.outline)),
        child: child,
      );
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const PrimaryButton({super.key, required this.label, required this.icon, required this.onPressed});
  @override
  Widget build(BuildContext context) => SizedBox(width: double.infinity, height: 53, child: ElevatedButton.icon(
    style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, foregroundColor: AppColors.background, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
    onPressed: onPressed, icon: Icon(icon, size: 19), label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
  ));
}

class Waveform extends StatelessWidget {
  final Color color;
  final double width;
  const Waveform({super.key, this.color = AppColors.cyan, this.width = 150});
  @override
  Widget build(BuildContext context) => SizedBox(width: width, height: 30, child: CustomPaint(painter: _WavePainter(color)));
}
class _WavePainter extends CustomPainter {
  final Color color; _WavePainter(this.color);
  @override void paint(Canvas c, Size s) { final p = Paint()..color = color..strokeWidth = 2..strokeCap = StrokeCap.round; for (var i = 0; i < 23; i++) { final h = 5 + ((math.sin(i * 1.9).abs()) * 20); final x = (i + .5) * s.width / 23; c.drawLine(Offset(x, (s.height-h)/2), Offset(x, (s.height+h)/2), p); } }
  @override bool shouldRepaint(_WavePainter old) => old.color != color;
}

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key});
  @override Widget build(BuildContext context) => IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_rounded));
}

class PhoneBottomNav extends StatelessWidget {
  final int index;
  const PhoneBottomNav({super.key, required this.index});
  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: index,
    onDestinationSelected: (value) {
      final destinations = ['/home', '/history', '/profile', '/settings'];
      Navigator.pushReplacementNamed(context, destinations[value]);
    },
    destinations: const [
      NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.history_rounded), label: 'History'),
      NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
      NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Settings'),
    ],
  );
}

class ModeTile extends StatelessWidget {
  final IconData icon; final String title; final String subtitle; final String route; final bool danger;
  const ModeTile({super.key, required this.icon, required this.title, required this.subtitle, required this.route, this.danger = false});
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16), onTap: () => Navigator.pushNamed(context, route),
    child: AppCard(padding: const EdgeInsets.all(11), child: Row(children: [
      CircleAvatar(backgroundColor: (danger ? AppColors.danger : AppColors.cyan).withOpacity(.16), child: Icon(icon, color: danger ? AppColors.danger : AppColors.cyan, size: 20)),
      const SizedBox(width: 9), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppColors.muted))]))
    ])),
  );
}
