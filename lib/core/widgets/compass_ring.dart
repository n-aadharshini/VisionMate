import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class CompassRing extends StatefulWidget {
  const CompassRing({
    super.key,
    this.heading = 0.0,
    this.size = 100,
  });

  final double heading;
  final double size;

  @override
  State<CompassRing> createState() => _CompassRingState();
}

class _CompassRingState extends State<CompassRing>
    with SingleTickerProviderStateMixin {
  double _displayHeading = 0.0;

  @override
  void didUpdateWidget(covariant CompassRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _displayHeading = widget.heading;
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final heading = reduce ? widget.heading : _displayHeading;

    return Semantics(
      label: 'Compass. Heading ${heading.round()} degrees.',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _CompassPainter(heading: heading, reduceMotion: reduce),
            ),
            Icon(
              Icons.navigation_rounded,
              color: AppColors.cyan,
              size: widget.size * 0.2,
            ),
            Positioned(
              top: 4,
              child: Text(
                'N',
                style: TextStyle(
                  color: AppColors.danger,
                  fontSize: widget.size * 0.11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Positioned(
              bottom: 4,
              child: Text(
                'S',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: widget.size * 0.11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Positioned(
              left: 4,
              child: Text(
                'W',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: widget.size * 0.11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Positioned(
              right: 4,
              child: Text(
                'E',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: widget.size * 0.11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  _CompassPainter({required this.heading, required this.reduceMotion});

  final double heading;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    final ringPaint = Paint()
      ..color = AppColors.surfaceHigh.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, ringPaint);

    final tickPaint = Paint()
      ..color = AppColors.muted.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var i = 0; i < 36; i++) {
      final angle = (i * 10 - 90) * math.pi / 180;
      final isMajor = i % 9 == 0;
      final innerR = radius * (isMajor ? 0.78 : 0.85);
      final outerR = radius * (isMajor ? 0.92 : 0.88);
      canvas.drawLine(
        Offset(center.dx + innerR * math.cos(angle), center.dy + innerR * math.sin(angle)),
        Offset(center.dx + outerR * math.cos(angle), center.dy + outerR * math.sin(angle)),
        isMajor ? (Paint()..color = AppColors.muted..strokeWidth = 1.5) : tickPaint,
      );
    }

    final headingRad = (heading - 90) * math.pi / 180;
    final arrowPaint = Paint()
      ..color = AppColors.cyan
      ..style = PaintingStyle.fill;

    final arrowLen = radius * 0.55;
    final arrowTip = Offset(
      center.dx + arrowLen * math.cos(headingRad),
      center.dy + arrowLen * math.sin(headingRad),
    );
    final arrowLeft = Offset(
      center.dx + arrowLen * 0.35 * math.cos(headingRad + 2.4),
      center.dy + arrowLen * 0.35 * math.sin(headingRad + 2.4),
    );
    final arrowRight = Offset(
      center.dx + arrowLen * 0.35 * math.cos(headingRad - 2.4),
      center.dy + arrowLen * 0.35 * math.sin(headingRad - 2.4),
    );

    final path = Path()
      ..moveTo(arrowTip.dx, arrowTip.dy)
      ..lineTo(arrowLeft.dx, arrowLeft.dy)
      ..lineTo(center.dx, center.dy)
      ..lineTo(arrowRight.dx, arrowRight.dy)
      ..close();
    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(_CompassPainter old) =>
      old.heading != heading || old.reduceMotion != reduceMotion;
}
