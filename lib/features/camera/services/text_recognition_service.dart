import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class TextRecognitionService {
  TextRecognitionService() : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final TextRecognizer _recognizer;

  Future<String> recognizeFile(String path) async {
    final result = await _recognizer.processImage(InputImage.fromFilePath(path));
    return result.text.trim();
  }

  void dispose() => _recognizer.close();
}
