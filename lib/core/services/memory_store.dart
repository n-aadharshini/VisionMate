import 'dart:async';

class MemoryEntry {
  MemoryEntry({
    required this.value,
    required this.timestamp,
    this.metadata,
  });

  final String value;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  bool get isExpired => ttl != null &&
      DateTime.now().difference(timestamp) >= ttl!;

  static Duration? ttl;
}

class MemoryStore {
  MemoryStore({Duration? ttl, Duration? sweepInterval}) {
    MemoryEntry.ttl = ttl;
    _startSweeper(sweepInterval);
  }

  final Map<String, List<MemoryEntry>> _store = {};
  Timer? _sweeper;

  void save(String key, String value, {Map<String, dynamic>? metadata}) {
    final entries = _store.putIfAbsent(key, () => []);
    entries.add(MemoryEntry(value: value, timestamp: DateTime.now(), metadata: metadata));
  }

  String? retrieve(String key, {bool latestOnly = true}) {
    final entries = _store[key];
    if (entries == null || entries.isEmpty) return null;
    final valid = entries.where((e) => !e.isExpired).toList();
    if (valid.isEmpty) return null;
    _store[key] = valid;
    return latestOnly ? valid.last.value : valid.map((e) => e.value).join('\n');
  }

  List<MemoryEntry> search(String query, {String? scope}) {
    final lowerQuery = query.toLowerCase();
    final results = <MemoryEntry>[];
    final sources = scope != null
        ? {scope: _store[scope]}
        : _store;

    for (final entry in sources.values) {
      if (entry == null) continue;
      for (final e in entry) {
        if (e.isExpired) continue;
        if (e.value.toLowerCase().contains(lowerQuery)) {
          results.add(e);
        }
      }
    }
    return results;
  }

  void remove(String key) {
    _store.remove(key);
  }

  void removeExpired() {
    for (final key in _store.keys.toList()) {
      _store[key]?.removeWhere((e) => e.isExpired);
      if (_store[key]?.isEmpty == true) {
        _store.remove(key);
      }
    }
  }

  void clear() {
    _store.clear();
  }

  bool get isEmpty => _store.isEmpty;

  int get totalEntries {
    var count = 0;
    for (final entries in _store.values) {
      count += entries.where((e) => !e.isExpired).length;
    }
    return count;
  }

  void _startSweeper(Duration? interval) {
    final effectiveInterval = interval ?? const Duration(seconds: 60);
    _sweeper = Timer.periodic(effectiveInterval, (_) => removeExpired());
  }

  void dispose() {
    _sweeper?.cancel();
    _store.clear();
  }
}
