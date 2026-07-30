import 'package:flutter_test/flutter_test.dart';
import 'package:vision_mate/features/assistant/models/intent_type.dart';
import 'package:vision_mate/features/assistant/services/keyword_intent_classifier.dart';

void main() {
  late KeywordIntentClassifier classifier;

  setUp(() {
    classifier = KeywordIntentClassifier();
  });

  group('Read Mode intent isolation', () {
    for (final phrase in [
      'read the sign',
      'what does this say',
      'what does it say',
      'what is this text',
      'scan this label',
      'read this for me',
      'read this bus number',
      'repeat that text',
      'say again',
    ]) {
      test('"$phrase" -> read intent', () {
        final result = classifier.classify(phrase);
        expect(result.intent, IntentType.read,
            reason: "'$phrase' should be classified as read, got ${result.intent}");
      });
    }
  });

  group('Travel Mode intent isolation', () {
    for (final phrase in [
      'which bus goes to marina',
      'bus number 25',
      'bus route to anna nagar',
      'train timing',
      'metro schedule',
      'eta for bus 47',
      'arrival at cmbt',
      'travel to vadapalani',
      'bus 21B arrival',
      'take me to the bus stop',  // "bus" triggers travel before "take me to" triggers navigate
      'where is the nearest bus stop',  // "bus" matches travel
    ]) {
      test('"$phrase" -> travel intent', () {
        final result = classifier.classify(phrase);
        expect(result.intent, IntentType.travel,
            reason: "'$phrase' should be travel, got ${result.intent}");
      });
    }
  });

  group('Navigate Mode intent isolation', () {
    for (final phrase in [
      'navigate to marina beach',
      'take me to the station',
      'directions to cmbt',
      'direction to anna nagar',
      'reach koyambedu',
      'way to the temple',
      'route to airport',
    ]) {
      test('"$phrase" -> navigate intent', () {
        final result = classifier.classify(phrase);
        expect(result.intent, IntentType.navigate,
            reason: "'$phrase' should be navigate, got ${result.intent}");
      });
    }

    test('"where is the station" -> navigate (where is in navigate list)', () {
      final result = classifier.classify('where is the station');
      expect(result.intent, IntentType.navigate);
    });

    test('"directions home" -> navigate', () {
      final result = classifier.classify('directions home');
      expect(result.intent, IntentType.navigate);
    });
  });

  group('Cross-domain phrases — correct precedence', () {
    test('"read this bus number" -> read (read checked before bus)', () {
      final result = classifier.classify('read this bus number');
      expect(result.intent, IntentType.read);
    });

    test('"bus route number" -> travel (bus checked before route)', () {
      final result = classifier.classify('bus route number');
      expect(result.intent, IntentType.travel);
    });

    test('"help I am lost" -> help', () {
      final result = classifier.classify('help I am lost');
      expect(result.intent, IntentType.help);
    });

    test('"SOS emergency" -> help', () {
      final result = classifier.classify('SOS emergency');
      expect(result.intent, IntentType.help);
    });
  });

  group('Fallback behavior', () {
    test('gibberish -> chat fallback with low confidence', () {
      final result = classifier.classify('asdfzxcv qwerty');
      expect(result.intent, IntentType.chat);
      expect(result.confidence, lessThan(0.5));
      expect(result.isFallback, true);
    });

    test('empty string -> chat fallback', () {
      final result = classifier.classify('');
      expect(result.intent, IntentType.chat);
      expect(result.isFallback, true);
    });

    test('unrecognized phrase -> chat fallback', () {
      final result = classifier.classify('tell me a story');
      expect(result.intent, IntentType.chat);
      expect(result.isFallback, true);
    });
  });

  group('Destination extraction', () {
    test('extracts destination from "to X"', () {
      final result = classifier.classify('take me to marina beach');
      expect(result.destination, 'marina beach');
    });

    test('extracts destination from "reach X"', () {
      final result = classifier.classify('how do I reach koyambedu');
      expect(result.destination, 'koyambedu');
    });

    test('extracts destination from "for X" in travel context', () {
      final result = classifier.classify('bus to anna nagar');
      expect(result.destination, 'anna nagar');
    });

    test('null destination when no "to/for/reach"', () {
      final result = classifier.classify('bus timing');
      expect(result.destination, isNull);
    });
  });
}
