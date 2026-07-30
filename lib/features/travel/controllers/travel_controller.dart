import 'dart:async';
import 'dart:math' as math;

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
    this.offRouteThresholdMeters = 25,
    this.offRouteSamplesRequired = 3,
  }) : _gps = gpsService ?? StubGpsService(),
       _geofence = geofenceService ?? HaversineGeofenceService(),
       _journeyPlanner = journeyPlannerService ?? StubJourneyPlannerService(),
       _navigation = navigationService ?? OsrmNavigationService(),
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

  /// A user must be this far from the route line for several consecutive
  /// GPS samples before rerouting. This filters normal GPS drift.
  final double offRouteThresholdMeters;
  final int offRouteSamplesRequired;

  JourneyPlan? _activePlan;
  StreamSubscription<GpsPosition>? _gpsSubscription;

  /// Walking steps for the current leg (either "to the boarding stop" or
  /// "to the final destination"), fetched from [NavigationService] once
  /// per leg. Empty until a leg's directions have been fetched, or if
  /// fetching them failed — narration is advisory-only, so a failure here
  /// never blocks the underlying geofence arrival trigger.
  List<NavigationStep> _walkingSteps = const [];
  List<RoutePoint> _walkingRoutePoints = const [];
  int _walkingStepIndex = 0;
  int _offRouteSamples = 0;

  /// Identifies which leg [_walkingSteps] currently belongs to, so
  /// [_onPositionUpdate] only fetches directions once per leg instead of
  /// re-fetching on every GPS update. Null means no leg fetched yet.
  TravelState? _walkingLegState;
  int _journeyEpoch = 0;

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
    final journeyEpoch = ++_journeyEpoch;
    _stopGpsMonitoring();
    // Defensive reset in case this controller instance is reused across
    // more than one journey — a stale leg from a previous trip should
    // never bleed into a new one.
    _resetWalkingNarrationState();

    try {
      _stateMachine.transitionTo(TravelState.listening);
      _stateMachine.transitionTo(TravelState.planning);

      final position = await _gps.getCurrentPosition();
      if (journeyEpoch != _journeyEpoch) return;
      final plan = await _journeyPlanner.planJourney(
        currentLat: position.latitude,
        currentLng: position.longitude,
        destinationQuery: destinationQuery,
      );
      if (journeyEpoch != _journeyEpoch) return;
      _activePlan = plan;

      await speak(plan.summarySpeech);
      if (journeyEpoch != _journeyEpoch) return;

      _stateMachine.transitionTo(
        plan.walkOnly
            ? TravelState.navigateToDestination
            : TravelState.navigateToBusStop,
      );

      _beginGpsMonitoring();
    } on TravelException catch (e) {
      if (journeyEpoch != _journeyEpoch) return;
      await _handleFailure(e.message);
    } catch (e) {
      if (journeyEpoch != _journeyEpoch) return;
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
  Future<void> onArrivedAtBusStop() async {
    if (_stateMachine.canTransitionTo(TravelState.waitingForBus)) {
      _stateMachine.transitionTo(TravelState.waitingForBus);
      _journeyEpoch++;
      _stopGpsMonitoring();
      _resetWalkingNarrationState();
      await speak('You have reached the bus stop.');
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
      _journeyEpoch++;
      _stopGpsMonitoring();
      _resetWalkingNarrationState();
      await speak('You have arrived at your destination.');
    }
  }

  /// Cancels an in-progress journey and returns to idle. Safe to call
  /// from any state — e.g. the user says "cancel" or a hard error occurs
  /// upstream in ConversationSessionController.
  void cancelJourney() {
    _journeyEpoch++;
    _stopGpsMonitoring();
    _activePlan = null;
    _resetWalkingNarrationState();
    _stateMachine.reset();
  }

  void _resetWalkingNarrationState() {
    _walkingSteps = const [];
    _walkingRoutePoints = const [];
    _walkingStepIndex = 0;
    _offRouteSamples = 0;
    _walkingLegState = null;
    _narrating = false;
  }

  void _beginGpsMonitoring() {
    _stopGpsMonitoring();
    _gps.startListening();
    _gpsSubscription = _gps.positionStream.listen(_onPositionUpdate);
  }

  void _stopGpsMonitoring() {
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
    _gps.stopListening();
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
          unawaited(onArrivedAtBusStop());
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
          unawaited(onArrivedAtDestination());
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
    final navigationEpoch = _journeyEpoch;
    try {
      if (_walkingLegState != legState) {
        // New leg — fetch fresh directions from here to the leg's target,
        // and reset step tracking before anything else touches it.
        _walkingLegState = legState;
        _walkingStepIndex = 0;
        try {
          final route = await _navigation.getWalkingRoute(
            fromLat: position.latitude,
            fromLng: position.longitude,
            toLat: toLat,
            toLng: toLng,
          );
          if (navigationEpoch != _journeyEpoch || state != legState) return;
          _walkingSteps = route.steps;
          _walkingRoutePoints = route.points;
        } on TravelException catch (error) {
          _walkingSteps = const [];
          if (navigationEpoch != _journeyEpoch || state != legState) return;
          await speak(error.message);
          return;
        } catch (_) {
          _walkingSteps = const [];
          if (navigationEpoch != _journeyEpoch || state != legState) return;
          await speak(
            'I could not get walking instructions right now. I will still let you know when you reach the destination.',
          );
          return;
        }
        if (_walkingSteps.isEmpty) return;
        // Speak the first instruction immediately rather than waiting for
        // the rider to physically reach its waypoint — this is the
        // "start walking, here's your first instruction" moment.
        if (navigationEpoch != _journeyEpoch || state != legState) return;
        await speak(_walkingSteps.first.instruction);
        _walkingStepIndex = 1;
        return;
      }

      if (await _rerouteIfOffRoute(
        legState: legState,
        position: position,
        toLat: toLat,
        toLng: toLng,
        navigationEpoch: navigationEpoch,
      )) {
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
        if (navigationEpoch != _journeyEpoch || state != legState) return;
        await speak(step.instruction);
      }
    } finally {
      _narrating = false;
    }
  }

  Future<bool> _rerouteIfOffRoute({
    required TravelState legState,
    required GpsPosition position,
    required double toLat,
    required double toLng,
    required int navigationEpoch,
  }) async {
    if (_walkingRoutePoints.length < 2) return false;
    final distance = _distanceToRouteMeters(position, _walkingRoutePoints);
    if (distance <= offRouteThresholdMeters) {
      _offRouteSamples = 0;
      return false;
    }

    _offRouteSamples++;
    if (_offRouteSamples < offRouteSamplesRequired) return false;
    _offRouteSamples = 0;
    await speak('You have gone off route. Calculating a new route.');
    if (navigationEpoch != _journeyEpoch || state != legState) return true;

    try {
      final route = await _navigation.getWalkingRoute(
        fromLat: position.latitude,
        fromLng: position.longitude,
        toLat: toLat,
        toLng: toLng,
      );
      if (navigationEpoch != _journeyEpoch || state != legState) return true;
      _walkingSteps = route.steps;
      _walkingRoutePoints = route.points;
      _walkingStepIndex = 0;
      if (_walkingSteps.isEmpty) {
        await speak('I could not find a new walking route from here.');
        return true;
      }
      await speak(_walkingSteps.first.instruction);
      _walkingStepIndex = 1;
    } on TravelException catch (error) {
      if (navigationEpoch == _journeyEpoch && state == legState) {
        await speak(error.message);
      }
    } catch (_) {
      if (navigationEpoch == _journeyEpoch && state == legState) {
        await speak('I could not recalculate the walking route right now.');
      }
    }
    return true;
  }

  /// Short-distance projection of a GPS point onto each route segment.
  /// At pedestrian-navigation scale this is accurate enough to distinguish
  /// genuine 25m deviations from normal location drift.
  double _distanceToRouteMeters(
    GpsPosition position,
    List<RoutePoint> routePoints,
  ) {
    var nearest = double.infinity;
    for (var index = 0; index < routePoints.length - 1; index++) {
      final distance = _distanceToSegmentMeters(
        position,
        routePoints[index],
        routePoints[index + 1],
      );
      if (distance < nearest) nearest = distance;
    }
    return nearest;
  }

  double _distanceToSegmentMeters(
    GpsPosition position,
    RoutePoint start,
    RoutePoint end,
  ) {
    const metersPerDegree = 111320.0;
    final referenceLatitude = (start.latitude + end.latitude + position.latitude) / 3;
    final longitudeScale = metersPerDegree * math.cos(referenceLatitude * math.pi / 180);
    final startX = start.longitude * longitudeScale;
    final startY = start.latitude * metersPerDegree;
    final endX = end.longitude * longitudeScale;
    final endY = end.latitude * metersPerDegree;
    final pointX = position.longitude * longitudeScale;
    final pointY = position.latitude * metersPerDegree;
    final dx = endX - startX;
    final dy = endY - startY;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) {
      return math.sqrt(math.pow(pointX - startX, 2) + math.pow(pointY - startY, 2));
    }
    final projection = (((pointX - startX) * dx) + ((pointY - startY) * dy)) / lengthSquared;
    final t = projection.clamp(0.0, 1.0);
    final nearestX = startX + t * dx;
    final nearestY = startY + t * dy;
    return math.sqrt(math.pow(pointX - nearestX, 2) + math.pow(pointY - nearestY, 2));
  }

  Future<void> _handleFailure(String message) async {
    _journeyEpoch++;
    await speak(message);
    if (_stateMachine.canTransitionTo(TravelState.error)) {
      _stateMachine.transitionTo(TravelState.error);
    }
    _stopGpsMonitoring();
    _resetWalkingNarrationState();
    _stateMachine.reset();
  }

  void dispose() {
    _journeyEpoch++;
    _stopGpsMonitoring();
    _navigation.dispose();
    _resetWalkingNarrationState();
    _stateMachine.dispose();
  }
}
