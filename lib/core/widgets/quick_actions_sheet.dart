import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../services/app_haptics.dart';
import 'app_ui.dart';

class QuickActionsSheet extends StatelessWidget {
  const QuickActionsSheet({super.key});

  static const _actions = [
    _ActionData(Icons.menu_book_rounded, 'Read', '/read', 'Point the camera at text to read.'),
    _ActionData(Icons.navigation_rounded, 'Navigate', '/navigate', 'Get walking directions.'),
    _ActionData(Icons.explore_rounded, 'Describe', '/describe', 'Describe what is around you.'),
    _ActionData(Icons.sos_rounded, 'SOS', '/sos', 'Emergency help.', danger: true),
  ];

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.muted.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        ...List.generate(_actions.length, (i) {
          final action = _actions[i];
          final delay = i * 60;
          return _ActionCard(
            data: action,
            delay: delay,
            reduceMotion: reduceMotion,
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ActionData {
  const _ActionData(this.icon, this.label, this.route, this.hint, {this.danger = false});

  final IconData icon;
  final String label;
  final String route;
  final String hint;
  final bool danger;
}

class _ActionCard extends StatefulWidget {
  const _ActionCard({
    required this.data,
    required this.delay,
    required this.reduceMotion,
  });

  final _ActionData data;
  final int delay;
  final bool reduceMotion;

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fadeAnimation = _slideAnimation;

    if (!widget.reduceMotion) {
      Future.delayed(Duration(milliseconds: widget.delay), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    Widget card = AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          AppHaptics.light();
          Navigator.pushNamed(context, data.route);
        },
        child: Semantics(
          label: data.label,
          hint: data.hint,
          button: true,
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: data.danger
                        ? [const Color(0xFFFF6A5D), AppColors.danger]
                        : [AppColors.cyan, AppColors.blue],
                  ),
                ),
                child: Icon(data.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      data.hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );

    if (!widget.reduceMotion) {
      card = FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(_slideAnimation),
          child: card,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: card,
    );
  }
}
