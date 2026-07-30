import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/app_haptics.dart';
import '../../core/widgets/app_ui.dart';
import '../../core/widgets/mic_orb.dart';
import '../../core/widgets/quick_actions_sheet.dart';
import '../../core/widgets/vision_mate_scaffold.dart';
import '../assistant/services/conversation_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ConversationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = ConversationControllerScope.of(context);
  }

  void _showQuickActions() {
    AppHaptics.light();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: QuickActionsSheet(),
      ),
    );
  }

  void _onOrbTap() {
    final c = _controller;
    if (c == null) return;
    if (c.state != ConversationState.idle) return;
    c.beginPushToTalk();
  }

  void _onOrbLongPress() {
    final c = _controller;
    if (c == null) return;
    c.speak('SOS activated');
    Navigator.pushNamed(context, '/sos');
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final isActive = c != null && c.state != ConversationState.idle;

    return VisionMateScaffold(
      padded: false,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () {
          AppHaptics.light();
        },
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity! < -200) {
            _showQuickActions();
          }
        },
        child: Stack(
          children: [
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'VisionMate',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap the mic or say a command',
                    style: TextStyle(color: AppColors.muted, fontSize: 14),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: MicOrb(
                  active: isActive,
                  onTap: _onOrbTap,
                  onLongPress: _onOrbLongPress,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReadScreen extends StatelessWidget {
  const ReadScreen({super.key});
  @override
  Widget build(BuildContext c) => AppPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Row(
          children: [
            AppBackButton(),
            Spacer(),
            Text('Read Mode', style: TextStyle(fontWeight: FontWeight.w800)),
            SizedBox(width: 45),
          ],
        ),
        const SizedBox(height: 14),
        AppCard(
          child: SizedBox(
            height: 255,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  margin: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cyan, width: 2),
                  ),
                ),
                const Icon(
                  Icons.document_scanner_outlined,
                  size: 80,
                  color: AppColors.cyan,
                ),
                const Positioned(
                  bottom: 30,
                  child: Chip(
                    label: Text('Detected text'),
                    backgroundColor: AppColors.surfaceLight,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 13),
        const AppCard(
          child: ListTile(
            leading: Icon(Icons.auto_awesome, color: AppColors.cyan),
            title: Text('DETECTED TEXT'),
            subtitle: Text(
              'Platform 5, Gate 3 • Central Station. Boarding in 4 minutes.',
            ),
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            _RoundAction(Icons.play_arrow_rounded, 'Listen'),
            _RoundAction(Icons.copy_rounded, 'Copy'),
            _RoundAction(Icons.translate_rounded, 'Translate'),
            _RoundAction(Icons.share_outlined, 'Share'),
          ],
        ),
        const Spacer(),
        PrimaryButton(
          label: 'Scan text',
          icon: Icons.camera_alt_rounded,
          onPressed: () => Navigator.pushNamed(c, '/processing'),
        ),
        const SizedBox(height: 16),
      ],
    ),
  );
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String label;
  const _RoundAction(this.icon, this.label);
  @override
  Widget build(BuildContext c) => Expanded(
    child: Column(
      children: [
        CircleAvatar(
          backgroundColor: AppColors.surfaceLight,
          child: Icon(icon, color: AppColors.cyan),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.muted),
        ),
      ],
    ),
  );
}

