import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_ui.dart';
import '../assistant/models/intent_type.dart';
import '../assistant/services/companion_mode_controller.dart';
import '../assistant/services/speech_service.dart';
import '../assistant/services/tts_service.dart';
import '../assistant/services/vision_mate_brain.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => AppPage(child: GestureDetector(
    behavior: HitTestBehavior.opaque, onTap: () => Navigator.pushNamed(context, '/welcome'),
    child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      GlowOrb(icon: Icons.visibility_rounded, size: 142), SizedBox(height: 26), Text('VisionMate', style: TextStyle(fontSize: 31, fontWeight: FontWeight.w900)), SizedBox(height: 7), Text('Your Vision. Your Voice. Your Companion.', style: TextStyle(color: AppColors.muted)), SizedBox(height: 46), Waveform(), SizedBox(height: 12), Text('Tap anywhere to begin', style: TextStyle(fontSize: 12, color: AppColors.cyan)),
    ])),
  ));
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override Widget build(BuildContext context) => AppPage(child: Column(children: [
    const Spacer(), const GlowOrb(icon: Icons.accessibility_new_rounded, size: 150), const SizedBox(height: 34), const Text('Welcome to\nVisionMate.', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1.08)), const SizedBox(height: 12), const Text('Your voice-first assistant. Just speak, and we’ll read, guide, and keep you moving through the world.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)), const Spacer(), PrimaryButton(label: 'Get started', icon: Icons.arrow_forward_rounded, onPressed: () => Navigator.pushNamed(context, '/permissions')), const SizedBox(height: 14), const Text('By continuing, you agree to our Terms & Privacy Policy', style: TextStyle(color: AppColors.muted, fontSize: 10)), const SizedBox(height: 18),
  ]));
}

class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({super.key});
  @override Widget build(BuildContext context) => AppPage(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SizedBox(height: 30), const Text('STEP 1 OF 3', style: TextStyle(fontSize: 11, color: AppColors.cyan, fontWeight: FontWeight.bold)), const SizedBox(height: 7), const Text('Enable your senses', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)), const Text('Grant access so VisionMate can guide you.', style: TextStyle(color: AppColors.muted)), const SizedBox(height: 25),
    const _Permission(icon: Icons.mic_rounded, title: 'Microphone', body: 'Hear your voice commands', granted: true), const _Permission(icon: Icons.camera_alt_rounded, title: 'Camera', body: 'Read labels and describe scenes'), const _Permission(icon: Icons.location_on_rounded, title: 'Location', body: 'Guide you safely, wherever you go'), const _Permission(icon: Icons.notifications_rounded, title: 'Notifications', body: 'Keep safety alerts visible'), const _Permission(icon: Icons.vibration_rounded, title: 'Motion', body: 'Recognize falls and sudden movements'), const Spacer(), PrimaryButton(label: 'Allow Microphone', icon: Icons.check_rounded, onPressed: () => Navigator.pushNamed(context, '/sign-in')), const SizedBox(height: 16),
  ]));
}
class _Permission extends StatelessWidget { final IconData icon; final String title, body; final bool granted; const _Permission({required this.icon, required this.title, required this.body, this.granted = false}); @override Widget build(BuildContext c) => Padding(padding: const EdgeInsets.only(bottom: 10), child: AppCard(child: ListTile(leading: CircleAvatar(backgroundColor: AppColors.cyan.withValues(alpha: .15), child: Icon(icon, color: AppColors.cyan)), title: Text(title), subtitle: Text(body), trailing: Icon(granted ? Icons.check_circle : Icons.chevron_right, color: granted ? AppColors.cyan : Colors.white70)))); }

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});
  @override Widget build(BuildContext context) => AppPage(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SizedBox(height: 20), const Row(children: [GlowOrb(icon: Icons.visibility_rounded, size: 38), SizedBox(width: 10), Text('VisionMate', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18))]), const SizedBox(height: 42), const Text('Welcome back', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)), const SizedBox(height: 22), const _Input(icon: Icons.person_outline, hint: 'you@example.com'), const SizedBox(height: 12), const _Input(icon: Icons.lock_outline, hint: 'Password', obscure: true), Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () {}, child: const Text('Forgot password?', style: TextStyle(color: AppColors.cyan)))), PrimaryButton(label: 'Log in', icon: Icons.login_rounded, onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false)), const SizedBox(height: 16), const Row(children: [Expanded(child: Divider(color: AppColors.outline)), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or')), Expanded(child: Divider(color: AppColors.outline))]), const SizedBox(height: 15), SizedBox(width: double.infinity, height: 51, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.outline)), onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false), icon: const Icon(Icons.g_mobiledata_rounded), label: const Text('Continue with Google'))), const Spacer(), const Center(child: Text('New here? Create an account', style: TextStyle(color: AppColors.cyan))), const SizedBox(height: 18),
  ]));
}
class _Input extends StatelessWidget { final IconData icon; final String hint; final bool obscure; const _Input({required this.icon, required this.hint, this.obscure = false}); @override Widget build(BuildContext c) => TextField(obscureText: obscure, decoration: InputDecoration(prefixIcon: Icon(icon, color: AppColors.cyan), hintText: hint, hintStyle: const TextStyle(color: AppColors.muted), filled: true, fillColor: AppColors.surface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.outline)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.outline)))); }

