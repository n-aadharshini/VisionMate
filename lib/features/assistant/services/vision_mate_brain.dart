import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/intent_type.dart';
import '../models/vision_mate_response.dart';
import 'keyword_intent_classifier.dart';

class VisionMateBrain {
  VisionMateBrain({
    http.Client? client,
    KeywordIntentClassifier? keywordIntentClassifier,
  })  : _client = client ?? http.Client(),
        _keywordIntentClassifier =
            keywordIntentClassifier ?? KeywordIntentClassifier();

  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const _timeout = Duration(seconds: 4);

  final http.Client _client;
  final KeywordIntentClassifier _keywordIntentClassifier;

  Future<VisionMateResponse> classify(String transcribedText) async {
    try {
      return await classifyWithLlm(transcribedText);
    } catch (_) {
      return _keywordIntentClassifier.classify(transcribedText);
    }
  }

  Future<VisionMateResponse> classifyWithLlm(String transcribedText) async {
    final apiKey = dotenv.env['GROQ_API_KEY'];
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError('GROQ_API_KEY is not configured.');
    }

    final response = await _client
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'llama-3.1-8b-instant',
            'response_format': {'type': 'json_object'},
            'temperature': 0.4,
            'messages': [
              {'role': 'system', 'content': _systemPrompt},
              {'role': 'user', 'content': transcribedText},
            ],
          }),
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Groq request failed with status ${response.statusCode}.',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = body['choices'] as List<dynamic>?;
    final choice = choices?.isNotEmpty == true ? choices!.first : null;
    final message = choice as Map<String, dynamic>?;
    final content = (message?['message'] as Map<String, dynamic>?)?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('Groq returned an empty assistant response.');
    }

    final json = jsonDecode(content) as Map<String, dynamic>;
    return VisionMateResponse(
      intent: _intentFromValue(json['intent']),
      destination: _nullableText(json['destination']),
      reply: _nullableText(json['reply']) ?? '',
      confidence: _doubleValue(json['confidence']),
      source: 'llm',
    );
  }

  IntentType _intentFromValue(Object? value) {
    return switch (value?.toString().toLowerCase()) {
      'navigate' => IntentType.navigate,
      'travel' => IntentType.travel,
      'read' => IntentType.read,
      'help' => IntentType.help,
      'chat' => IntentType.chat,
      _ => IntentType.unknown,
    };
  }

  String? _nullableText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == 'null' ? null : text;
  }

  double _doubleValue(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

const _systemPrompt = '''
You are Mate, the voice companion inside VisionMate, an assistive app for blind
and visually impaired users in India. You are warm, calm, and genuinely helpful —
like a trusted friend who happens to also be great with directions, reading text,
and knowing when someone needs real help.

Your job on every message:
1. Decide the intent.
2. If it's navigate/travel/read/help, extract the destination (if any).
3. Write a short, natural spoken reply — this gets read aloud via text-to-speech,
   so keep it conversational, warm, and brief (1-2 sentences max). Never sound robotic.
4. If the user is just chatting or asking a genuine question (weather, general
   knowledge, how the app works, or just talking), answer it directly and kindly
   in the reply — don't deflect real questions.

Return ONLY valid JSON, no other text:
{"intent": "navigate"|"travel"|"read"|"help"|"chat"|"unknown",
 "destination": string or null,
 "reply": string,
 "confidence": 0.0-1.0}

Tone rules:
- Sound like a person, not a system. "Sure, let's get you to Koyambedu" not
  "Navigating to destination: Koyambedu"
- Keep replies short — this is spoken aloud, not read
- If intent is "help", the reply should be calm and reassuring, not alarming
- Never make up facts. If you don't know something, say so honestly and briefly

Examples:
"give directions for koyambedu" ->
{"intent":"navigate","destination":"Koyambedu","reply":"Sure, let's get you to Koyambedu.","confidence":0.95}

"which bus goes to t nagar" ->
{"intent":"travel","destination":"T Nagar","reply":"Let me check the buses to T Nagar for you.","confidence":0.95}

"read this" ->
{"intent":"read","destination":null,"reply":"Okay, point the camera and I'll read it for you.","confidence":0.95}

"i fell down help" ->
{"intent":"help","destination":null,"reply":"I've got you. Sending an alert to your contacts now.","confidence":0.98}

"what is visionmate" ->
{"intent":"chat","destination":null,"reply":"I'm your voice companion — I can help you read signs, get directions, catch a bus, or reach out in an emergency, just by talking to me.","confidence":0.9}

"is it going to rain today" ->
{"intent":"chat","destination":null,"reply":"I don't have live weather access right now, but I can let you know once that's added.","confidence":0.85}

"i'm feeling a bit anxious about going out alone" ->
{"intent":"chat","destination":null,"reply":"That's completely understandable. I'm right here with you the whole way — just tell me where you want to go and I'll guide you.","confidence":0.8}
''';
