import 'package:http/http.dart' as http;
import '../models/vision_mate_response.dart';
import 'groq_intent_service.dart';
import 'keyword_intent_classifier.dart';
class VisionMateBrain {
  VisionMateBrain({http.Client? client, KeywordIntentClassifier? keywordIntentClassifier, GroqIntentService? groqIntentService}) : _groq = groqIntentService ?? GroqIntentService(client: client ?? http.Client(), fallback: keywordIntentClassifier);
  final GroqIntentService _groq;
  Future<VisionMateResponse> classify(String text, {List<Map<String,String>> history = const []}) => _groq.classify(text, history);
}
