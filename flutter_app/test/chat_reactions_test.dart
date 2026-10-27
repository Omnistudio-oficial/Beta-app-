import 'package:beta_app/screens/chat_message_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toggles and removes one reaction while preserving others', () {
    expect(toggleChatReaction('', '👍'), '👍');
    expect(toggleChatReaction('👍,❤️', '😂'), '👍,❤️,😂');
    expect(toggleChatReaction('👍,❤️,👍', '👍'), '❤️,👍');
    expect(() => toggleChatReaction('', 'bad,emoji'), throwsArgumentError);
  });

  test('counts duplicate reactions for display', () {
    expect(countChatReactions('👍,❤️,👍'), {'👍': 2, '❤️': 1});
    expect(countChatReactions(''), isEmpty);
  });

  test('parses legacy reaction field from RTDB message', () {
    final message = ChatMessage.fromMap('m1', 'room', {
      'senderName': 'A', 'senderEmail': 'a@example.test', 'text': 'hola',
      'timestamp': 1, 'reactions': '👍,❤️',
    });
    expect(message.reactions, '👍,❤️');
  });
}
