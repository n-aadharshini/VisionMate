import 'dart:async';

import '../models/journey_plan.dart';
import '../models/travel_exception.dart';
import '../models/travel_state.dart';
import '../services/geofence_service.dart';
import '../services/gps_service.dart';
import '../services/journey_planner_service.dart';
import '../services/navigation_service.dart';
import '../state_machine/travel_state_machine.dart';

/// Orchestrates a full journey by driving [TravelStateMachine] with the
/// injected services. This is the single integration point the rest of
/// the app talks to — NavigateScreen (Phase 5) calls [startJourney] once
/// ConversationSessionController hands off a destination string, and
/// nothing else needs to know how the journey is actually carried out.
///
/// Every dependency is injected via the constructor, defaulting to a
/// stub, exactly like the existing `SpeechService()` pattern already used
/// in ConversationSessionController. That's what lets this class compile
/// and run today, in Phase 1, with no GPS/Maps/bus-data wiring yet —
/// later phases swap one stub for a real implementation at a time, with
/// no changes to this file's orchestration logic.
///
/// Speech is NOT owned here: a `speak` callback is injected instead of a
/// concrete TtsService, so this controller stays decoupled from your
/// existing TTS implementation. Wire it in Phase 5, e.g.:
///
///   TravelController(speak: existingTtsService.speak, ...)
///
/// so the assistant's voice and journey narration always come from the
/// one shared TtsService instance and never talk over each other.
class TravelController {
  TravelController({
    required this.speak,
    GpsService? gpsService,
    GeofenceService? geofenceService,
    JourneyPlannerService? journeyPlannerService,
    NavigationService? navigationService,
    this.busStopGeofenceRadiusMeters = 20,
    this.destinationGeofenceRadiusMeters = 15,
    this.turnNarrationRadiusMeters = 15,
  }) : _gps = gpsService ?? StubGpsService(),
       _geofence = geofenceService ?? HaversineGeofenceService(),
       _journeyPlanner = journeyPlannerService ?? StubJourneyPlannerService(),
       _navigation = navigationService ?? StubNavigationService(),
       _stateMachine = TravelStateMachine();

  final GpsService _gps;
  final GeofenceService _geofence;
  final JourneyPlannerService _journeyPlanner;
  final NavigationService _navigation;
  final TravelStateMachine _stateMachine;

  /// Injected speech sink — every user-facing announcement goes through
  /// this, never through a locally-constructed TTS instance.
  final Future<void> Function(String text) speak;

  /// Distance (meters) from the boarding stop that triggers the automatic,
  /// hands-free navigateToBusStop -> waitingForBus transition. Spec calls
  /// out 20m explicitly.
  final double busStopGeofenceRadiusMeters;

  /// Distance (meters) from the final destination that triggers the
  /// automatic navigateToDestination -> completed transition.
  final double destinationGeofenceRadiusMeters;

  /// Distance (meters) from a walking step's waypoint that counts as
  /// "reached it" — triggers speaking that step's instruction and
  /// advancing to the next one.
  final double turnNarrationRadiusMeters;

  JourneyPlan? _activePlan;
  StreamSubscription<GpsPosition>? _gpsSubscription;

  /// Walking steps for the current leg (either "to the boarding stop" or
  /// "to the final destination"), fetched from [NavigationService] once
  /// per leg. Empty until a leg's directions have been fetched, or if
  /// fetching them failed — narration is advisory-only, so a failure here
  /// never blocks the underlying geofence arrival trigger.
  List<NavigationStep> _walkingSteps = const [];
  int _walkingStepIndex = 0;

  /// Identifies which leg [_walkingSteps] currently belongs to, so
  /// [_onPositionUpdate] only fetches directions once per leg instead of
  /// re-fetching on every GPS update. Null means no leg fetched yet.
  TravelState? _walkingLegState;

  /// Guards [_updateWalkingNarration] against overlapping runs — a `speak`
  /// call can take a couple of seconds, during which several more GPS
  /// updates may arrive. Without this, those updates could kick off a
  /// second concurrent fetch/narration pass for the same leg.
  bool _narrating = false;

