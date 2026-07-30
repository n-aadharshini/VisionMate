import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/services/location_service.dart' as loc;
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_ui.dart';
import '../../../../core/widgets/compass_ring.dart';
import '../../../../core/widgets/road_crossing_overlay.dart';
import '../../../../core/widgets/vision_mate_scaffold.dart';
import '../../../assistant/services/conversation_controller.dart';

enum NavScreenState { summary, guided, arrived }

enum GpsQuality { searching, good, error }

class NavigateScreen extends StatefulWidget {
  const NavigateScreen({super.key});

  @override
  State<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends State<NavigateScreen>
    with TickerProviderStateMixin {
  NavScreenState _state = NavScreenState.summary;
  int _stepIndex = 0;
  int _remainingDistance = 0;
  double _heading = 0.0;
  bool _offRoute = false;
  bool _showCrossing = false;
  bool _turnApproaching = false;
  GpsQuality _gpsQuality = GpsQuality.searching;
  String? _gpsErrorMessage;

  final loc.GeolocatorLocationService _locationService = loc.GeolocatorLocationService();
  StreamSubscription<loc.GpsPosition>? _gpsSubscription;

  Timer? _simTimer;
  Timer? _headingTimer;
  Timer? _turnPulseTimer;
  Timer? _rerouteTimer;

  late final AnimationController _entryController;
  late final AnimationController _routeDrawController;
  late final AnimationController _turnPulseController;
  late final AnimationController _rerouteBannerController;
  late final ConversationController _conversation;

  int _lastCueDistance = 0;
  final Set<int> _firedCues = {};

  _MockRoute get _route {
    final argument = ModalRoute.of(context)?.settings.arguments;
    final destination = argument is String && argument.trim().isNotEmpty
        ? argument.trim()
        : 'Koyambedu';
    return _MockRoute.forDestination(destination);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _conversation = ConversationControllerScope.of(context);
  }

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _routeDrawController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _turnPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _rerouteBannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _entryController.forward();
    _routeDrawController.forward();

    _initLocationService();
  }

