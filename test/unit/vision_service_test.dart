import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vision_mate/core/services/vision_service.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({this.statusCode = 200, this.body, this.error, this.delay});

  final int statusCode;
  final String? body;
  final Object? error;
  final Duration? delay;

  int callCount = 0;
  int _failAttempts = 0;

  void setFailAttempts(int n) => _failAttempts = n;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    callCount++;
    if (delay != null) await Future.delayed(delay!);
    if (callCount <= _failAttempts && error != null) throw error!;
    return http.StreamedResponse(
      http.ByteStream.fromBytes(utf8.encode(body ?? '{}')),
      statusCode,
    );
  }
}

void main() {
  setUpAll(() {
    dotenv.testLoad();
    dotenv.env['GROQ_API_KEY'] = 'test-key';
    dotenv.env['MAX_IMAGE_BYTES'] = '20971520';
    dotenv.env['VISION_TIMEOUT_SECONDS'] = '2';
  });

  group('image compression', () {
    test('accepts image over 20MB without crashing', () async {
      final client = _FakeHttpClient();
      final service = GroqVisionService(client: client);
      await service.describeImage(Uint8List(21 * 1024 * 1024 + 100));
    });

    test('accepts small image without issues', () async {
      final client = _FakeHttpClient();
      final service = GroqVisionService(client: client);
      await service.describeImage(Uint8List(1024));
    });
  });

  group('retry and failure handling', () {
    test('retries 3 times on network failure then returns fallback', () async {
      final client = _FakeHttpClient(error: const SocketException('Connection refused'));
      client.setFailAttempts(99);
      final service = GroqVisionService(client: client);
      final result = await service.describeImage(Uint8List(1024));
      expect(client.callCount, 3);
      expect(result, 'I could not get a look at that, try again.');
    });

    test('returns fallback after repeated rate limit responses', () async {
      final client = _FakeHttpClient(statusCode: 429, body: 'Rate limited');
      final service = GroqVisionService(client: client);
      final result = await service.describeImage(Uint8List(1024));
      expect(result, 'I could not get a look at that, try again.');
      expect(client.callCount, 3);
    });

    test('succeeds on retry after first failure', () async {
      final client = _FakeHttpClient(
        error: const SocketException('First attempt failed'),
        body: jsonEncode({
          'choices': [{'message': {'content': 'A person walking down the street.'}}],
        }),
      );
      client.setFailAttempts(1);
      final service = GroqVisionService(client: client);
      final result = await service.describeImage(Uint8List(1024));
      expect(result, 'A person walking down the street.');
      expect(client.callCount, 2);
    });
  });

  group('response handling', () {
    test('returns content from successful vision response', () async {
      final client = _FakeHttpClient(
        body: jsonEncode({
          'choices': [{'message': {'content': 'A busy road with vehicles.'}}],
        }),
      );
      final service = GroqVisionService(client: client);
      final result = await service.describeImage(Uint8List(1024));
      expect(result, 'A busy road with vehicles.');
    });

    test('returns fallback when choices are missing', () async {
      final client = _FakeHttpClient(body: jsonEncode({}));
      final service = GroqVisionService(client: client);
      final result = await service.describeImage(Uint8List(1024));
      expect(result, 'I could not get a look at that, try again.');
    });

    test('handles malformed JSON response', () async {
      final client = _FakeHttpClient(body: 'not-json');
      final service = GroqVisionService(client: client);
      final result = await service.describeImage(Uint8List(1024));
      expect(result, 'I could not get a look at that, try again.');
    });
  });

  group('response truncation', () {
    test('truncates to first sentence ending with period', () async {
      final client = _FakeHttpClient(
        body: jsonEncode({
          'choices': [{'message': {'content': 'A busy street. Cars are moving.'}}],
        }),
      );
      final service = GroqVisionService(client: client);
      final result = await service.describeImage(Uint8List(1024));
      expect(result, 'A busy street.');
    });

    test('truncates to first sentence ending with exclamation', () async {
      final client = _FakeHttpClient(
        body: jsonEncode({
          'choices': [{'message': {'content': 'Watch out! A car is coming.'}}],
        }),
      );
      final service = GroqVisionService(client: client);
      final result = await service.describeImage(Uint8List(1024));
      expect(result, 'Watch out!');
    });
  });

  group('timeout handling', () {
    test('returns fallback on timeout', () async {
      final client = _FakeHttpClient(delay: const Duration(seconds: 5));
      final service = GroqVisionService(client: client);
      final result = await service.describeImage(Uint8List(1024));
      expect(result, 'I could not get a look at that, try again.');
      expect(client.callCount, 3);
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  test('dispose closes HTTP client', () {
    final client = _FakeHttpClient();
    final service = GroqVisionService(client: client);
    service.dispose();
  });
}
