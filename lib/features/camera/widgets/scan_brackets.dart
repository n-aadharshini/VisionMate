import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum BracketState { entering, scanning, detected }

class ScanBrackets extends StatefulWidget {
  const ScanBrackets({
    super.key,
    required this.bracketState,
  });

  final BracketState bracketState;

  @override
  State<ScanBrackets> createState() => _ScanBracketsState();
}

class _ScanBracketsState extends State<ScanBrackets>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _pulseController;
  Timer? _detectedTimer;
  bool _snapped = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didUpdateWidget(covariant ScanBrackets oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bracketState != widget.bracketState) {
      if (widget.bracketState == BracketState.entering) {
        _entryController.forward();
        _pulseController.stop();
        _snapped = false;
      } else if (widget.bracketState == BracketState.scanning) {
        if (!_entryController.isCompleted) {
          _entryController.forward();
        }
        _pulseController.repeat(reverse: true);
        _snapped = false;
      } else if (widget.bracketState == BracketState.detected) {
        _pulseController.stop();
        _snapped = true;
        _detectedTimer?.cancel();
        _detectedTimer = Timer(const Duration(milliseconds: 2500), () {
          if (mounted) setState(() => _snapped = false);
        });
      }
    }
  }

  Color get _bracketColor {
    if (_snapped) return AppColors.success;
    if (widget.bracketState == BracketState.scanning ||
        widget.bracketState == BracketState.entering) {
      final pulse = _pulseController.value;
      return Color.lerp(AppColors.cyan, AppColors.cyan.withValues(alpha: 0.5), pulse)!;
    }
    return AppColors.cyan;
  }

  @override
  void dispose() {
    _detectedTimer?.cancel();
    _entryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final color = reduce ? AppColors.cyan : _bracketColor;
    final width = 40.0;
    const thickness = 3.0;
    const gap = 20.0;

    if (reduce) {
      return _buildBrackets(color, width, thickness, gap, 1.0);
    }

    return AnimatedBuilder(
      animation: _entryController,
      builder: (context, _) {
        final t = _entryController.value;
        return _buildBrackets(color, width, thickness, gap, t);
      },
    );
  }

  Widget _buildBrackets(Color color, double w, double t, double g, double anim) {
    return SizedBox.expand(
      child: Padding(
        padding: EdgeInsets.all(g),
        child: CustomPaint(
          painter: _BracketPainter(color: color, bracketLength: w, thickness: t, animation: anim),
        ),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  _BracketPainter({
    required this.color,
    required this.bracketLength,
    required this.thickness,
    required this.animation,
  });

  final Color color;
  final double bracketLength;
  final double thickness;
  final double animation;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final animLen = bracketLength * animation;
    final m = thickness / 2;

    // Top-left
    canvas.drawLine(Offset(m, m + animLen), Offset(m, m), paint);
    canvas.drawLine(Offset(m, m), Offset(m + animLen, m), paint);

    // Top-right
    canvas.drawLine(
      Offset(size.width - m - animLen, m),
      Offset(size.width - m, m),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - m, m),
      Offset(size.width - m, m + animLen),
      paint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(m, size.height - m - animLen),
      Offset(m, size.height - m),
      paint,
    );
    canvas.drawLine(
      Offset(m, size.height - m),
      Offset(m + animLen, size.height - m),
      paint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(size.width - m, size.height - m - animLen),
      Offset(size.width - m, size.height - m),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - m - animLen, size.height - m),
      Offset(size.width - m, size.height - m),
      paint,
    );
  }

  @override
  bool shouldRepaint(_BracketPainter old) =>
      old.color != color ||
      old.bracketLength != bracketLength ||
      old.animation != animation;
}
