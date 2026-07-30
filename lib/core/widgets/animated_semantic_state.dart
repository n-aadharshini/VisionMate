import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AnimatedSemanticState extends StatefulWidget {
  const AnimatedSemanticState({
    super.key,
    required this.label,
    this.liveRegion = true,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.button = false,
    this.tooltip,
  });

  final String label;
  final bool liveRegion;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool button;
  final String? tooltip;

  @override
  State<AnimatedSemanticState> createState() => _AnimatedSemanticStateState();
}

class _AnimatedSemanticStateState extends State<AnimatedSemanticState> {
  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final scale = reduceMotion ? 1.0 : null;

    Widget result = widget.child;

    if (scale != null) {
      result = Transform.scale(scale: scale, child: result);
    }

    result = Semantics(
      label: widget.label,
      liveRegion: widget.liveRegion,
      button: widget.button,
      child: result,
    );

    if (widget.onTap != null || widget.onLongPress != null) {
      result = GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap?.call();
        },
        onLongPress: widget.onLongPress,
        child: result,
      );
    }

    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip!, child: result);
    }

    return result;
  }
}