  Future<void> _initLocationService() async {
    final result = await _locationService.getCurrentLocation(
      timeout: const Duration(seconds: 10),
    );
    if (!mounted) return;
    setState(() {
      _gpsQuality = switch (result) {
        loc.LocationSuccess() => GpsQuality.good,
        loc.LocationTimeout() => GpsQuality.error,
        _ => GpsQuality.error,
      };
      _gpsErrorMessage = (result is! loc.LocationSuccess) ? loc.describeLocationResult(result) : null;
    });

    if (result is loc.LocationSuccess) {
      _headingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) {
          setState(() => _heading = (_heading + 2) % 360);
        }
      });
      _locationService.startListening();
      _gpsSubscription = _locationService.positionStream.listen((position) {
        if (mounted) {
          setState(() {
            _gpsQuality = GpsQuality.good;
          });
        }
      });
    }
  }

  void _startGuidance() {
    if (_gpsQuality == GpsQuality.error && _gpsErrorMessage != null) {
      _conversation.speak(_gpsErrorMessage!);
      return;
    }
    setState(() => _state = NavScreenState.guided);
    final route = _route;
    final total = route.steps.fold<int>(0, (s, e) => s + e.distanceMeters);
    _remainingDistance = total;
    _lastCueDistance = total;
    _firedCues.clear();
    _startStepSimulation();
  }

  void _startStepSimulation() {
    _simTimer?.cancel();
    final route = _route;
    if (_stepIndex >= route.steps.length) return;
    final currentStep = route.steps[_stepIndex];
    var stepRemaining = currentStep.distanceMeters;

    _simTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final reduce = MediaQuery.of(context).disableAnimations;
      stepRemaining = (stepRemaining - (reduce ? 50 : 20)).clamp(0, stepRemaining);
      final totalRemaining = route.steps
          .skip(_stepIndex)
          .fold<int>(0, (s, e) => s + e.distanceMeters);

      setState(() {
        _remainingDistance = totalRemaining -
            (currentStep.distanceMeters - stepRemaining);
        _turnApproaching = stepRemaining < 60;
      });

      _checkTurnCues(stepRemaining);

      if (stepRemaining <= 1) {
        _simTimer?.cancel();
        _turnPulseController.stop();
        setState(() => _turnApproaching = false);
        _advanceStep();
      }
    });
  }

  void _checkTurnCues(int distance) {
    for (final threshold in [50, 20, 5]) {
      if (distance <= threshold && threshold > _lastCueDistance && !_firedCues.contains(threshold)) {
        _firedCues.add(threshold);
        AppHaptics.shortShortLong();
        _conversation.speak(
          threshold == 5
              ? 'Turn now'
              : 'Turn in $threshold meters',
        );
        if (threshold == 20) {
          AppHaptics.shortShortLong();
          _turnPulseController.repeat(reverse: true);
        }
      }
    }
    _lastCueDistance = distance;
  }

  void _advanceStep() {
    final route = _route;
    if (_stepIndex + 1 >= route.steps.length) {
      setState(() {
        _state = NavScreenState.arrived;
        _remainingDistance = 0;
      });
      return;
    }
    setState(() => _stepIndex++);
    _lastCueDistance = route.steps[_stepIndex].distanceMeters;
    _firedCues.clear();
    _startStepSimulation();
  }

  void _simulateReroute() {
    setState(() => _offRoute = true);
    _rerouteBannerController.forward();
    AppHaptics.heavy();
    _conversation.speak('Rerouting');
    _rerouteTimer?.cancel();
    _rerouteTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _offRoute = false);
        _rerouteBannerController.reverse();
      }
    });
  }

  void _repeatInstruction() {
    final route = _route;
    _conversation.speak(route.steps[_stepIndex].instruction);
  }

  void _cancelNavigation() {
    _simTimer?.cancel();
    _turnPulseTimer?.cancel();
    _rerouteTimer?.cancel();
    _turnPulseController.stop();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _routeDrawController.dispose();
    _turnPulseController.dispose();
    _rerouteBannerController.dispose();
    _simTimer?.cancel();
    _headingTimer?.cancel();
    _turnPulseTimer?.cancel();
    _rerouteTimer?.cancel();
    _gpsSubscription?.cancel();
    _locationService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final reduce = MediaQuery.of(context).disableAnimations;

    return AnimatedBuilder(
      animation: _entryController,
      builder: (context, _) {
        final slideOffset = reduce ? 0.0 : (1.0 - _entryController.value) * 40;

        return Transform.translate(
          offset: Offset(0, slideOffset),
          child: Opacity(
            opacity: reduce ? 1.0 : _entryController.value,
            child: Stack(
              children: [
                VisionMateScaffold(
                  body: _buildBody(route),
                ),
                if (_showCrossing)
                  RoadCrossingOverlay(
                    state: CrossingState.wait,
                    onDismiss: () => setState(() => _showCrossing = false),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(_MockRoute route) {
    return switch (_state) {
      NavScreenState.summary => _SummaryView(
          key: const ValueKey('summary'),
          route: route,
          gpsQuality: _gpsQuality,
          gpsErrorMessage: _gpsErrorMessage,
          onStartGuidance: _startGuidance,
        ),
      NavScreenState.guided => _GuidedView(
          key: const ValueKey('guided'),
          route: route,
          stepIndex: _stepIndex,
          remainingDistance: _remainingDistance,
          heading: _heading,
          offRoute: _offRoute,
          turnApproaching: _turnApproaching,
          gpsQuality: _gpsQuality,
          turnPulseController: _turnPulseController,
          rerouteBannerController: _rerouteBannerController,
          onNext: _advanceStep,
          onRepeat: _repeatInstruction,
          onCancel: _cancelNavigation,
          onReroute: _simulateReroute,
          onCross: () => setState(() => _showCrossing = true),
        ),
      NavScreenState.arrived => _ArrivedView(
          key: const ValueKey('arrived'),
          destination: route.destination,
          onNewNavigation: () => setState(() {
            _stepIndex = 0;
            _state = NavScreenState.summary;
          }),
        ),
    };
  }
}

class _SummaryView extends StatelessWidget {
  const _SummaryView({
    super.key,
    required this.route,
    required this.gpsQuality,
    required this.gpsErrorMessage,
    required this.onStartGuidance,
  });
  final _MockRoute route;
  final GpsQuality gpsQuality;
  final String? gpsErrorMessage;
  final VoidCallback onStartGuidance;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _GpsIndicator(quality: gpsQuality, message: gpsErrorMessage),
      const SizedBox(height: 12),
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
      const SizedBox(height: 12),
      PrimaryButton(label: 'Start guidance', icon: Icons.directions_walk_rounded, onPressed: onStartGuidance),
    ],
  );
}

class _GuidedView extends StatefulWidget {
  const _GuidedView({
    super.key,
    required this.route,
    required this.stepIndex,
    required this.remainingDistance,
    required this.heading,
    required this.offRoute,
    required this.turnApproaching,
    required this.gpsQuality,
    required this.turnPulseController,
    required this.rerouteBannerController,
    required this.onNext,
    required this.onRepeat,
    required this.onCancel,
    required this.onReroute,
    required this.onCross,
  });

  final _MockRoute route;
  final int stepIndex;
  final int remainingDistance;
  final double heading;
  final bool offRoute;
  final bool turnApproaching;
  final GpsQuality gpsQuality;
  final AnimationController turnPulseController;
  final AnimationController rerouteBannerController;
  final VoidCallback onNext;
  final VoidCallback onRepeat;
  final VoidCallback onCancel;
  final VoidCallback onReroute;
  final VoidCallback onCross;

  @override
  State<_GuidedView> createState() => _GuidedViewState();
}

class _GuidedViewState extends State<_GuidedView> {
  @override
  Widget build(BuildContext context) {
    final step = widget.route.steps[widget.stepIndex];
    final stepDistance = widget.remainingDistance;
    final etaMin = ((stepDistance / 300) * 5).ceil().clamp(1, 999);
    final reduce = MediaQuery.of(context).disableAnimations;

    return Semantics(
      label: 'Navigation active. ${step.instruction}.'
          ' $stepDistance metres remaining. About $etaMin minutes.',
      child: Column(
        children: [
          AnimatedBuilder(
            animation: widget.rerouteBannerController,
            builder: (context, _) {
              if (!widget.offRoute) return const SizedBox.shrink();
              final slide = reduce ? 0.0 : (1.0 - widget.rerouteBannerController.value) * -40;
              return Transform.translate(
                offset: Offset(0, slide),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(children: [
                      const Icon(Icons.warning_rounded, color: Colors.white),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Rerouting', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                      TextButton(
                        onPressed: widget.onReroute,
                        child: const Text('Simulate', style: TextStyle(color: Colors.white70)),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _GpsIndicator(quality: widget.gpsQuality),
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    label: step.instruction,
                    child: Text(
                      step.instruction,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '$stepDistance m remaining',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
                  Text(
                    'About $etaMin min',
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  CompassRing(
                    heading: widget.heading,
                    size: 130,
                  ),
                  const SizedBox(height: 6),
                  const SizedBox(height: 24),
                  AnimatedBuilder(
                    animation: widget.turnPulseController,
                    builder: (context, _) {
                      final scale = widget.turnApproaching && !reduce
                          ? 1.0 + (widget.turnPulseController.value * 0.2)
                          : 1.0;
                      return Transform.scale(
                        scale: scale,
                        child: Icon(
                          Icons.turn_right_rounded,
                          size: 72,
                          color: widget.turnApproaching
                              ? AppColors.cyan
                              : AppColors.muted,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'In $stepDistance metres',
                    style: const TextStyle(color: AppColors.muted, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Step ${widget.stepIndex + 1} of ${widget.route.steps.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          label: 'Repeat instruction',
                          button: true,
                          child: SizedBox(
                            height: 56,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.outline),
                              ),
                              onPressed: widget.onRepeat,
                              icon: const Icon(Icons.replay_rounded),
                              label: const Text('Repeat'),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Semantics(
                          label: 'Cancel navigation',
                          button: true,
                          child: SizedBox(
                            height: 56,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.outline),
                              ),
                              onPressed: widget.onCancel,
                              icon: const Icon(Icons.close_rounded),
                              label: const Text('Cancel'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          label: 'Simulate rerouting',
                          button: true,
                          child: SizedBox(
                            height: 48,
                            child: TextButton.icon(
                              onPressed: widget.onReroute,
                              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                              label: const Text('Reroute', style: TextStyle(fontSize: 13)),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Semantics(
                          label: 'Road crossing',
                          button: true,
                          child: SizedBox(
                            height: 48,
                            child: TextButton.icon(
                              onPressed: widget.onCross,
                              icon: const Icon(Icons.signpost_rounded, size: 18),
                              label: const Text('Crossing', style: TextStyle(fontSize: 13)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.stepIndex + 1 < widget.route.steps.length) ...[
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'Skip to next step',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: widget.onNext,
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsIndicator extends StatelessWidget {
  const _GpsIndicator({required this.quality, this.message});
  final GpsQuality quality;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (quality) {
      GpsQuality.searching => ('Searching', AppColors.warning),
      GpsQuality.good => ('Good', AppColors.success),
      GpsQuality.error => ('Not available', AppColors.danger),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              'GPS $label',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
        if (message != null && quality != GpsQuality.good)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              message!,
              style: const TextStyle(fontSize: 13, color: AppColors.danger),
            ),
          ),
      ],
    );
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
    _MockStep('Head north on Poonamallee High Road', 300),
    _MockStep('Turn right onto Market Road', 80),
    _MockStep('Continue straight for 1.2 km', 1200),
    _MockStep('Turn left toward the destination', 250),
    _MockStep('Destination will be on your right', 100),
  ]);
}

class _MockStep {
  const _MockStep(this.instruction, this.distanceMeters);
  final String instruction; final int distanceMeters;
}
