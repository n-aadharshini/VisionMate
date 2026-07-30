import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/vision_mate_response.dart';
import 'keyword_intent_classifier.dart';

class GroqIntentService {
  GroqIntentService({required http.Client client, KeywordIntentClassifier? fallback}) : _client = client, _fallback = fallback ?? KeywordIntentClassifier();
  final http.Client _client; final KeywordIntentClassifier _fallback;
  Future<VisionMateResponse> classify(String text, List<Map<String, String>> history) async {
    try {
      debugPrint('[GROQ CALL] text="$text" history_turns=${history.length}');
      final key = dotenv.env['GROQ_API_KEY']; if (key == null || key.isEmpty) throw StateError('missing_api_key');
      final response = await _client.post(Uri.parse('https://api.groq.com/openai/v1/chat/completions'), headers: {'Authorization':'Bearer $key','Content-Type':'application/json'}, body: jsonEncode({'model':'llama-3.1-8b-instant','response_format':{'type':'json_object'},'temperature':0.4,'messages':[{'role':'system','content':_prompt}, ...history, {'role':'user','content':text}]})).timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('http_${response.statusCode}');
      final body = jsonDecode(response.body) as Map<String,dynamic>; final content = (((body['choices'] as List?)?.first as Map?)?['message'] as Map?)?['content'];
      if (content is! String) throw const FormatException('empty_content');
      final result = VisionMateResponse.fromGroqJson(jsonDecode(content) as Map<String,dynamic>);
      debugPrint('[GROQ RESPONSE] intent=${result.intent.name} reply="${result.reply}" fallback=false');
      return result;
    } catch (error) { debugPrint('[GROQ FALLBACK] reason=$error'); return _fallback.classify(text); }
  }
}
const _prompt = '''You are VisionMate, a friendly intelligent voice companion. Return ONLY JSON: {"intent":"chat|navigate|read|travel|help","destination":string|null,"reply":string,"confidence":number}.

First understand the user's intent. Answer normal chat and general knowledge directly, naturally, and briefly using your general knowledge: greetings, jokes, boredom, science, history, technology, learning, and advice are chat. Do not say you cannot answer normal questions when you know the answer.

Map app capabilities as follows: directions, reaching somewhere, or feeling lost means navigate; bus/train/timings/public transport means travel; reading a label/image/text means read; emergency, fear, danger, or needing assistance means help. Detect indirect intent, not just exact commands.

Weather, current location, reminders, and any other live tool request are chat in this app. Do not invent live data. Explain warmly that the required live service is not available yet or ask for the needed detail. A question such as “What is Chennai?” is chat, not location. “How does rain happen?” is chat, not weather.

If the request is ambiguous, remain chat and ask one simple clarifying question instead of guessing. Use recent conversation context naturally. Keep replies short and easy to speak aloud.''';
