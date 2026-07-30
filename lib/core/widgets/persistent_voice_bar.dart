import 'dart:ui';
import 'package:flutter/material.dart';

import '../../features/assistant/services/conversation_controller.dart';
import '../theme/app_theme.dart';
import '../services/app_haptics.dart';
import '../services/app_earcons.dart';

class PersistentVoiceBar extends StatefulWidget {
  const PersistentVoiceBar({super.key, this.rightAction});

  final Widget? rightAction;

  @override
  State<PersistentVoiceBar> createState() => _PersistentVoiceBarState();
}

class _PersistentVoiceBarState extends State<PersistentVoiceBar> {
  ConversationController? _controller;
  String _lastStateLabel = 'Idle';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = ConversationControllerScope.of(context);
  }

  void _onTapDown() {
    final c = _controller;
    if (c == null) return;
    if (c.state == ConversationState.idle) {
      AppHaptics.medium();
      AppEarcons.listeningStart();
      c.beginPushToTalk();
    } else if (c.state == ConversationState.speaking ||
        c.state == ConversationState.processing) {
      c.interruptSpeaking();
    }
  }

  void _onTapUp() {
    final c = _controller;
    if (c != null && c.state == ConversationState.listening) {
      c.endPushToTalk();
    }
  }

  void _onTapCancel() {
    _onTapUp();
  }

  String _labelFor(ConversationState state) => switch (state) {
    ConversationState.idle => 'Idle',
    ConversationState.listening => 'Listening',
    ConversationState.processing => 'Processing',
    ConversationState.speaking => 'Speaking',
  };

  IconData _iconFor(ConversationState state) => switch (state) {
    ConversationState.listening => Icons.mic_rounded,
    ConversationState.processing => Icons.auto_awesome_rounded,
    ConversationState.speaking => Icons.graphic_eq_rounded,
    ConversationState.idle => Icons.mic_none_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final state = c?.state ?? ConversationState.idle;
    final label = _labelFor(state);
    if (label != _lastStateLabel) {
      _lastStateLabel = label;
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 72,
          decoration: const BoxDecoration(
            color: Color(0xCC171C3A),
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Semantics(
                  label: 'Hold to listen. Double tap to start speaking, release to send.',
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _onTapDown(),
                    onTapUp: (_) => _onTapUp(),
                    onTapCancel: _onTapCancel,
                    child: Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: state == ConversationState.listening
                            ? AppColors.cyan.withValues(alpha: .25)
                            : AppColors.surfaceHigh.withValues(alpha: .5),
                        border: Border.all(
                          color: state == ConversationState.listening
                              ? AppColors.cyan
                              : AppColors.outline,
                          width: state == ConversationState.listening ? 2 : 1.2,
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          _iconFor(state),
                          key: ValueKey(state),
                          color: state == ConversationState.idle
                              ? AppColors.muted
                              : AppColors.cyan,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    label: 'Voice state: $label',
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: state == ConversationState.idle
                            ? AppColors.muted
                            : state == ConversationState.listening
                            ? AppColors.cyan
                            : state == ConversationState.processing
                            ? AppColors.warning
                            : AppColors.text,
                      ),
                    ),
                  ),
                ),
                if (widget.rightAction != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: widget.rightAction!,
                  ),
                if (widget.rightAction == null) const SizedBox(width: 64 + 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
