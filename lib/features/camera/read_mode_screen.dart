import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_ui.dart';
import '../assistant/services/conversation_controller.dart';
import 'widgets/camera_preview_background.dart';

enum ReadModeState { idle, detecting, found, reading, speaking, completed }

class ReadModeScreen extends StatefulWidget {
  const ReadModeScreen({super.key});
  @override
  State<ReadModeScreen> createState() => _ReadModeScreenState();
}

class _ReadModeScreenState extends State<ReadModeScreen> {
  ReadModeState _state = ReadModeState.idle;
  bool _expanded = false;
  bool _flash = false;
  static const _mockText =
      'Bus stop sign: Koyambedu CMBT, Route 47. Next bus arrives in six minutes.';

  void _scan() async {
    setState(() => _state = ReadModeState.detecting);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _state = ReadModeState.found);
  }

  void _read() async {
    setState(() => _state = ReadModeState.reading);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _state = ReadModeState.speaking);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _state = ReadModeState.completed);
  }

  @override
  Widget build(BuildContext context) {
    final conversation = ConversationControllerScope.of(context);
    final chat = conversation.messages.isEmpty
        ? 'Point your camera towards text.'
        : conversation.messages.last.text;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreviewBackground(onStatus: (_) {}, torchOn: _flash),
          Center(
            child: Container(
              width: 280,
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _state == ReadModeState.idle
                      ? Colors.white38
                      : AppColors.cyan,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: .25),
                    blurRadius: 28,
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const AppBackButton(),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Read Mode',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _flash = !_flash),
                        icon: Icon(
                          _flash
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Chip(
                      label: Text(_label),
                      avatar: Icon(
                        _state == ReadModeState.speaking
                            ? Icons.volume_up_rounded
                            : Icons.visibility_rounded,
                        size: 17,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_state == ReadModeState.found ||
                      _state == ReadModeState.reading ||
                      _state == ReadModeState.speaking ||
                      _state == ReadModeState.completed)
                    AnimatedOpacity(
                      opacity: 1,
                      duration: const Duration(milliseconds: 280),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .65),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          'Koyambedu CMBT, Route 47',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  const Spacer(),
                  _BottomPanel(
                    state: _state,
                    text: _mockText,
                    expanded: _expanded,
                    onMore: () => setState(() => _expanded = !_expanded),
                    onRead: _read,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton.filledTonal(
                        onPressed: _read,
                        icon: const Icon(Icons.replay_rounded),
                        tooltip: 'Read again',
                      ),
                      Semantics(
                        label: 'Capture text',
                        button: true,
                        child: SizedBox(
                          width: 66,
                          height: 66,
                          child: FloatingActionButton(
                            onPressed: _scan,
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () {},
                        icon: const Icon(Icons.copy_rounded),
                        tooltip: 'Copy text',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  MiniChatStrip(
                    text: chat,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _label => switch (_state) {
    ReadModeState.idle => 'Ready',
    ReadModeState.detecting => 'Detecting',
    ReadModeState.found => 'Text detected',
    ReadModeState.reading => 'Reading',
    ReadModeState.speaking => 'Speaking',
    ReadModeState.completed => 'Completed',
  };
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.state,
    required this.text,
    required this.expanded,
    required this.onMore,
    required this.onRead,
  });
  final ReadModeState state;
  final String text;
  final bool expanded;
  final VoidCallback onMore;
  final VoidCallback onRead;
  @override
  Widget build(BuildContext context) => AppCard(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: state == ReadModeState.idle || state == ReadModeState.detecting
          ? Row(
              children: [
                if (state == ReadModeState.detecting)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (state == ReadModeState.detecting) const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    state == ReadModeState.detecting
                        ? 'Searching for text...'
                        : 'Point your camera towards text',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state == ReadModeState.reading
                      ? 'Reading...'
                      : '✓ Text detected',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  text,
                  maxLines: expanded ? null : 2,
                  overflow: TextOverflow.ellipsis,
                ),
                TextButton(
                  onPressed: expanded ? onMore : onRead,
                  child: Text(expanded ? 'Show less' : 'Read text'),
                ),
              ],
            ),
    ),
  );
}