class SpeakScreen extends StatefulWidget {
  const SpeakScreen({super.key});

  @override
  State<SpeakScreen> createState() => _SpeakScreenState();
}

class _SpeakScreenState extends State<SpeakScreen> {
  static bool _hasShownDisclosure = false;

  final CompanionModeController _companionMode =
      CompanionModeController.instance;
  CompanionOrbState _orbState = CompanionOrbState.off;
  bool _showDisclosure = false;

  bool get _companionModeOn => _orbState != CompanionOrbState.off;

  String get _companionStatus => switch (_orbState) {
        CompanionOrbState.off => 'Companion mode off',
        CompanionOrbState.listening => 'Listening for you',
        CompanionOrbState.processing => 'Thinking about that...',
        CompanionOrbState.speaking => 'Speaking to you',
      };

  @override
  void dispose() {
    super.dispose();
  }

  void _toggleCompanionMode() {
    if (_companionModeOn) {
      _companionMode.disable();
      setState(() {
        _orbState = CompanionOrbState.off;
        _showDisclosure = false;
      });
      return;
    }

    _companionMode.enable();
    setState(() {
      _orbState = _companionMode.state;
      _showDisclosure = !_hasShownDisclosure;
      _hasShownDisclosure = true;
    });
    Navigator.pushNamed(context, '/listening');
  }

  @override
  Widget build(BuildContext context) => AppPage(
        padded: false,
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(children: [
                const SizedBox(height: 16),
                const Row(children: [
                  Text(
                    'Good morning,',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  Spacer(),
                  Icon(Icons.notifications_none_rounded),
                ]),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Anika Sharma',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleCompanionMode,
                  child: GlowOrb(
                    icon: Icons.mic_rounded,
                    size: 172,
                    state: _orbState,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  _companionStatus,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.cyan,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _companionModeOn
                      ? 'Tap the orb any time to turn Companion Mode off.'
                      : 'Tap the orb to turn Companion Mode on.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                if (_showDisclosure) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Companion Mode keeps me listening between replies. It uses more battery, and I cannot hear you while I’m talking or thinking.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ] else
                  const SizedBox(height: 22),
                const Spacer(),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: 1.65,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: const [
                    ModeTile(
                      icon: Icons.navigation_rounded,
                      title: 'Navigate',
                      subtitle: 'Where should we go?',
                      route: '/navigate',
                    ),
                    ModeTile(
                      icon: Icons.menu_book_rounded,
                      title: 'Read',
                      subtitle: 'Read text around you',
                      route: '/read',
                    ),
                    ModeTile(
                      icon: Icons.directions_bus_rounded,
                      title: 'Travel',
                      subtitle: 'Plan your journey',
                      route: '/travel',
                    ),
                    ModeTile(
                      icon: Icons.sos_rounded,
                      title: 'Help',
                      subtitle: 'Get help fast',
                      route: '/help',
                      danger: true,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ]),
            ),
          ),
          const PhoneBottomNav(index: 0),
        ]),
      );
}

class ListeningScreen extends StatefulWidget {
  const ListeningScreen({super.key});