  TravelState get state => _stateMachine.current;
  JourneyPlan? get activePlan => _activePlan;
  Stream<TravelState> get onStateChange => _stateMachine.onChange;

  /// Entry point called once a destination has been extracted from the
  /// user's speech (idle -> listening -> planning -> first navigation
  /// state, all without further user input, per the spec).
  Future<void> startJourney(String destinationQuery) async {
    // Defensive reset in case this controller instance is reused across
    // more than one journey — a stale leg from a previous trip should
    // never bleed into a new one.
    _resetWalkingNarrationState();

    try {
      _stateMachine.transitionTo(TravelState.listening);
      _stateMachine.transitionTo(TravelState.planning);

      final position = await _gps.getCurrentPosition();
      final plan = await _journeyPlanner.planJourney(
        currentLat: position.latitude,
        currentLng: position.longitude,
        destinationQuery: destinationQuery,
      );
      _activePlan = plan;

      await speak(plan.summarySpeech);

      _stateMachine.transitionTo(
        plan.walkOnly
            ? TravelState.navigateToDestination
            : TravelState.navigateToBusStop,
      );

      _beginGpsMonitoring();
    } on TravelException catch (e) {
      await _handleFailure(e.message);
    } catch (e) {
      // Phase 1: the injected services are stubs and will throw
      // UnimplementedError here — that's expected until Phase 2/3 land.
      // This catch-all becomes real user-facing error recovery once the
      // planner/GPS are real and can fail for legitimate reasons
      // (no GPS fix, destination not found, no route available).
      await _handleFailure('I could not plan that journey yet: $e');
    }
  }

  /// Driven by geofence checks once the rider is within ~20m of the
  /// boarding stop. Exposed as an explicit method (rather than buried in
  /// a GPS callback) so tests can drive the state machine without a real
  /// GPS stream.
  void onArrivedAtBusStop() {
    if (_stateMachine.canTransitionTo(TravelState.waitingForBus)) {
      _stateMachine.transitionTo(TravelState.waitingForBus);
    }
  }

  /// Phase 1/early Phase 5: triggered by the user saying "I'm on the
  /// bus." Later this becomes automatic via geofence + bus-tracking
  /// signals, with no change needed here.
  void onBoardedBus() {
    if (_stateMachine.canTransitionTo(TravelState.onBus)) {
      _stateMachine.transitionTo(TravelState.onBus);
    }
  }

  /// Reserved for a future explicit alighting action once live bus tracking
  /// is introduced.
  void onAlightedBus() {
    if (_stateMachine.canTransitionTo(TravelState.navigateToDestination)) {
      _stateMachine.transitionTo(TravelState.navigateToDestination);
    }
  }

  /// Driven by geofence checks once the rider reaches the final
  /// destination coordinates.
  Future<void> onArrivedAtDestination() async {
    if (_stateMachine.canTransitionTo(TravelState.completed)) {
      _stateMachine.transitionTo(TravelState.completed);
      await speak('You have arrived.');
    }
  }

  /// Cancels an in-progress journey and returns to idle. Safe to call
  /// from any state — e.g. the user says "cancel" or a hard error occurs
  /// upstream in ConversationSessionController.
  void cancelJourney() {
    _gpsSubscription?.cancel();
    _gps.stopListening();
    _activePlan = null;
    _resetWalkingNarrationState();
    _stateMachine.reset();
  }

  void _resetWalkingNarrationState() {
    _walkingSteps = const [];
    _walkingStepIndex = 0;
    _walkingLegState = null;
    _narrating = false;
  }

  void _beginGpsMonitoring() {
    _gps.startListening();
    _gpsSubscription?.cancel();
    _gpsSubscription = _gps.positionStream.listen(_onPositionUpdate);
  }

