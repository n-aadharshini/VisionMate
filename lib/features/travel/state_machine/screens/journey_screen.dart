import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_ui.dart';
import '../../../assistant/services/conversation_controller.dart';
import '../../controllers/travel_controller.dart';
import '../../models/travel_state.dart';
import '../../repositories/routes_repository.dart';
import '../../repositories/stops_repository.dart';
import '../../services/default_journey_planner_service.dart';
import '../../services/geofence_service.dart';
import '../../services/geolocator_gps_service.dart';
import '../../services/nominatim_geocoding_service.dart';
import '../../services/navigation_service.dart';

/// The real screen behind both `/navigate` and `/travel`.
///
/// This is the piece that was missing: it reads the destination string
/// ConversationSessionController hands off via NavigationRequest.arguments,
/// constructs a [TravelController] wired to the real Phase 1/2 services,
/// and calls [TravelController.startJourney] immediately — no further tap
/// needed, per the spec's hands-free flow. Every [TravelState] change
/// re-renders this screen automatically via the controller's
/// [TravelController.onStateChange] stream.
///
/// Geocoding uses [NominatimGeocodingService] (OpenStreetMap, free, no
/// API key) — see that file's doc comment for its rate-limit/accuracy
/// trade-offs versus a paid provider.
class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key, required this.title});

  final String title;

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  late final TravelController _travelController;
  StreamSubscription<TravelState>? _stateSubscription;
  TravelState _state = TravelState.idle;
  String? _destination;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    _destination = args is String && args.trim().isNotEmpty
        ? args.trim()
        : null;

    final conversationController = ConversationControllerScope.of(context);
    _travelController = _buildTravelController(conversationController.speak);
    _stateSubscription = _travelController.onStateChange.listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
    });

    if (_destination != null) {
      // Hands-free: no further tap needed once a destination is known,
      // per the spec's "I'll start guiding you" flow.
      unawaited(_travelController.startJourney(_destination!));
    }
  }

  /// Wires the real Phase 1/2/4 services together.
  TravelController _buildTravelController(Future<void> Function(String) speak) {
    final geofence = HaversineGeofenceService();
    final stops = StopsRepository(geofenceService: geofence);
    final routes = RoutesRepository();
    final journeyPlanner = DefaultJourneyPlannerService(
      geocodingService: NominatimGeocodingService(),
      stopsRepository: stops,
      routesRepository: routes,
      geofenceService: geofence,
    );

    return TravelController(
      speak: speak,
      gpsService: GeolocatorGpsService(),
      geofenceService: geofence,
      journeyPlannerService: journeyPlanner,
      navigationService: OsrmNavigationService(),
    );
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _travelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversation = ConversationControllerScope.of(context);
    final lastMessage = conversation.messages.isEmpty
        ? 'You can keep speaking while guidance is open.'
        : conversation.messages.last.text;
    return AppPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          widget.title,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        if (_destination != null)
          Text(
            'To $_destination',
            style: const TextStyle(color: AppColors.muted),
          ),
        const Spacer(),
        Center(
          child: GlowOrb(
            icon: _iconFor(_state),
            size: 150,
            active: _state != TravelState.idle && _state != TravelState.error,
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: Text(
            _labelFor(_state, _destination),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        const Spacer(),
        if (_destination == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 24),
            child: Text(
              'Say a destination, e.g. "Take me to Agni College" — '
              'this screen only guides a journey once one is known.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        if (_state == TravelState.completed || _state == TravelState.error)
          PrimaryButton(
            label: 'Done',
            icon: Icons.check_rounded,
            onPressed: () => Navigator.of(context).pop(),
          ),
        MiniChatStrip(
          text: lastMessage,
          onTap: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 16),
      ],
    ),
    );
  }

  IconData _iconFor(TravelState state) => switch (state) {
    TravelState.idle => Icons.explore_outlined,
    TravelState.listening => Icons.hearing_rounded,
    TravelState.planning => Icons.auto_awesome_rounded,
    TravelState.navigateToBusStop => Icons.directions_walk_rounded,
    TravelState.waitingForBus => Icons.directions_bus_filled_rounded,
    TravelState.onBus => Icons.directions_bus_rounded,
    TravelState.navigateToDestination => Icons.directions_walk_rounded,
    TravelState.completed => Icons.flag_rounded,
    TravelState.error => Icons.error_outline_rounded,
  };

  String _labelFor(TravelState state, String? destination) => switch (state) {
    TravelState.idle => 'Ready',
    TravelState.listening => 'Listening...',
    TravelState.planning => 'Planning your route...',
    TravelState.navigateToBusStop => 'Walking to the bus stop...',
    TravelState.waitingForBus => 'Waiting for the bus...',
    TravelState.onBus => 'On the bus...',
    TravelState.navigateToDestination => 'Walking to your destination...',
    TravelState.completed => 'You have arrived.',
    TravelState.error => "Something went wrong — let's try again.",
  };
}
