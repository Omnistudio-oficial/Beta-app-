import 'package:beta_app/screens/youtube_chat_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts YouTube IDs from watch, short, embed, and shorts URLs', () {
    expect(extractChatYouTubeId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(extractChatYouTubeId('https://youtu.be/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(extractChatYouTubeId('https://www.youtube.com/embed/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(extractChatYouTubeId('https://www.youtube.com/shorts/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(extractChatYouTubeId('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(extractChatYouTubeId('https://example.com/watch?v=bad'), isNull);
    expect(buildChatYouTubeEmbedUrl('dQw4w9WgXcQ'), contains('/embed/dQw4w9WgXcQ'));
    expect(buildChatYouTubeVideoUrl('dQw4w9WgXcQ'), 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
  });
}
