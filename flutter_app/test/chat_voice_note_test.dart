import 'package:beta_app/screens/chat_voice_note.dart';
import 'package:record/record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefers Opus in OGG on Android when available', () {
    final choice = voiceNoteEncoderChoice(isAndroid: true, opusSupported: true);
    expect(choice.encoder, AudioEncoder.opus);
    expect(choice.extension, 'ogg');
    expect(choice.mimeType, 'audio/ogg');
  });

  test('falls back to AAC/M4A when Opus is unavailable or platform is iOS', () {
    final android = voiceNoteEncoderChoice(isAndroid: true, opusSupported: false);
    expect(android.encoder, AudioEncoder.aacLc);
    expect(android.mimeType, 'audio/mp4');
    final ios = voiceNoteEncoderChoice(isAndroid: false, opusSupported: true);
    expect(ios.extension, 'm4a');
  });
}
