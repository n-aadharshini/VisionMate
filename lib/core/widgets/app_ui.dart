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

enum CompanionOrbState { off, listening, processing, speaking }

class GlowOrb extends StatefulWidget {
  final IconData icon;
  final double size;
  final bool active;
  final CompanionOrbState? state;

  const GlowOrb({
    super.key,
    required this.icon,
    this.size = 132,
    this.active = false,
    this.state,
  });

  @override
  State<GlowOrb> createState() => _GlowOrbState();
}

class _GlowOrbState extends State<GlowOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  CompanionOrbState get _state =>
      widget.state ??
      (widget.active ? CompanionOrbState.listening : CompanionOrbState.off);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _configureAnimation();
  }

  @override
  void didUpdateWidget(covariant GlowOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state || oldWidget.active != widget.active) {
      _configureAnimation();
    }
  }

  void _configureAnimation() {
    switch (_state) {
      case CompanionOrbState.off:
        _controller.stop();
        _controller.value = 0;
        return;
      case CompanionOrbState.listening:
        _controller.duration = const Duration(milliseconds: 1300);
        _controller.repeat(reverse: true);
        return;
      case CompanionOrbState.processing:
        _controller.duration = const Duration(milliseconds: 2600);
        _controller.repeat();
        return;
      case CompanionOrbState.speaking:
        _controller.duration = const Duration(milliseconds: 700);
        _controller.repeat(reverse: true);
        return;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOff = _state == CompanionOrbState.off;
    final isListening = _state == CompanionOrbState.listening;
    final isProcessing = _state == CompanionOrbState.processing;
    final isSpeaking = _state == CompanionOrbState.speaking;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = isListening || isSpeaking
            ? 1 + (_controller.value * (isListening ? .07 : .045))
            : 1.0;
        final glowAlpha = isOff
            ? .12
            : isProcessing
                ? .38
                : .6;

        return Transform.scale(
          scale: scale,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isProcessing)
                  Transform.rotate(
                    angle: _controller.value * 6.28318,
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.cyan,
                          width: 2.5,
                        ),
                        borderRadius: BorderRadius.circular(widget.size),
                      ),
                    ),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  width: widget.size * .84,
                  height: widget.size * .84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isOff
                        ? const RadialGradient(
                            colors: [
                              AppColors.surfaceLight,
                              AppColors.surface,
                              AppColors.background,
                            ],
                          )
                        : const RadialGradient(
                            colors: [
                              Color(0xFF55E2FF),
                              Color(0xFF2079EC),
                              Color(0xFF12296A),
                            ],
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cyan.withValues(alpha: glowAlpha),
                        blurRadius: isOff ? 14 : 38,
                        spreadRadius: isOff ? 0 : 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    isSpeaking ? Icons.graphic_eq_rounded : widget.icon,
                    color: isOff ? AppColors.muted : Colors.white,
                    size: widget.size * .3,
                  ),
                ),
                if (isSpeaking)
                  Positioned(
                    bottom: widget.size * .02,
                    child: Waveform(
                      color: AppColors.cyan,
                      width: widget.size * .52,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  const AppCard({super.key, required this.child, this.padding, this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: color ?? AppColors.surface.withValues(alpha: .92), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.outline)),
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
      CircleAvatar(backgroundColor: (danger ? AppColors.danger : AppColors.cyan).withValues(alpha: .16), child: Icon(icon, color: danger ? AppColors.danger : AppColors.cyan, size: 20)),
      const SizedBox(width: 9), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppColors.muted))]))
    ])),
  );
}
