import 'dart:async';

import '../models/travel_exception.dart';
import '../models/travel_state.dart';

/// The ONLY component permitted to change [TravelState].
///
/// TravelController drives this machine but never mutates state directly —
/// every transition is checked against [_allowedTransitions] first. Keeping
/// "what state can follow what" in exactly one place means a bug elsewhere
/// (e.g. a GPS callback firing twice) can't silently push the journey into
/// an invalid state; it throws instead.
///
/// Listen to [onChange] to react to every transition (e.g. update a debug
/// overlay, or drive Phase 5's screen routing).
class TravelStateMachine {
  TravelStateMachine() {
    _controller.add(_current);
  }

  TravelState _current = TravelState.idle;
  final _controller = StreamController<TravelState>.broadcast();

  /// Maps each state to the set of states it is allowed to move to next.
  /// This table IS the state diagram from the spec:
  ///
  /// idle -> listening -> planning -> navigateToBusStop -> waitingForBus
  ///      -> onBus -> navigateToDestination -> completed -> idle
  ///
  /// `error` is reachable from any in-flight state and only ever leads
  /// back to `idle`. Every in-flight state can also fall back to `idle`
  /// directly (user cancels mid-journey).
  static const Map<TravelState, Set<TravelState>> _allowedTransitions = {
    TravelState.idle: {TravelState.listening},
    TravelState.listening: {TravelState.planning, TravelState.idle},
    TravelState.planning: {
      TravelState.navigateToBusStop,
      TravelState.navigateToDestination, // walk-only plans skip the bus
      TravelState.idle,
      TravelState.error,
    },
    TravelState.navigateToBusStop: {
      TravelState.waitingForBus,
      TravelState.idle,
      TravelState.error,
    },
    TravelState.waitingForBus: {
      TravelState.onBus,
      TravelState.idle,
      TravelState.error,
    },
    TravelState.onBus: {
      TravelState.navigateToDestination,
      TravelState.idle,
      TravelState.error,
    },
    TravelState.navigateToDestination: {
      TravelState.completed,
      TravelState.idle,
      TravelState.error,
    },
    TravelState.completed: {TravelState.idle},
    TravelState.error: {TravelState.idle},
  };

  TravelState get current => _current;
  Stream<TravelState> get onChange => _controller.stream;

  bool canTransitionTo(TravelState next) =>
      _allowedTransitions[_current]?.contains(next) ?? false;

  /// Throws [TravelException] (code: `invalid_transition`, not
  /// recoverable) if the move isn't in the table above.
  void transitionTo(TravelState next) {
    if (!canTransitionTo(next)) {
      throw TravelException(
        'invalid_transition',
        'Cannot move from ${_current.label} to ${next.label}',
        recoverable: false,
      );
    }
    _current = next;
    _controller.add(_current);
  }

  /// Hard reset to idle. Used after `completed`, after an unrecoverable
  /// `error`, or when the user cancels a journey outright.
  void reset() {
    _current = TravelState.idle;
    _controller.add(_current);
  }

  void dispose() => _controller.close();
}
