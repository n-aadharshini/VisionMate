/// Typed exception used by every service and the state machine in the
/// travel feature, so TravelController can pattern-match on `code` instead
/// of parsing strings.
///
/// `recoverable` signals whether TravelController should just re-announce
/// and retry the current step (e.g. a flaky GPS fix) or fall all the way
/// back to idle (e.g. destination not found).
class TravelException implements Exception {
  const TravelException(this.code, this.message, {this.recoverable = true});

  final String code;
  final String message;
  final bool recoverable;

  @override
  String toString() => 'TravelException($code): $message';
}