class IndoorNavigationScreen extends StatelessWidget {
  const IndoorNavigationScreen({super.key});
  @override
  Widget build(BuildContext c) => AppPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Row(
          children: [
            AppBackButton(),
            SizedBox(width: 8),
            Text('Read Mode', style: TextStyle(fontWeight: FontWeight.w800)),
            Spacer(),
            Icon(Icons.flash_on_outlined),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Skyline Tower - Floor 2',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: AppCard(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  margin: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.cyan),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const GlowOrb(icon: Icons.navigation_rounded, size: 58),
                const Positioned(
                  bottom: 25,
                  child: Chip(label: Text('You are here')),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const AppCard(
          child: ListTile(
            leading: Icon(Icons.auto_awesome, color: AppColors.cyan),
            title: Text('DETECTED TEXT'),
            subtitle: Text('Platform 5, Gate 3 • Central Station'),
          ),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: 'Begin navigation',
          icon: Icons.navigation_rounded,
          onPressed: () => Navigator.pushNamed(c, '/arrived'),
        ),
        const SizedBox(height: 16),
      ],
    ),
  );
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext c) => AppPage(
    child: Column(
      children: [
        const SizedBox(height: 24),
        const Text(
          'HELP & SAFETY',
          style: TextStyle(
            color: AppColors.danger,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'You are not alone.',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
        ),
        const Spacer(),
        const GlowOrb(
          icon: Icons.health_and_safety_rounded,
          size: 154,
          active: true,
        ),
        const SizedBox(height: 22),
        const Text(
          'Need immediate help?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const Text(
          'Your emergency contacts will be notified.',
          style: TextStyle(color: AppColors.muted),
        ),
        const Spacer(),
        PrimaryButton(
          label: 'Hold for SOS',
          icon: Icons.sos_rounded,
          onPressed: () => Navigator.pushNamed(c, '/sos'),
        ),
        const SizedBox(height: 12),
        const AppCard(
          child: ListTile(
            leading: Icon(Icons.contact_phone, color: AppColors.cyan),
            title: Text('Emergency contacts'),
            subtitle: Text('Mom, Dad, Neighbour'),
            trailing: Icon(Icons.chevron_right),
          ),
        ),
        const SizedBox(height: 16),
      ],
    ),
  );
}

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});
  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  int seconds = 5;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (seconds <= 1) {
        timer.cancel();
      } else {
        setState(() => seconds--);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF210E20),
    body: Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: .9,
          colors: [Color(0xFF8B203C), Color(0xFF210E20)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 28),
              const Text(
                'EMERGENCY SOS',
                style: TextStyle(
                  color: Color(0xFFFFABBB),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Hold to send SOS',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const Text(
                'Alert your emergency contacts',
                style: TextStyle(color: Color(0xFFFFB9C5)),
              ),
              const Spacer(),
              Container(
                width: 208,
                height: 208,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.danger,
                  boxShadow: [BoxShadow(color: Colors.red, blurRadius: 48)],
                ),
                child: Center(
                  child: Text(
                    '$seconds\nSOS',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Sending location in $seconds seconds',
                style: const TextStyle(color: Color(0xFFFFBAC6)),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFB64F65)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ),
  );
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext c) => AppPage(
    padded: false,
    child: Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recent activity',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Wrap(
                  spacing: 8,
                  children: [
                    Chip(label: Text('All')),
                    Chip(label: Text('Read Mode')),
                    Chip(label: Text('Travel')),
                  ],
                ),
                const SizedBox(height: 10),
                const Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _Activity(
                          Icons.menu_book,
                          'Read: Medicine label',
                          'Today · 10:42 AM',
                        ),
                        _Activity(
                          Icons.navigation,
                          'Navigation: Home → Library',
                          'Today · 9:18 AM',
                        ),
                        _Activity(
                          Icons.mic,
                          'Voice command',
                          'Yesterday · 7:20 PM',
                        ),
                        _Activity(
                          Icons.sos,
                          'SOS test completed',
                          'Yesterday · 4:15 PM',
                          danger: true,
                        ),
                        _Activity(
                          Icons.directions_bus,
                          'Travel: Bus 21G',
                          'Monday · 9:20 AM',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const PhoneBottomNav(index: 1),
      ],
    ),
  );
}

class _Activity extends StatelessWidget {
  final IconData icon;
  final String title, time;
  final bool danger;
  const _Activity(this.icon, this.title, this.time, {this.danger = false});
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (danger ? AppColors.danger : AppColors.cyan)
              .withValues(alpha: .16),
          child: Icon(icon, color: danger ? AppColors.danger : AppColors.cyan),
        ),
        title: Text(title),
        subtitle: Text(time),
        trailing: const Icon(Icons.more_horiz, color: AppColors.cyan),
      ),
    ),
  );
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext c) => AppPage(
    padded: false,
    child: Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => Navigator.pushNamed(c, '/settings'),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ),
                const GlowOrb(icon: Icons.person_rounded, size: 108),
                const SizedBox(height: 14),
                const Text(
                  'Anika Sharma',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const Text(
                  'anika.sharma@email.com',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 22),
                const _ProfileRow(
                  Icons.language,
                  'Preferred language',
                  'English',
                ),
                const _ProfileRow(
                  Icons.contact_phone,
                  'Emergency contacts',
                  '2 contacts',
                ),
                const _ProfileRow(
                  Icons.record_voice_over,
                  'Voice settings',
                  'Calm voice',
                ),
                const _ProfileRow(
                  Icons.accessibility_new,
                  'Accessibility',
                  'Haptics and text size',
                ),
                const _ProfileRow(
                  Icons.shield_outlined,
                  'VisionMate Plus',
                  'Your plan',
                ),
                const Spacer(),
                const Text(
                  'Version 1.0.0',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
        const PhoneBottomNav(index: 2),
      ],
    ),
  );
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  const _ProfileRow(this.icon, this.title, this.sub);
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      child: ListTile(
        leading: Icon(icon, color: AppColors.cyan),
        title: Text(title),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right),
      ),
    ),
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext c) => AppPage(
    padded: false,
    child: Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Preferences',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                const _Setting('Language', 'English', false),
                const _Setting('Voice speed', 'Normal', false),
                const _Setting('Voice guidance', 'On', true),
                const _Setting('Haptic feedback', 'On', true),
                const _Setting('Offline mode', 'Use saved assistance', false),
                const SizedBox(height: 15),
                const Text(
                  'About VisionMate',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                AppCard(
                  child: ListTile(
                    onTap: () => Navigator.pushNamed(c, '/offline'),
                    leading: const Icon(
                      Icons.cloud_off_outlined,
                      color: AppColors.cyan,
                    ),
                    title: const Text('Preview offline state'),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 49,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: Color(0xFF713345)),
                    ),
                    onPressed: () =>
                        Navigator.pushNamedAndRemoveUntil(c, '/', (_) => false),
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const PhoneBottomNav(index: 3),
      ],
    ),
  );
}

