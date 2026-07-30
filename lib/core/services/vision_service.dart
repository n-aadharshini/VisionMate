import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';

abstract class VisionService {
  Future<String> describeImage(Uint8List imageBytes, {String? prompt});
}

class GroqVisionService implements VisionService {
  GroqVisionService({http.Client? client, this.modelId})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String? modelId;

  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const _maxRetries = 2;
  static const _retryDelay = Duration(milliseconds: 800);
  static const _defaultPrompt =
      'Describe this image in one short, voice-friendly sentence. '
      'Focus on what is ahead or around the person. '
      'Do not describe the image quality or framing.';
  static const _maxResponseTokens = 120;

  @override
  Future<String> describeImage(
    Uint8List imageBytes, {
    String? prompt,
  }) async {
    final compressed = _compressIfNeeded(imageBytes);
    final effectivePrompt = prompt ?? _defaultPrompt;

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final result = await _callVision(compressed, effectivePrompt);
        if (result.isNotEmpty) return _truncateToFirstSentence(result);
      } catch (e) {
        debugPrint('[GROQ VISION] attempt $attempt failed: $e');
        if (attempt < _maxRetries) {
          await Future.delayed(_retryDelay);
        }
      }
    }
    return 'I could not get a look at that, try again.';
  }

  Future<String> _callVision(Uint8List imageBytes, String prompt) async {
    final base64Image = base64Encode(imageBytes);
    final dataUri = 'data:image/jpeg;base64,$base64Image';

    final model = modelId ?? AppConfig.groqVisionModel;

    final response = await _client
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Authorization': 'Bearer ${AppConfig.groqApiKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': prompt},
                  {'type': 'image_url', 'image_url': {'url': dataUri}},
                ],
              },
            ],
            'max_tokens': _maxResponseTokens,
          }),
        )
        .timeout(AppConfig.groqVisionTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Groq vision status ${response.statusCode}: ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        (((body['choices'] as List?)?.first as Map?)?['message']
            as Map?)?['content'] as String?;

    return content?.trim() ?? '';
  }

  Uint8List _compressIfNeeded(Uint8List bytes) {
    if (bytes.length <= AppConfig.maxImageBytes) return bytes;
    debugPrint(
      '[VISION] compressing image ${bytes.length} -> ${AppConfig.maxImageBytes}',
    );
    return bytes.sublist(0, AppConfig.maxImageBytes);
  }

  String _truncateToFirstSentence(String text) {
    final match = RegExp(r'^[^.!?]*[.!?]').firstMatch(text);
    if (match == null) return text;
    return text.substring(0, match.end).trim();
  }

  void dispose() {
    _client.close();
  }
}
