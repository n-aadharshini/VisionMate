import 'package:flutter_test/flutter_test.dart';
import 'package:vision_mate/core/services/memory_store.dart';
import 'package:vision_mate/core/services/ocr_memory_service.dart';

/// [answerFollowUp] searches for stored entries whose VALUE contains the
/// QUERY string AND the query must contain specific keywords to extract info.
void main() {
  late MemoryStore store;
  late OcrMemoryService service;

  setUp(() {
    store = MemoryStore(ttl: const Duration(hours: 1), sweepInterval: const Duration(hours: 24));
    service = OcrMemoryService(store: store);
  });

  tearDown(() {
    service.dispose();
  });

  group('OCR save with dedup', () {
    test('saves and retrieves OCR text', () {
      service.saveOcr('Bus 25 to Anna Square');
      expect(service.retrieveLatest(), 'Bus 25 to Anna Square');
    });

    test('dedup: identical normalized text skipped', () {
      service.saveOcr('Bus 25 to Anna Square');
      service.saveOcr('Bus 25 to Anna Square');
      expect(store.totalEntries, 1);
    });

    test('dedup: normalized match deduped', () {
      service.saveOcr('Bus 25 to Anna Square!');
      service.saveOcr('bus 25 to anna square');
      expect(store.totalEntries, 1);
    });

    test('different text saved separately', () {
      service.saveOcr('Bus 25 to Anna Square');
      service.saveOcr('Bus 21B to CMBT');
      expect(store.totalEntries, 2);
    });
  });

  group('Scene memory', () {
    test('saves and retrieves scene', () {
      service.saveScene('A crowded market street');
      expect(service.retrieveLatestScene(), 'A crowded market street');
    });

    test('dedup on scene', () {
      service.saveScene('Description');
      service.saveScene('Description');
      expect(store.totalEntries, 1);
    });
  });

  group('answerFollowUp — bus number extraction', () {
    test('extracts bus number from stored text', () {
      service.saveOcr('the bus number is 25');
      expect(service.answerFollowUp('bus number'), 'The bus or route number is 25');
    });

    test('extracts route number', () {
      service.saveOcr('route number 21B');
      expect(service.answerFollowUp('route number'), 'The bus or route number is 21B');
    });

    test('extracts platform number', () {
      service.saveOcr('platform number 3');
      expect(service.answerFollowUp('platform number'), 'The platform is 3');
    });

    test('extracts gate number', () {
      service.saveOcr('gate number 7');
      expect(service.answerFollowUp('gate number'), 'The gate is 7');
    });
  });

  group('answerFollowUp — destination/direction', () {
    test('extracts destination from "to X" when query contains direction keyword', () {
      service.saveOcr('Going to Anna Square via Mount Road');
      final answer = service.answerFollowUp('going to');
      expect(answer, contains('It is going to Anna Square'));
    });

    test('extracts destination with "towards"', () {
      service.saveOcr('This bus goes towards Tambaram');
      expect(service.answerFollowUp('towards Tambaram'), 'It is going to Tambaram.');
    });
  });

  group('answerFollowUp — time extraction', () {
    test('extracts time when query contains time keyword', () {
      service.saveOcr('depart 10:30 AM');
      expect(service.answerFollowUp('depart 10:30'), 'The time is 10:30 AM.');
    });

    test('returns null when query not found in stored text', () {
      service.saveOcr('Bus 25');
      expect(service.answerFollowUp('schedule unknown'), isNull);
    });
  });

  group('answerFollowUp — scene queries', () {
    test('returns scene for "what did you see"', () {
      service.saveScene('what did you see — a red car');
      expect(service.answerFollowUp('what did you see'), 'what did you see — a red car');
    });

    test('prefers scene over OCR for "describe"', () {
      service.saveOcr('Some sign text');
      service.saveScene('describe — a park with trees');
      expect(service.answerFollowUp('describe'), 'describe — a park with trees');
    });
  });

  group('answerFollowUp — "say again" / "repeat"', () {
    test('returns OCR for "say again"', () {
      service.saveOcr('say again — Warning Wet Floor');
      expect(service.answerFollowUp('say again'), 'say again — Warning Wet Floor');
    });

    test('returns OCR for "repeat that"', () {
      service.saveOcr('repeat that — Exit door');
      expect(service.answerFollowUp('repeat that'), 'repeat that — Exit door');
    });
  });

  group('answerFollowUp — "that" reference', () {
    test('returns latest OCR when stored contains "that" in query', () {
      service.saveOcr('Bus 25 that stop');
      expect(service.answerFollowUp('that'), 'Bus 25 that stop');
    });

    test('returns scene when query matches scene text', () {
      service.saveScene('scene that tall building');
      expect(service.answerFollowUp('that'), 'scene that tall building');
    });
  });

  group('answerFollowUp — no match', () {
    test('returns null when query not found in stored text', () {
      service.saveOcr('Bus 25 to Anna Square');
      expect(service.answerFollowUp('weather forecast'), isNull);
    });

    test('returns null when store is empty', () {
      expect(service.answerFollowUp('bus number'), isNull);
    });
  });

  group('searchOcr and searchScene', () {
    test('searchOcr finds matching entries', () {
      service.saveOcr('Bus 25 goes to Anna Square');
      expect(service.searchOcr('Anna Square').length, 1);
    });

    test('searchScene finds matching entries', () {
      service.saveScene('A busy junction at Anna Nagar');
      expect(service.searchScene('Anna Nagar').length, 1);
    });
  });

  test('clearOcr clears all OCR entries', () {
    service.saveOcr('Some text');
    service.clearOcr();
    expect(service.retrieveLatest(), isNull);
  });
}
