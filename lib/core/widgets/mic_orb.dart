import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../services/app_haptics.dart';

class MicOrb extends StatefulWidget {
  const MicOrb({
    super.key,
    this.size = 96,
    this.onTap,
    this.onLongPress,
    this.active = false,
  });

  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool active;

  @override
  State<MicOrb> createState() => _MicOrbState();
}

class _MicOrbState extends State<MicOrb>
    with TickerProviderStateMixin {
  late final AnimationController _breatheController;
  late final AnimationController _rippleController;
  Timer? _longPressTimer;
  bool _isPressed = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _rippleController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _rippleController.reset();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _reduceMotion = MediaQuery.of(context).disableAnimations;
        });
        if (!_reduceMotion) {
          _breatheController.repeat(reverse: true);
        }
      }
    });
  }

  void _handleTapDown(TapDownDetails details) {
    if (_reduceMotion) {
      widget.onTap?.call();
      return;
    }
    _isPressed = true;
    AppHaptics.medium();
    _rippleController.forward();
    _breatheController.stop();
    setState(() {});

    _longPressTimer = Timer(const Duration(milliseconds: 600), () {
      if (_isPressed && mounted) {
        AppHaptics.heavy();
        HapticFeedback.heavyImpact();
        widget.onLongPress?.call();
      }
    });
  }

  void _handleTapUp(TapUpDetails details) {
    if (_reduceMotion) return;
    _longPressTimer?.cancel();
    if (_isPressed && mounted) {
      _isPressed = false;
      _breatheController.repeat(reverse: true);
      setState(() {});
      widget.onTap?.call();
    }
  }

  void _handleTapCancel() {
    if (_reduceMotion) return;
    _longPressTimer?.cancel();
    if (_isPressed && mounted) {
      _isPressed = false;
      _breatheController.repeat(reverse: true);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _breatheController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final breatheValue = _breatheController.value;
    final idleScale = _reduceMotion ? 1.0 : 1.0 + (0.06 * breatheValue);
    final pressedScale = 1.15;
    final scale = _isPressed ? pressedScale : idleScale;

    return Semantics(
      label: widget.active
          ? 'Listening. Mic active.'
          : 'Tap to speak. Long press for SOS.',
      hint: 'Double tap to start. Long press for emergency.',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        child: RepaintBoundary(
          child: SizedBox(
            width: widget.size * 2.2,
            height: widget.size * 2.2,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _rippleController,
                  builder: (context, _) {
                    final t = _rippleController.value;
                    final ringSize = widget.size + (widget.size * 1.2 * t);
                    final opacity = (1 - t) * 0.3;
                    return Container(
                      width: ringSize,
                      height: ringSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.cyan.withValues(alpha: opacity),
                          width: 2,
                        ),
                      ),
                    );
                  },
                ),
                Transform.scale(
                  scale: scale,
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
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        widget.active
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_rounded,
                        key: ValueKey(widget.active),
                        color: Colors.white,
                        size: widget.size * 0.32,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
