class IntentParser {
  /// Very simple keyword-based intent detection.
  /// Returns a destination keyword if the phrase sounds like a navigation request, else null.
  static String? extractNavigationDestination(String spokenText) {
    final text = spokenText.toLowerCase();

    const navigationTriggers = ['take me to', 'navigate to', 'go to', 'find', 'directions to'];

    for (final trigger in navigationTriggers) {
      if (text.contains(trigger)) {
        final index = text.indexOf(trigger) + trigger.length;
        final destination = text.substring(index).trim();
        if (destination.isNotEmpty) return destination;
      }
    }

    // Fallback: if it just says a place-like word directly (e.g. "hospital")
    const commonPlaces = ['hospital', 'pharmacy', 'restaurant', 'bus stop', 'home', 'office'];
    for (final place in commonPlaces) {
      if (text.contains(place)) return place;
    }

    return null;
  }
}
