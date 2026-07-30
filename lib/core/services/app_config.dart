import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract final class AppConfig {
  static String get groqApiKey {
    final key = dotenv.env['GROQ_API_KEY']?.trim();
    if (key == null || key.isEmpty) {
      throw StateError('GROQ_API_KEY is not configured in .env');
    }
    return key;
  }

  static String get groqVisionModel =>
      dotenv.env['VISION_MODEL'] ?? 'qwen/qwen3.6-27b';

  static String get groqChatModel =>
      dotenv.env['CHAT_MODEL'] ?? 'llama-3.1-8b-instant';

  static String get groqTtsModel =>
      dotenv.env['TTS_MODEL'] ?? 'canopylabs/orpheus-v1-english';

  static String get groqTtsVoice =>
      dotenv.env['GROQ_TTS_VOINE']?.trim().isNotEmpty == true
          ? dotenv.env['GROQ_TTS_VOINE']!.trim()
          : 'austin';

  static double get groqTtsSpeed {
    final raw = dotenv.env['GROQ_TTS_SPEED']?.trim();
    if (raw == null || raw.isEmpty) return 0.85;
    final parsed = double.tryParse(raw);
    if (parsed == null) return 0.85;
    return parsed.clamp(0.5, 5.0);
  }

  static Duration get groqTimeout =>
      Duration(seconds: _parseInt('GROQ_TIMEOUT_SECONDS', 12));

  static Duration get groqVisionTimeout =>
      Duration(seconds: _parseInt('VISION_TIMEOUT_SECONDS', 20));

  static int get maxVisionRateLimitCallsPer10s =>
      _parseInt('VISION_RATE_LIMIT', 1);

  static Duration get memoryTtl =>
      Duration(minutes: _parseInt('MEMORY_TTL_MINUTES', 30));

  static Duration get memorySweepInterval =>
      Duration(seconds: _parseInt('MEMORY_SWEEP_SECONDS', 60));

  static int get maxImageBytes =>
      _parseInt('MAX_IMAGE_BYTES', 20 * 1024 * 1024); // 20MB

  static bool get reduceMotion =>
      dotenv.env['REDUCE_MOTION']?.trim().toLowerCase() == 'true';

  static int _parseInt(String key, int defaultValue) {
    final raw = dotenv.env[key]?.trim();
    if (raw == null || raw.isEmpty) return defaultValue;
    final parsed = int.tryParse(raw);
    return parsed ?? defaultValue;
  }
}