  /// The one place GPS updates get turned into state transitions and
  /// turn-by-turn narration — entirely without user input, per the spec
  /// ("When distance <20 metres, automatically transition... WITHOUT
  /// USER INPUT").
  ///
  /// Only two of the four in-flight states act on raw distance here:
  ///  - navigateToBusStop: geofence around the boarding stop, plus
  ///    walking-step narration toward it.
  ///  - navigateToDestination: geofence around the final destination,
  ///    plus walking-step narration toward it.
  /// waitingForBus and onBus don't react to raw GPS distance in the current
  /// scope; live timetable and bus-tracking behavior is not implemented.
  void _onPositionUpdate(GpsPosition position) {
    final plan = _activePlan;
    if (plan == null) return;

    switch (state) {
      case TravelState.navigateToBusStop:
        final boardingStop = plan.boardingStop;
        if (boardingStop == null) return;
        unawaited(
          _updateWalkingNarration(
            TravelState.navigateToBusStop,
            position,
            boardingStop.latitude,
            boardingStop.longitude,
          ),
        );
        if (_geofence.isWithinRadius(
          position,
          boardingStop.latitude,
          boardingStop.longitude,
          busStopGeofenceRadiusMeters,
        )) {
          onArrivedAtBusStop();
        }
        break;

      case TravelState.navigateToDestination:
        unawaited(
          _updateWalkingNarration(
            TravelState.navigateToDestination,
            position,
            plan.destinationLat,
            plan.destinationLng,
          ),
        );
        if (_geofence.isWithinRadius(
          position,
          plan.destinationLat,
          plan.destinationLng,
          destinationGeofenceRadiusMeters,
        )) {
          onArrivedAtDestination();
        }
        break;

      default:
        // waitingForBus, onBus, and terminal states don't react to raw
        // GPS distance here — see doc comment above.
        break;
    }
  }

  /// Fetches walking directions once per leg (identified by [legState])
  /// and speaks each step as the rider's live position reaches its
  /// waypoint. This is purely advisory narration layered on top of the
  /// authoritative geofence arrival check in [_onPositionUpdate] — if
  /// [NavigationService] fails (e.g. OSRM unreachable), the journey still
  /// completes normally via the geofence trigger, just without turn
  /// callouts.
  Future<void> _updateWalkingNarration(
    TravelState legState,
    GpsPosition position,
    double toLat,
    double toLng,
  ) async {
    if (_narrating) return;
    _narrating = true;
    try {
      if (_walkingLegState != legState) {
        // New leg — fetch fresh directions from here to the leg's target,
        // and reset step tracking before anything else touches it.
        _walkingLegState = legState;
        _walkingStepIndex = 0;
        try {
          _walkingSteps = await _navigation.getWalkingDirections(
            fromLat: position.latitude,
            fromLng: position.longitude,
            toLat: toLat,
            toLng: toLng,
          );
        } catch (_) {
          _walkingSteps = const [];
          return;
        }
        if (_walkingSteps.isEmpty) return;
        // Speak the first instruction immediately rather than waiting for
        // the rider to physically reach its waypoint — this is the
        // "start walking, here's your first instruction" moment.
        await speak(_walkingSteps.first.instruction);
        _walkingStepIndex = 1;
        return;
      }

      // Same leg as last time — walk forward through any waypoints the
      // rider has reached since the last GPS update. A `while` (not a
      // single `if`) so a sparse GPS stream that jumps past more than one
      // waypoint between fixes doesn't leave narration permanently behind.
      while (_walkingStepIndex < _walkingSteps.length) {
        final step = _walkingSteps[_walkingStepIndex];
        if (!_geofence.isWithinRadius(
          position,
          step.latitude,
          step.longitude,
          turnNarrationRadiusMeters,
        )) {
          break;
        }
        _walkingStepIndex++;
        await speak(step.instruction);
      }
    } finally {
      _narrating = false;
    }
  }

  Future<void> _handleFailure(String message) async {
    await speak(message);
    if (_stateMachine.canTransitionTo(TravelState.error)) {
      _stateMachine.transitionTo(TravelState.error);
    }
    _gpsSubscription?.cancel();
    _gps.stopListening();
    _resetWalkingNarrationState();
    _stateMachine.reset();
  }

  void dispose() {
    _gpsSubscription?.cancel();
    _gps.stopListening();
    _resetWalkingNarrationState();
    _stateMachine.dispose();
  }
}
