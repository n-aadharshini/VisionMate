import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_ui.dart';
import '../../core/widgets/vision_mate_scaffold.dart';
import '../assistant/models/chat_message.dart';
import '../assistant/services/conversation_controller.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _springController;
  late final AnimationController _fadeController;
  late final AnimationController _ringController;
  late final Animation<double> _springAnimation;
  bool _ready = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();

    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _springAnimation = CurvedAnimation(
      parent: _springController,
      curve: Curves.elasticOut,
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _reduceMotion = MediaQuery.of(context).disableAnimations;
      });
      _runEntrance();
    });
  }

  Future<void> _runEntrance() async {
    if (_reduceMotion) {
      setState(() => _ready = true);
      await Future.delayed(const Duration(milliseconds: 800));
      _exitToHome();
      return;
    }

    _fadeController.forward();
    await _springController.forward();
    if (!mounted) return;

    _ringController.repeat();
    setState(() => _ready = true);

    try {
      final controller = ConversationControllerScope.of(context);
      controller.speak('VisionMate ready');
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    _exitToHome();
  }

  void _exitToHome() {
    if (!mounted) return;
    _ringController.stop();
    _springController.reverse();

    if (_reduceMotion) {
      Navigator.pushReplacementNamed(context, '/home');
      return;
    }

    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  void dispose() {
    _springController.dispose();
    _fadeController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = _reduceMotion;

    return ScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _exitToHome(),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (!reduce)
                        AnimatedBuilder(
                          animation: _ringController,
                          builder: (context, _) {
                            final t = _ringController.value;
                            final ringSize = 80 + (120 * t);
                            final opacity = (1 - t) * 0.4;
                            return Container(
                              width: ringSize,
                              height: ringSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.cyan.withValues(alpha: opacity),
                                  width: 1.5,
                                ),
                              ),
                            );
                          },
                        ),
                      if (!reduce)
                        AnimatedBuilder(
                          animation: _ringController,
                          builder: (context, _) {
                            final t = (_ringController.value + 0.5) % 1.0;
                            final ringSize = 80 + (120 * t);
                            final opacity = (1 - t) * 0.4;
                            return Container(
                              width: ringSize,
                              height: ringSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.blue.withValues(alpha: opacity),
                                  width: 1.5,
                                ),
                              ),
                            );
                          },
                        ),
                      FadeTransition(
                        opacity: _fadeController,
                        child: ScaleTransition(
                          scale: reduce
                              ? const AlwaysStoppedAnimation(1.0)
                              : _springAnimation,
                          child: Container(
                            width: 142,
                            height: 142,
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
                                  color: AppColors.blue.withValues(alpha: .35),
                                  blurRadius: 40,
                                  spreadRadius: 6,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.visibility_rounded,
                              color: Colors.white,
                              size: 52,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 34),
                FadeTransition(
                  opacity: _fadeController,
                  child: Column(
                    children: [
                      const Text(
                        'VisionMate',
                        style: TextStyle(
                          fontSize: 31,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _ready ? 'Ready' : 'Your Vision. Your Voice. Your Companion.',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      if (_ready) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Tap anywhere to begin',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.cyan.withValues(alpha: _ready ? 1.0 : 0.6),
                          ),
                        ),
                      ],
                    ],
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

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => AppPage(
    child: Column(
      children: [
        const Spacer(),
        const GlowOrb(icon: Icons.accessibility_new_rounded, size: 150),
        const SizedBox(height: 34),
        const Text(
          'Welcome to\nVisionMate.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Your voice-first assistant. Just speak, and we’ll read, guide, and keep you moving through the world.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, height: 1.45),
        ),
        const Spacer(),
        PrimaryButton(
          label: 'Get started',
          icon: Icons.arrow_forward_rounded,
          onPressed: () => Navigator.pushNamed(context, '/permissions'),
        ),
        const SizedBox(height: 14),
        const Text(
          'By continuing, you agree to our Terms & Privacy Policy',
          style: TextStyle(color: AppColors.muted, fontSize: 10),
        ),
        const SizedBox(height: 18),
      ],
    ),
  );
}

class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({super.key});
  @override
  Widget build(BuildContext context) => AppPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        const Text(
          'STEP 1 OF 3',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.cyan,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Enable your senses',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const Text(
          'Grant access so VisionMate can guide you.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 25),
        const _Permission(
          icon: Icons.mic_rounded,
          title: 'Microphone',
          body: 'Hear your voice commands',
          granted: true,
        ),
        const _Permission(
          icon: Icons.camera_alt_rounded,
          title: 'Camera',
          body: 'Read labels and describe scenes',
        ),
        const _Permission(
          icon: Icons.location_on_rounded,
          title: 'Location',
          body: 'Guide you safely, wherever you go',
        ),
        const _Permission(
          icon: Icons.notifications_rounded,
          title: 'Notifications',
          body: 'Keep safety alerts visible',
        ),
        const _Permission(
          icon: Icons.vibration_rounded,
          title: 'Motion',
          body: 'Recognize falls and sudden movements',
        ),
        const Spacer(),
        PrimaryButton(
          label: 'Allow Microphone',
          icon: Icons.check_rounded,
          onPressed: () => Navigator.pushNamed(context, '/sign-in'),
        ),
        const SizedBox(height: 16),
      ],
    ),
  );
}