class _Setting extends StatelessWidget {
  final String title, sub;
  final bool on;
  const _Setting(this.title, this.sub, this.on);
  @override
  Widget build(BuildContext c) => AppCard(
    child: SwitchListTile(
      value: on,
      onChanged: (_) {},
      activeThumbColor: AppColors.cyan,
      title: Text(title),
      subtitle: Text(sub),
    ),
  );
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext c) => AppPage(
    padded: false,
    child: Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {},
                      child: const Text('Mark all read'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const _Activity(
                  Icons.directions_bus,
                  'Bus 42 arriving',
                  'In 4 minutes',
                ),
                const _Activity(
                  Icons.sos,
                  'Battery low',
                  'Consider charging your phone',
                  danger: true,
                ),
                const _Activity(
                  Icons.verified,
                  'SOS test successful',
                  'All contacts notified',
                ),
                const _Activity(
                  Icons.menu_book,
                  'Read completed',
                  'Saved to History',
                ),
              ],
            ),
          ),
        ),
        const PhoneBottomNav(index: 0),
      ],
    ),
  );
}

class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key});
  @override
  Widget build(BuildContext c) => AppPage(
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GlowOrb(icon: Icons.cloud_off_rounded, size: 140),
          const SizedBox(height: 27),
          const Text(
            "You're offline",
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          const Text(
            'Location and saved routes still work. Navigation and travel need internet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Try again',
            icon: Icons.refresh,
            onPressed: () =>
                Navigator.pushNamedAndRemoveUntil(c, '/home', (_) => false),
          ),
          TextButton.icon(
            onPressed: () =>
                Navigator.pushNamedAndRemoveUntil(c, '/home', (_) => false),
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Use offline features'),
          ),
        ],
      ),
    ),
  );
}

class ArrivedScreen extends StatelessWidget {
  const ArrivedScreen({super.key});
  @override
  Widget build(BuildContext c) => AppPage(
    child: Column(
      children: [
        const SizedBox(height: 38),
        const GlowOrb(icon: Icons.check_rounded, size: 150, active: true),
        const SizedBox(height: 26),
        const Text(
          "You've arrived",
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        const Text(
          'Central Library · 2 min remaining to entrance',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 22),
        const AppCard(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Arrival('5:42', 'Arrival'),
                _Arrival('0.4 km', 'Distance'),
                _Arrival('7 min', 'Elapsed'),
              ],
            ),
          ),
        ),
        const Spacer(),
        PrimaryButton(
          label: 'Back to home',
          icon: Icons.home_rounded,
          onPressed: () =>
              Navigator.pushNamedAndRemoveUntil(c, '/home', (_) => false),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 49,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.outline),
            ),
            onPressed: () {},
            icon: const Icon(Icons.bookmark_outline),
            label: const Text('Save this route'),
          ),
        ),
        const SizedBox(height: 16),
      ],
    ),
  );
}

class _Arrival extends StatelessWidget {
  final String value, label;
  const _Arrival(this.value, this.label);
  @override
  Widget build(BuildContext c) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: AppColors.cyan,
          fontWeight: FontWeight.w900,
        ),
      ),
      Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
    ],
  );
}

class MicrointeractionsScreen extends StatelessWidget {
  const MicrointeractionsScreen({super.key});
  @override
  Widget build(BuildContext c) => AppPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        const Text(
          'Microinteractions',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 22),
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.05,
          children: const [
            _Mini(Icons.mic_rounded, 'Voice pulse'),
            _Mini(Icons.graphic_eq_rounded, 'Listening'),
            _Mini(Icons.circle, 'Loading'),
            _Mini(Icons.vibration_rounded, 'Haptics'),
            _Mini(Icons.more_horiz, 'Progress dots'),
            _Mini(Icons.toggle_on_rounded, 'Button glow'),
          ],
        ),
        const SizedBox(height: 14),
        const AppCard(
          child: ListTile(
            title: Text('Every interaction should feel simple + confident'),
            subtitle: Text(
              'Soft motion, meaningful feedback, and clear voice cues.',
            ),
          ),
        ),
      ],
    ),
  );
}

class _Mini extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Mini(this.icon, this.label);
  @override
  Widget build(BuildContext c) => AppCard(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GlowOrb(icon: icon, size: 55),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}
