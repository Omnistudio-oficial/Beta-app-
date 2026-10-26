import 'package:flutter_tts/flutter_tts.dart';
import 'navigation_guidance.dart';

class TtsSpeechOutput implements SpeechOutput {
  TtsSpeechOutput(this.tts);
  final FlutterTts tts;
  @override
  Future<void> speak(String text) async {
    try {
      await tts.speak(text);
    } catch (_) {
      // TTS setup can fail on devices without an available speech engine.
    }
  }
  @override
  Future<void> stop() async {
    try { await tts.stop(); } catch (_) {}
  }
}