class _Permission extends StatelessWidget {
  final IconData icon;
  final String title, body;
  final bool granted;
  const _Permission({
    required this.icon,
    required this.title,
    required this.body,
    this.granted = false,
  });
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.cyan.withValues(alpha: .15),
          child: Icon(icon, color: AppColors.cyan),
        ),
        title: Text(title),
        subtitle: Text(body),
        trailing: Icon(
          granted ? Icons.check_circle : Icons.chevron_right,
          color: granted ? AppColors.cyan : Colors.white70,
        ),
      ),
    ),
  );
}

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});
  @override
  Widget build(BuildContext context) => AppPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Row(
          children: [
            GlowOrb(icon: Icons.visibility_rounded, size: 38),
            SizedBox(width: 10),
            Text(
              'VisionMate',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ],
        ),
        const SizedBox(height: 42),
        const Text(
          'Welcome back',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 22),
        const _Input(icon: Icons.person_outline, hint: 'you@example.com'),
        const SizedBox(height: 12),
        const _Input(icon: Icons.lock_outline, hint: 'Password', obscure: true),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {},
            child: const Text(
              'Forgot password?',
              style: TextStyle(color: AppColors.cyan),
            ),
          ),
        ),
        PrimaryButton(
          label: 'Log in',
          icon: Icons.login_rounded,
          onPressed: () =>
              Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false),
        ),
        const SizedBox(height: 16),
        const Row(
          children: [
            Expanded(child: Divider(color: AppColors.outline)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('or'),
            ),
            Expanded(child: Divider(color: AppColors.outline)),
          ],
        ),
        const SizedBox(height: 15),
        SizedBox(
          width: double.infinity,
          height: 51,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.outline),
            ),
            onPressed: () => Navigator.pushNamedAndRemoveUntil(
              context,
              '/home',
              (_) => false,
            ),
            icon: const Icon(Icons.g_mobiledata_rounded),
            label: const Text('Continue with Google'),
          ),
        ),
        const Spacer(),
        const Center(
          child: Text(
            'New here? Create an account',
            style: TextStyle(color: AppColors.cyan),
          ),
        ),
        const SizedBox(height: 18),
      ],
    ),
  );
}

class _Input extends StatelessWidget {
  final IconData icon;
  final String hint;
  final bool obscure;
  const _Input({required this.icon, required this.hint, this.obscure = false});
  @override
  Widget build(BuildContext c) => TextField(
    obscureText: obscure,
    decoration: InputDecoration(
      prefixIcon: Icon(icon, color: AppColors.cyan),
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.muted),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
    ),
  );
}

class SpeakScreen extends StatefulWidget {
  const SpeakScreen({super.key});

  @override
  State<SpeakScreen> createState() => _SpeakScreenState();
}

