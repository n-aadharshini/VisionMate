import 'package:flutter_test/flutter_test.dart';
import 'package:vision_mate/core/services/memory_store.dart';

void main() {
  late MemoryStore store;

  setUp(() {
    store = MemoryStore(ttl: const Duration(hours: 1), sweepInterval: const Duration(hours: 24));
  });

  tearDown(() {
    store.dispose();
  });

  group('save and retrieve', () {
    test('save and retrieve a value', () {
      store.save('ocr', 'Bus 25 to Anna Square');
      expect(store.retrieve('ocr'), 'Bus 25 to Anna Square');
    });

    test('returns null for missing key', () {
      expect(store.retrieve('nonexistent'), isNull);
    });

    test('latestOnly returns most recent entry', () {
      store.save('ocr', 'First text');
      store.save('ocr', 'Second text');
      expect(store.retrieve('ocr'), 'Second text');
    });

    test('latestOnly=false returns all entries joined', () {
      store.save('ocr', 'First');
      store.save('ocr', 'Second');
      expect(store.retrieve('ocr', latestOnly: false), 'First\nSecond');
    });
  });

  group('TTL expiry', () {
    test('return null for expired entries', () {
      final expiredStore = MemoryStore(ttl: Duration.zero, sweepInterval: const Duration(hours: 24));
      expiredStore.save('ocr', 'Will expire instantly');
      expect(expiredStore.retrieve('ocr'), isNull);
      expiredStore.dispose();
    });

    test('removeExpired cleans up expired entries', () {
      final expiredStore = MemoryStore(ttl: Duration.zero, sweepInterval: const Duration(hours: 24));
      expiredStore.save('ocr', 'Gone');
      expiredStore.removeExpired();
      expect(expiredStore.retrieve('ocr'), isNull);
      expect(expiredStore.isEmpty, true);
      expiredStore.dispose();
    });
  });

  group('search', () {
    test('find entries by keyword', () {
      store.save('ocr', 'Bus 25 to Anna Square');
      store.save('ocr', 'Metro to Central');
      store.save('scene', 'A busy road');
      final results = store.search('Anna');
      expect(results.length, 1);
      expect(results.first.value, 'Bus 25 to Anna Square');
    });

    test('find entries across all scopes', () {
      store.save('ocr', 'Bus 25 to Anna Square');
      store.save('scene', 'Anna Nagar tower');
      final results = store.search('Anna');
      expect(results.length, 2);
    });

    test('scoped search', () {
      store.save('ocr', 'Bus 25');
      store.save('scene', 'Scene description');
      final results = store.search('Bus', scope: 'scene');
      expect(results, isEmpty);
    });

    test('skip expired entries in search', () {
      final expiredStore = MemoryStore(ttl: Duration.zero, sweepInterval: const Duration(hours: 24));
      expiredStore.save('ocr', 'Expired text');
      final results = expiredStore.search('Expired');
      expect(results, isEmpty);
      expiredStore.dispose();
    });

    test('case insensitive search', () {
      store.save('ocr', 'Bus 25 to Anna Square');
      expect(store.search('anna').length, 1);
      expect(store.search('ANNA').length, 1);
      expect(store.search('SQUARE').length, 1);
    });
  });

  group('remove and clear', () {
    test('remove by key', () {
      store.save('ocr', 'Some text');
      store.remove('ocr');
      expect(store.retrieve('ocr'), isNull);
    });

    test('clear removes everything', () {
      store.save('ocr', 'Text 1');
      store.save('scene', 'Text 2');
      store.clear();
      expect(store.isEmpty, true);
    });
  });

  group('totalEntries', () {
    test('counts only non-expired entries', () {
      store.save('ocr', 'Entry 1');
      store.save('ocr', 'Entry 2');
      store.save('scene', 'Entry 3');
      expect(store.totalEntries, 3);
    });
  });
}