  @override
  State<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends State<ListeningScreen> {
  final SpeechService _speechService = SpeechService();
  final CompanionModeController _companionMode =
      CompanionModeController.instance;
  String _partialTranscript = '';
  String? _errorMessage;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startListening());
  }

  Future<void> _startListening() async {
    if (!_companionMode.isEnabled) {
      return;
    }
    _companionMode.setListening();
    try {
      await _speechService.startListening(
        _onFinalTranscript,
        onPartialResult: (text) {
          if (mounted) {
            setState(() => _partialTranscript = text);
          }
        },
      );
    } on StateError {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Microphone access is needed before VisionMate can listen.';
        });
      }
    }
  }

  Future<void> _onFinalTranscript(String transcript) async {
    if (_hasNavigated) {
      return;
    }

    if (transcript.trim().isEmpty) {
      _restartListening();
      return;
    }

    _hasNavigated = true;
    _companionMode.setProcessing();
    await _speechService.stopListening();
    if (mounted) {
      Navigator.pushReplacementNamed(
        context,
        '/processing',
        arguments: transcript.trim(),
      );
    }
  }

  void _restartListening() {
    if (!_companionMode.isEnabled || _hasNavigated) {
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (mounted && _companionMode.isEnabled && !_hasNavigated) {
        _startListening();
      }
    });
  }

  Future<void> _cancel() async {
    _companionMode.disable();
    await _speechService.stopListening();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    unawaited(_speechService.stopListening());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
        child: Column(children: [
          const SizedBox(height: 35),
          const Text(
            'LISTENING...',
            style: TextStyle(
              color: AppColors.cyan,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _cancel,
            child: GlowOrb(
              icon: Icons.mic_rounded,
              size: 150,
              state: _companionMode.state,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            "I'm listening...",
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26),
          ),
          const SizedBox(height: 10),
          const Waveform(width: 210),
          const SizedBox(height: 13),
          Text(
            _errorMessage ??
                (_partialTranscript.isEmpty
                    ? 'Tell me what you need help with.'
                    : _partialTranscript),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 51,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.outline),
              ),
              onPressed: null,
              icon: const Icon(Icons.close),
              label: const Text('Tap the orb to turn off'),
            ),
          ),
          const SizedBox(height: 16),
        ]),
      );
}
class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  final VisionMateBrain _brain = VisionMateBrain();
  final TtsService _ttsService = TtsService();
  final CompanionModeController _companionMode =
      CompanionModeController.instance;
  bool _hasStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _processRequest());
  }

  Future<void> _processRequest() async {
    if (_hasStarted) {
      return;
    }
    _hasStarted = true;

    final transcribedText = ModalRoute.of(context)?.settings.arguments as String?;
    if (transcribedText == null || transcribedText.trim().isEmpty) {
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }

    final response = await _brain.classify(transcribedText);
    _companionMode.setSpeaking();
    try {
      await _ttsService.speak(response.reply);
    } catch (_) {
      // Navigation remains available even if native text-to-speech is unavailable.
    }

    if (!mounted) {
      return;
    }

    if (_companionMode.isEnabled &&
        (response.intent == IntentType.chat ||
            response.intent == IntentType.unknown)) {
      Navigator.pushReplacementNamed(context, '/listening');
      return;
    }

    if (response.confidence < 0.5) {
      Navigator.pop(context);
      return;
    }

    switch (response.intent) {
      case IntentType.navigate:
        Navigator.pushReplacementNamed(
          context,
          '/navigate',
          arguments: response.destination,
        );
        return;
      case IntentType.travel:
        Navigator.pushReplacementNamed(
          context,
          '/travel',
          arguments: response.destination,
        );
        return;
      case IntentType.read:
        Navigator.pushReplacementNamed(context, '/read');
        return;
      case IntentType.help:
        Navigator.pushReplacementNamed(context, '/help');
        return;
      case IntentType.chat:
      case IntentType.unknown:
        Navigator.pop(context);
        return;
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
        child: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GlowOrb(icon: Icons.auto_awesome_rounded, size: 155, active: true),
            SizedBox(height: 28),
            Text(
              'Understanding your request...',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ]),
        ),
      );
}