class _SpeakScreenState extends State<SpeakScreen> {
  late final ConversationController _controller;
  final ScrollController _scrollController = ScrollController();
  String? _startupError;
  String? _lastError;
  bool _isSubscribed = false;
  StreamSubscription<Object>? _errorSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isSubscribed) return;
    _controller = ConversationControllerScope.of(context);
    _controller.addListener(_onControllerChanged);
    // Previously nothing ever assigned _lastError, so the error banner
    // below could never appear even though the controller was reporting
    // failures. Subscribing here surfaces every STT/Groq/TTS/channel
    // error the controller sees while this screen is open.
    _errorSubscription = _controller.errors.listen(_onControllerError);
    _isSubscribed = true;
    _init();
  }

  Future<void> _init() async {
    final ok = await _controller.initialize();
    if (!ok && mounted) {
      setState(() {
        _startupError = 'Microphone access is needed for VisionMate to listen.';
      });
    }
  }

  void _onControllerError(Object error) {
    if (!mounted) return;
    setState(() => _lastError = _friendlyErrorMessage(error));
  }

  String _friendlyErrorMessage(Object error) {
    // Keep this short — it renders in a single-line banner. The full
    // error is still available in the debug/log output via onError.
    final text = error.toString();
    return text.length > 120 ? '${text.substring(0, 117)}...' : text;
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    // Keep the latest message in view as the chat grows/streams in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients ||
          !_scrollController.position.hasContentDimensions) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    if (_isSubscribed) _controller.removeListener(_onControllerChanged);
    _errorSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VisionMateScaffold(
    padded: false,
    body: Column(
      children: [
        const SizedBox(height: 8),
        const Row(
          children: [
            SizedBox(width: 20),
            Text(
              'VisionMate',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            Spacer(),
            Icon(Icons.notifications_none_rounded),
            SizedBox(width: 20),
          ],
        ),
        const SizedBox(height: 8),
        if (_lastError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _lastError = null),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: .4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.danger,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lastError!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.close,
                        color: AppColors.danger,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: _startupError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Text(
                      _startupError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                )
              : _controller.messages.isEmpty
              ? const _EmptyChatHint()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: _controller.messages.length,
                  itemBuilder: (context, i) =>
                      _ChatBubble(message: _controller.messages[i]),
                ),
        ),
        SizedBox(
          height: 78,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: const [
              _QuickMode(
                icon: Icons.navigation_rounded,
                label: 'Navigate',
                route: '/navigate',
              ),
              _QuickMode(
                icon: Icons.menu_book_rounded,
                label: 'Read',
                route: '/read',
              ),
              _QuickMode(
                icon: Icons.directions_bus_rounded,
                label: 'Travel',
                route: '/travel',
              ),
              _QuickMode(
                icon: Icons.sos_rounded,
                label: 'Help',
                route: '/help',
                danger: true,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _EmptyChatHint extends StatelessWidget {
  const _EmptyChatHint();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 36),
      child: Text(
        'Hold the mic button or Volume Up, then tell me what you need. I can read something, get directions, or just chat.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.muted),
      ),
    ),
  );
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser
            ? AppColors.cyan.withValues(alpha: .22)
            : AppColors.surface.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message.text.isEmpty ? '…' : message.text,
        style: const TextStyle(color: AppColors.text, height: 1.35),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [bubble],
      ),
    );
  }
}

class _QuickMode extends StatelessWidget {
  const _QuickMode({
    required this.icon,
    required this.label,
    required this.route,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final String route;
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.pushNamed(context, route),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: danger ? AppColors.danger : AppColors.cyan,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ),
  );
}

class ProcessingScreen extends StatelessWidget {
  const ProcessingScreen({super.key});

  @override
  Widget build(BuildContext context) => AppPage(
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlowOrb(
            icon: Icons.auto_awesome_rounded,
            size: 155,
            active: ConversationControllerScope.of(context).isThinking,
          ),
          const SizedBox(height: 28),
          Text(
            ConversationControllerScope.of(context).isThinking
                ? 'Understanding your request...'
                : 'Ready for your next request',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ),
  );
}
