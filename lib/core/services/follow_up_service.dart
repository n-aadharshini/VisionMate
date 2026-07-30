import 'ocr_memory_service.dart';

abstract final class FollowUpService {
  static OcrMemoryService? _ocrMemory;

  static void init(OcrMemoryService service) {
    _ocrMemory = service;
  }

  static String? tryAnswer(String query) {
    final memory = _ocrMemory;
    if (memory == null) return null;
    return memory.answerFollowUp(query);
  }

  static OcrMemoryService? get memory => _ocrMemory;
}
