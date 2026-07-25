import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Aurora background — soft royal-blue / teal / indigo glow blobs over the
/// deep navy base. Same widget signature as before; every screen using
/// [AppPage] picks this up automatically.
class ScreenBackground extends StatelessWidget {
  final Widget child;
  const ScreenBackground({super.key, required this.child});

  static Widget _blob(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color.withValues(alpha: .38), color.withValues(alpha: 0)],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: AppColors.background),
      Positioned(top: -110, left: -90, child: _blob(AppColors.blue, 280)),
      Positioned(top: -40, right: -110, child: _blob(AppColors.cyan, 230)),
      Positioned(bottom: -150, left: -70, child: _blob(AppColors.deep, 300)),
      child,
    ],
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
      body: SafeArea(
        child: padded
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: child,
              )
            : child,
      ),
    ),
  );
}

/// The mic orb — breathes gently at rest, breathes faster + grows pulse
/// rings when [active]. Same constructor as before (icon, size, active).
class GlowOrb extends StatefulWidget {
  final IconData icon;
  final double size;
  final bool active;
  const GlowOrb({
    super.key,
    required this.icon,
    this.size = 132,
    this.active = false,
  });

  @override
  State<GlowOrb> createState() => _GlowOrbState();
}

class _GlowOrbState extends State<GlowOrb> with TickerProviderStateMixin {
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat();

  @override
  void dispose() {
    _breathe.dispose();
    _pulse.dispose();
    super.dispose();
  }

  List<Widget> _pulseRings() => List.generate(3, (i) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = (_pulse.value + i / 3) % 1.0;
        final ringSize = widget.size + (widget.size * 0.85 * t);
        final opacity = (1 - t) * 0.32;
        return Container(
          width: ringSize,
          height: ringSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.cyan.withValues(alpha: opacity),
              width: 1.4,
            ),
          ),
        );
      },
    );
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.active ? 'Listening' : 'Microphone, idle',
    button: true,
    child: SizedBox(
      width: widget.size * 1.9,
      height: widget.size * 1.9,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.active) ..._pulseRings(),
          AnimatedBuilder(
            animation: _breathe,
            builder: (context, child) {
              final wobble = widget.active
                  ? Curves.easeInOutSine.transform(_breathe.value) * 0.06
                  : Curves.easeInOutSine.transform(_breathe.value) * 0.015;
              return Transform.scale(scale: 1.0 + wobble, child: child);
            },
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [
                    Color(0xFF7BEFF0),
                    AppColors.blue,
                    Color(0xFF161B52),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.blue.withValues(
                      alpha: widget.active ? .55 : .25,
                    ),
                    blurRadius: widget.active ? 46 : 22,
                    spreadRadius: widget.active ? 8 : 1,
                  ),
                  BoxShadow(
                    color: AppColors.cyan.withValues(
                      alpha: widget.active ? .35 : .12,
                    ),
                    blurRadius: widget.active ? 60 : 26,
                  ),
                ],
              ),
              child: Icon(
                widget.icon,
                color: Colors.white,
                size: widget.size * .3,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Frosted glass card. Same constructor as before (child, padding, color).
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  const AppCard({super.key, required this.child, this.padding, this.color});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? AppColors.surface.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      ),
    ),
  );
}

/// Gradient-filled primary action button. Same constructor as before
/// (label, icon, onPressed). Fires a haptic on tap.
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const PrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 56,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blue, AppColors.cyan],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withValues(alpha: .38),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            HapticFeedback.mediumImpact();
            onPressed();
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: AppColors.onAccent),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.onAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Live-feeling animated waveform. Same constructor as before (color, width).
class Waveform extends StatefulWidget {
  final Color color;
  final double width;
  const Waveform({super.key, this.color = AppColors.cyan, this.width = 150});

  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => SizedBox(
      width: widget.width,
      height: 30,
      child: CustomPaint(
        painter: _WavePainter(widget.color, _controller.value),
      ),
    ),
  );
}

class _WavePainter extends CustomPainter {
  final Color color;
  final double t;
  _WavePainter(this.color, this.t);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 23; i++) {
      final h = 5 + (math.sin(i * 1.9 + t * 2 * math.pi).abs() * 20);
      final x = (i + .5) * s.width / 23;
      c.drawLine(
        Offset(x, (s.height - h) / 2),
        Offset(x, (s.height + h) / 2),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.t != t || old.color != color;
}

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: () => Navigator.of(context).maybePop(),
    icon: const Icon(Icons.arrow_back_rounded),
  );
}

/// Floating glass bottom nav. Same constructor as before (index).
class PhoneBottomNav extends StatelessWidget {
  final int index;
  const PhoneBottomNav({super.key, required this.index});

  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xCC171C3A),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) {
            HapticFeedback.selectionClick();
            final destinations = ['/home', '/history', '/profile', '/settings'];
            Navigator.pushReplacementNamed(context, destinations[value]);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    ),
  );
}

/// Glass tile with gradient icon chip. Same constructor as before
/// (icon, title, subtitle, route, danger).
class ModeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final bool danger;
  const ModeTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: () {
      HapticFeedback.selectionClick();
      Navigator.pushNamed(context, route);
    },
    child: AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: danger
                    ? const [Color(0xFFFF6A5D), AppColors.danger]
                    : const [AppColors.cyan, AppColors.blue],
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
