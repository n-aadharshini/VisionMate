/// The finite set of states a VisionMate bus journey can be in.
///
/// This mirrors the state machine in the spec exactly:
/// idle -> listening -> planning -> navigateToBusStop -> waitingForBus
/// -> onBus -> navigateToDestination -> completed
///
/// `error` is reachable from any in-progress state and always resolves
/// back to `idle` (see TravelStateMachine).
enum TravelState {
  idle,
  listening,
  planning,
  navigateToBusStop,
  waitingForBus,
  onBus,
  navigateToDestination,
  completed,
  error,
}

extension TravelStateLabel on TravelState {
  /// Human-readable label, useful for debug logging/UI — never spoken
  /// directly (TTS strings are composed separately so wording can be
  /// tuned without touching state logic).
  String get label {
    switch (this) {
      case TravelState.idle:
        return 'Idle';
      case TravelState.listening:
        return 'Listening';
      case TravelState.planning:
        return 'Planning';
      case TravelState.navigateToBusStop:
        return 'Navigating to bus stop';
      case TravelState.waitingForBus:
        return 'Waiting for bus';
      case TravelState.onBus:
        return 'On bus';
      case TravelState.navigateToDestination:
        return 'Navigating to destination';
      case TravelState.completed:
        return 'Completed';
      case TravelState.error:
        return 'Error';
    }
  }
}
