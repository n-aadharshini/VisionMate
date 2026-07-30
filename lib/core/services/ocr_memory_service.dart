import 'memory_store.dart';

class OcrMemoryService {
  OcrMemoryService({MemoryStore? store})
    : _store = store ?? MemoryStore(ttl: const Duration(minutes: 30));

  final MemoryStore _store;

  static const _ocrKey = 'ocr';
  static const _sceneKey = 'scene';

  void saveOcr(String text) {
    final normalized = _normalize(text);
    final latest = retrieveLatest();
    if (latest != null && _normalize(latest) == normalized) return;
    _store.save(_ocrKey, text, metadata: {'source': 'ocr'});
  }

  String? retrieveLatest() => _store.retrieve(_ocrKey);

  List<String> searchOcr(String query) =>
      _store.search(query, scope: _ocrKey).map((e) => e.value).toList();

  void clearOcr() => _store.remove(_ocrKey);

  void saveScene(String description) {
    final normalized = _normalize(description);
    final latest = retrieveLatestScene();
    if (latest != null && _normalize(latest) == normalized) return;
    _store.save(_sceneKey, description, metadata: {'source': 'scene'});
  }

  String? retrieveLatestScene() => _store.retrieve(_sceneKey);

  List<String> searchScene(String query) =>
      _store.search(query, scope: _sceneKey).map((e) => e.value).toList();

  String? answerFollowUp(String query) {
    final lowerQuery = query.toLowerCase();

    final ocrResults = searchOcr(query);
    final sceneResults = searchScene(query);
    final allResults = [...ocrResults, ...sceneResults];

    if (allResults.isEmpty) return null;

    if (_containsAny(lowerQuery, [
      'bus number', 'bus no', 'what bus', 'which bus', 'route',
      'platform', 'gate', 'counter',
    ])) {
      final match = _extractNumberNear(allResults.join(' '), lowerQuery);
      if (match != null) return 'The $match';
    }

    if (_containsAny(lowerQuery, [
      'where', 'going', 'destination', 'direction', 'towards',
    ])) {
      final joined = allResults.join(' ');
      final destMatch = RegExp(
        r'(?:to|towards|for|via)\s+([A-Z][A-Za-z\s]+?)(?:[.!?,]|$)',
      ).firstMatch(joined);
      if (destMatch != null) {
        return 'It is going to ${destMatch.group(1)!.trim()}.';
      }
    }

    if (_containsAny(lowerQuery, [
      'when', 'time', 'leave', 'depart', 'arrive', 'schedule', 'eta',
      'how long',
    ])) {
      final joined = allResults.join(' ');
      final timeMatch = RegExp(
        r'(\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?)',
      ).firstMatch(joined);
      if (timeMatch != null) {
        return 'The time is ${timeMatch.group(1)!.trim()}.';
      }
    }

    if (sceneResults.isNotEmpty && _containsAny(lowerQuery, [
      'what did you see', 'what was there', 'describe', 'what is around',
      'what is ahead', 'what do you see', 'scene', 'look',
    ])) {
      return sceneResults.last;
    }

    if (ocrResults.isNotEmpty && _containsAny(lowerQuery, [
      'what did', 'what was', 'what does', 'say again', 'repeat',
      'tell me what',
    ])) {
      final latest = ocrResults.last;
      if (latest.length <= 200) return latest;
    }

    final latestOcr = retrieveLatest();
    if (latestOcr != null && lowerQuery.contains('that')) {
      final words = latestOcr.split(' ');
      if (words.length <= 10) return latestOcr;
      return '${words.take(10).join(' ')}...';
    }

    final latestScene = retrieveLatestScene();
    if (latestScene != null && lowerQuery.contains('that')) {
      return latestScene;
    }

    return null;
  }

  String? _extractNumberNear(String text, String query) {
    final numberMatch = RegExp(r'\b\d{1,4}[A-Za-z]?\b').firstMatch(text);
    if (numberMatch == null) return null;
    final number = numberMatch.group(0)!;
    if (query.contains('platform')) return 'platform is $number';
    if (query.contains('gate')) return 'gate is $number';
    if (query.contains('bus') || query.contains('route')) {
      return 'bus or route number is $number';
    }
    return 'number is $number';
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _containsAny(String text, List<String> keywords) =>
      keywords.any(text.contains);

  void dispose() => _store.dispose();
}
