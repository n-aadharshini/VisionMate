import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_ui.dart';
import '../../../assistant/services/conversation_controller.dart';
import 'journey_screen.dart';

enum NavScreenState { summary, guided, arrived }

class NavigateScreen extends StatefulWidget {
  const NavigateScreen({super.key});

  @override
  State<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends State<NavigateScreen> {
  NavScreenState _state = NavScreenState.summary;
  int _stepIndex = 0;

  _MockRoute get _route {
    final argument = ModalRoute.of(context)?.settings.arguments;
    final destination = argument is String && argument.trim().isNotEmpty
        ? argument.trim()
        : 'Koyambedu';
    return _MockRoute.forDestination(destination);
  }

  @override
  Widget build(BuildContext context) {
    final conversation = ConversationControllerScope.of(context);
    final lastMessage = conversation.messages.isEmpty
        ? 'Say “next step”, “how far”, or “cancel navigation”.'
        : conversation.messages.last.text;
    final route = _route;

    return FeatureScreenShell(
      title: route.destination,
      bottom: MiniChatStrip(
        text: lastMessage,
        onTap: () => Navigator.of(context).pop(),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: switch (_state) {
          NavScreenState.summary => _SummaryView(
              key: const ValueKey('summary'),
              route: route,
              onStartMockGuidance: () => setState(() => _state = NavScreenState.guided),
              onStartLiveGuidance: () => Navigator.of(context).pushNamed(
                '/navigate/live',
                arguments: route.destination,
              ),
            ),
          NavScreenState.guided => _GuidedView(
              key: const ValueKey('guided'),
              route: route,
              stepIndex: _stepIndex,
              onNext: () => setState(() {
                if (_stepIndex + 1 >= route.steps.length) {
                  _state = NavScreenState.arrived;
                } else {
                  _stepIndex++;
                }
              }),
            ),
          NavScreenState.arrived => _ArrivedView(
              key: const ValueKey('arrived'),
              destination: route.destination,
              onNewNavigation: () => setState(() {
                _stepIndex = 0;
                _state = NavScreenState.summary;
              }),
            ),
        },
      ),
    );
  }
}

class LiveNavigateScreen extends StatelessWidget {
  const LiveNavigateScreen({super.key});
  @override
  Widget build(BuildContext context) => const JourneyScreen(title: 'Live guidance');
}

class _SummaryView extends StatelessWidget {
  const _SummaryView({super.key, required this.route, required this.onStartMockGuidance, required this.onStartLiveGuidance});
  final _MockRoute route;
  final VoidCallback onStartMockGuidance;
  final VoidCallback onStartLiveGuidance;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppCard(child: Row(children: [
        const Icon(Icons.route_rounded, color: AppColors.cyan),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Route overview', style: TextStyle(fontWeight: FontWeight.w800)),
          Text('${route.distanceKm.toStringAsFixed(1)} km • ${route.etaMinutes} min', style: const TextStyle(color: AppColors.muted)),
        ])),
      ])),
      const SizedBox(height: 14),
      Expanded(child: ListView.builder(itemCount: route.steps.length, itemBuilder: (context, index) {
        final step = route.steps[index];
        return Padding(padding: const EdgeInsets.only(bottom: 10), child: AppCard(child: ListTile(
          leading: CircleAvatar(backgroundColor: AppColors.blue.withValues(alpha: .22), child: Text('${index + 1}')),
          title: Text(step.instruction), subtitle: Text('${step.distanceMeters} metres'),
        )));
      })),
      PrimaryButton(label: 'Preview guided steps', icon: Icons.directions_walk_rounded, onPressed: onStartMockGuidance),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: onStartLiveGuidance, icon: const Icon(Icons.navigation_rounded), label: const Text('Start live guidance'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52))),
    ],
  );
}

class _GuidedView extends StatelessWidget {
  const _GuidedView({super.key, required this.route, required this.stepIndex, required this.onNext});
  final _MockRoute route; final int stepIndex; final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    final step = route.steps[stepIndex];
    final remaining = route.steps.skip(stepIndex).fold<int>(0, (sum, item) => sum + item.distanceMeters);
    return Column(children: [
      AppCard(child: Row(children: [const Icon(Icons.place_rounded, color: AppColors.cyan), const SizedBox(width: 8), Expanded(child: Text('$remaining m remaining • about ${((remaining / 300) * 5).ceil()} min'))])),
      const Spacer(),
      Icon(Icons.turn_right_rounded, size: 96, color: AppColors.cyan),
      const SizedBox(height: 20),
      Text(step.instruction, textAlign: TextAlign.center, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10), Text('In ${step.distanceMeters} metres', style: const TextStyle(color: AppColors.muted, fontSize: 17)),
      const Spacer(),
      Text('Step ${stepIndex + 1} of ${route.steps.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      PrimaryButton(label: stepIndex + 1 == route.steps.length ? 'I have arrived' : 'Next step', icon: Icons.arrow_forward_rounded, onPressed: onNext),
    ]);
  }
}

class _ArrivedView extends StatelessWidget {
  const _ArrivedView({super.key, required this.destination, required this.onNewNavigation});
  final String destination; final VoidCallback onNewNavigation;
  @override
  Widget build(BuildContext context) => Center(child: AppCard(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.flag_rounded, size: 68, color: AppColors.success), const SizedBox(height: 16),
    Text("You've arrived at $destination", textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
    const SizedBox(height: 20), PrimaryButton(label: 'Start new navigation', icon: Icons.navigation_rounded, onPressed: onNewNavigation),
  ]))));
}

class _MockRoute {
  const _MockRoute(this.destination, this.distanceKm, this.etaMinutes, this.steps);
  final String destination; final double distanceKm; final int etaMinutes; final List<_MockStep> steps;
  factory _MockRoute.forDestination(String destination) => _MockRoute(destination, 4.2, 14, const [
    _MockStep('Head north on Poonamallee High Road', 300), _MockStep('Turn right onto Market Road', 800), _MockStep('Continue straight', 1200), _MockStep('Turn left toward the destination', 900), _MockStep('Destination will be on your right', 200),
  ]);
}
class _MockStep { const _MockStep(this.instruction, this.distanceMeters); final String instruction; final int distanceMeters; }
