import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../services/app_haptics.dart';

enum CrossingState { wait, cross }

class RoadCrossingOverlay extends StatefulWidget {
  const RoadCrossingOverlay({
    super.key,
    required this.state,
    this.crossSeconds = 8,
    this.onDismiss,
  });

  final CrossingState state;
  final int crossSeconds;
  final VoidCallback? onDismiss;

  @override
  State<RoadCrossingOverlay> createState() => _RoadCrossingOverlayState();
}

class _RoadCrossingOverlayState extends State<RoadCrossingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _barController;
  late final AnimationController _pulseController;
  late final AnimationController _countdownController;
  Timer? _hapticTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _barController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _countdownController = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.crossSeconds),
    );
    _syncState();
  }

  @override
  void didUpdateWidget(covariant RoadCrossingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncState();
    }
  }

  void _syncState() {
    _hapticTimer?.cancel();
    _pulseController.stop();
    _countdownController.stop();
    _remainingSeconds = widget.crossSeconds;

    if (widget.state == CrossingState.wait) {
      _barController.reverse();
      _pulseController.repeat(reverse: true);
      _hapticTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        AppHaptics.medium();
      });
    } else {
      _barController.forward();
      _countdownController.reverse(from: 1.0);
      AppHaptics.tripleTick();

      _countdownController.addListener(() {
        final remaining = (_countdownController.value * widget.crossSeconds).round();
        if (remaining != _remainingSeconds && mounted) {
          setState(() => _remainingSeconds = remaining);
        }
      });
    }
  }

  @override
  void dispose() {
    _hapticTimer?.cancel();
    _barController.dispose();
    _pulseController.dispose();
    _countdownController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;

    return GestureDetector(
      onTap: widget.onDismiss,
      child: Container(
        color: Colors.black87,
        child: Column(
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_barController, _pulseController]),
              builder: (context, _) {
                final isCross = widget.state == CrossingState.cross;
                final barColor = isCross
                    ? AppColors.success
                    : Color.lerp(
                        AppColors.danger,
                        AppColors.danger.withValues(alpha: 0.6),
                        _pulseController.value,
                      )!;
                final barHeight = 8.0 + (_pulseController.value * 4);

                return Container(
                  height: reduce ? 8 : barHeight,
                  color: barColor,
                );
              },
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      liveRegion: true,
                      label: widget.state == CrossingState.wait
                          ? 'Wait, crossing not safe'
                          : 'Cross now, $_remainingSeconds seconds',
                      child: Text(
                        widget.state == CrossingState.wait ? 'Wait' : 'Cross now',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          color: widget.state == CrossingState.wait
                              ? AppColors.danger
                              : AppColors.success,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (widget.state == CrossingState.cross) ...[
                      Text(
                        '$_remainingSeconds seconds',
                        style: const TextStyle(
                          fontSize: 22,
                          color: AppColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: reduce
                            ? const SizedBox.shrink()
                            : AnimatedBuilder(
                                animation: _countdownController,
                                builder: (context, _) {
                                  return CustomPaint(
                                    size: const Size(120, 120),
                                    painter: _CountdownRingPainter(
                                      progress: _countdownController.value,
                                      color: AppColors.success,
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.directions_walk_rounded,
                                        color: AppColors.success,
                                        size: 48,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                    if (widget.state == CrossingState.wait) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: reduce
                            ? const SizedBox.shrink()
                            : AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, _) {
                                  final scale = 1.0 + (_pulseController.value * 0.08);
                                  return Transform.scale(
                                    scale: scale,
                                    child: const Icon(
                                      Icons.hourglass_bottom_rounded,
                                      color: AppColors.danger,
                                      size: 64,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Semantics(
                label: 'Dismiss crossing overlay',
                button: true,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.outline),
                    ),
                    onPressed: widget.onDismiss,
                    icon: const Icon(Icons.close),
                    label: const Text('Dismiss'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  _CountdownRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    canvas.drawCircle(center, radius, bgPaint);

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      -progress * 2 * math.pi,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_CountdownRingPainter old) => old.progress != progress;
}
