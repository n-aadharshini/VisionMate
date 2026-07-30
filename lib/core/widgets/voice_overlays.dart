import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../features/assistant/services/conversation_controller.dart';
import '../theme/app_theme.dart';
import '../services/app_earcons.dart';
import '../services/app_haptics.dart';

class ListeningOverlay extends StatefulWidget {
  const ListeningOverlay({super.key});

  @override
  State<ListeningOverlay> createState() => _ListeningOverlayState();
}

class _ListeningOverlayState extends State<ListeningOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _ringController;
  late final AnimationController _slideController;
  Timer? _silenceTimer;
  bool _cancelled = false;
  ConversationController? _controller;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _controller = ConversationControllerScope.of(context);
    } catch (_) {}
  }

  void _startSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || _cancelled) return;
      final c = _controller;
      if (c == null || c.state != ConversationState.listening) return;
      AppEarcons.error();
      c.endPushToTalk();
    });
  }

  void _cancelWithHaptic() {
    if (_cancelled) return;
    _cancelled = true;
    AppHaptics.medium();
    _silenceTimer?.cancel();
    _ringController.stop();
    _slideController.forward();
    final c = _controller;
    if (c != null && c.state == ConversationState.listening) {
      c.speak('Cancelled');
      c.endPushToTalk();
    }
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    });
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _ringController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      _controller = ConversationControllerScope.of(context);
    } catch (_) {}

    final c = _controller;
    final show = c != null && c.state == ConversationState.listening && !_cancelled;

    if (!show) {
      if (_ringController.isAnimating) _ringController.stop();
      return const SizedBox.shrink();
    }

    final reduce = MediaQuery.of(context).disableAnimations;

    if (!_ringController.isAnimating && !reduce) {
      _ringController.repeat();
    }

    _startSilenceTimer();

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity! > 200) {
          _cancelWithHaptic();
        }
      },
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([_ringController, _slideController]),
          builder: (context, _) {
            final slideOffset = _slideController.value * 200.0;
            return Transform.translate(
              offset: Offset(0, slideOffset),
              child: Container(
                color: AppColors.background.withValues(alpha: 0.85),
                child: Stack(
                  children: [
                    Center(
                      child: SizedBox(
                        width: 160,
                        height: 160,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (!reduce)
                              AnimatedBuilder(
                                animation: _ringController,
                                builder: (context, _) {
                                  return Transform.rotate(
                                    angle: _ringController.value * 2 * math.pi,
                                    child: Container(
                                      width: 140,
                                      height: 140,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.cyan.withValues(alpha: 0.4),
                                          width: 2.5,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            Container(
                              width: 96,
                              height: 96,
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
                                    color: AppColors.cyan.withValues(alpha: 0.35),
                                    blurRadius: 36,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.mic_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: MediaQuery.of(context).size.height * 0.25,
                      left: 0,
                      right: 0,
                      child: Column(
                        children: [
                          _ListeningWaveform(
                            reduceMotion: reduce,
                            controller: c,
                          ),
                          const SizedBox(height: 20),
                          Semantics(
                            liveRegion: true,
                            label: 'Listening',
                            child: Text(
                              'Listening',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.cyan.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Swipe down to cancel',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.muted.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ListeningWaveform extends StatefulWidget {
  const _ListeningWaveform({required this.reduceMotion, required this.controller});

  final bool reduceMotion;
  final ConversationController? controller;

  @override
  State<_ListeningWaveform> createState() => _ListeningWaveformState();
}

class _ListeningWaveformState extends State<_ListeningWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  Timer? _amplitudeTimer;
  final List<double> _barHeights = [0.3, 0.2, 0.5, 0.25, 0.4];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..repeat(reverse: true);

    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final amplitude = widget.controller?.soundLevel ?? 0.0;
      final normalized = (amplitude.clamp(0.0, 1.0) * 0.8) + 0.15;
      setState(() {
        for (var i = 0; i < _barHeights.length; i++) {
          final phase = math.sin(
            DateTime.now().millisecondsSinceEpoch / 200 + i * 1.2,
          );
          _barHeights[i] = (normalized * (0.6 + 0.4 * phase)).clamp(0.1, 1.0);
        }
      });
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _amplitudeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reduceMotion) {
      return const SizedBox(
        width: 120,
        height: 40,
        child: Center(
          child: Text(
            '...',
            style: TextStyle(color: AppColors.cyan, fontSize: 24),
          ),
        ),
      );
    }

    return SizedBox(
      width: 120,
      height: 72,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(5, (i) {
          final barHeight = _barHeights[i].clamp(0.1, 1.0);
          final height = 8 + (64 * barHeight);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: 8,
              height: height,
              decoration: BoxDecoration(
                color: AppColors.cyan,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class ThinkingOverlay extends StatefulWidget {
  const ThinkingOverlay({super.key});

  @override
  State<ThinkingOverlay> createState() => _ThinkingOverlayState();
}

class _ThinkingOverlayState extends State<ThinkingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _sphereController;
  late final AnimationController _shimmerController;
  bool _reducing = false;
  ConversationController? _controller;

  @override
  void initState() {
    super.initState();
    _sphereController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _controller = ConversationControllerScope.of(context);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sphereController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      _controller = ConversationControllerScope.of(context);
    } catch (_) {}

    final c = _controller;
    final show = c != null && c.state == ConversationState.processing && !_reducing;

    if (!show && _sphereController.isAnimating) {
      _sphereController.stop();
      _shimmerController.stop();
    }

    if (!show) return const SizedBox.shrink();

    final reduce = MediaQuery.of(context).disableAnimations;

    if (!_sphereController.isAnimating && !reduce) {
      _sphereController.repeat();
      _shimmerController.repeat();
    }

    return GestureDetector(
      onLongPress: () {
        if (!mounted) return;
        AppHaptics.heavy();
        setState(() => _reducing = true);
        final controller = _controller;
        if (controller != null) {
          controller.stop();
        }
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => _reducing = false);
        });
      },
      child: IgnorePointer(
        child: Container(
          color: AppColors.background.withValues(alpha: 0.88),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: reduce
                      ? Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.blue,
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                      : AnimatedBuilder(
                          animation: _sphereController,
                          builder: (context, _) {
                            return Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: SweepGradient(
                                  startAngle: _sphereController.value * 2 * math.pi,
                                  endAngle: _sphereController.value * 2 * math.pi + 2 * math.pi,
                                  colors: const [
                                    AppColors.blue,
                                    AppColors.cyan,
                                    AppColors.blue,
                                    AppColors.deep,
                                    AppColors.blue,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.blue.withValues(alpha: 0.3),
                                    blurRadius: 32,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.auto_awesome_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 28),
                _ShimmerText(
                  controller: _shimmerController,
                  reduceMotion: reduce,
                  text: 'Thinking\u2026',
                ),
                if (!reduce) ...[
                  const SizedBox(height: 40),
                  Semantics(
                    label: 'Long press to cancel',
                    child: Text(
                      'Long press to cancel',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.muted.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShimmerText extends StatelessWidget {
  const _ShimmerText({
    required this.controller,
    required this.reduceMotion,
    required this.text,
  });

  final AnimationController controller;
  final bool reduceMotion;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) {
      return Semantics(
        liveRegion: true,
        label: 'Thinking',
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.muted,
          ),
        ),
      );
    }

    return Semantics(
      liveRegion: true,
      label: 'Thinking',
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = controller.value;
          final gradient = LinearGradient(
            colors: const [
              AppColors.muted,
              AppColors.muted,
              AppColors.cyan,
              AppColors.text,
              AppColors.cyan,
              AppColors.muted,
              AppColors.muted,
            ],
            stops: [
              0.0,
              (t - 0.2).clamp(0.0, 1.0),
              (t - 0.05).clamp(0.0, 1.0),
              t.clamp(0.0, 1.0),
              (t + 0.05).clamp(0.0, 1.0),
              (t + 0.2).clamp(0.0, 1.0),
              1.0,
            ],
          );

          return ShaderMask(
            shaderCallback: (bounds) => gradient.createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          );
        },
      ),
    );
  }
}
