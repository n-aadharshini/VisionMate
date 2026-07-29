import 'package:flutter/material.dart';

/// A large, high-contrast, accessible SOS button used on the SOS screen.
/// The looping glow makes the primary emergency action visibly available.
class SosButton extends StatefulWidget {
  const SosButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.isEnabled = true,
    this.label = 'SOS',
    this.semanticLabel =
        'Emergency S O S button. Double tap to send an emergency alert '
        'to your contacts with your current location.',
  });

  final VoidCallback onPressed;
  final bool isLoading;
  final bool isEnabled;
  final String label;
  final String semanticLabel;

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tappable = widget.isEnabled && !widget.isLoading;

    return Semantics(
      button: true,
      enabled: tappable,
      label: widget.semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 220,
          height: 220,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final glowOpacity = .32 + (_pulseController.value * .16);
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: glowOpacity,
                    child: Container(
                      width: 190,
                      height: 190,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFFD32F2F),
                            blurRadius: 34,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: _isPressed ? .94 : 1,
                    child: child,
                  ),
                ],
              );
            },
            child: Material(
              color: tappable ? const Color(0xFFD32F2F) : Colors.grey.shade600,
              shape: const CircleBorder(),
              elevation: 8,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: tappable ? widget.onPressed : null,
                onTapDown: tappable ? (_) => _setPressed(true) : null,
                onTapUp: tappable ? (_) => _setPressed(false) : null,
                onTapCancel: tappable ? () => _setPressed(false) : null,
                child: Center(
                  child: widget.isLoading
                      ? const SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(
                            strokeWidth: 5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          widget.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
