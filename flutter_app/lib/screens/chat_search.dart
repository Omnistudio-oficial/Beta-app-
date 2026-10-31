import 'package:flutter/material.dart';
import 'chat_repository.dart';

/// Filters only the messages already provided by the open conversation stream.
/// A blank query deliberately preserves the original message ordering/content.
List<ChatMessage> filterChatMessages(List<ChatMessage> messages, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return messages;
  return messages.where((message) =>
      message.text.toLowerCase().contains(needle) ||
      message.senderName.toLowerCase().contains(needle) ||
      message.senderEmail.toLowerCase().contains(needle)).toList(growable: false);
}

/// Renders local query matches with a subtle highlight without changing the
/// message model or issuing additional repository/database operations.
class HighlightedChatText extends StatelessWidget {
  const HighlightedChatText(this.text, {super.key, required this.query, this.style});

  final String text;
  final String query;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final needle = query.trim();
    if (needle.isEmpty) return Text(text, style: style);
    final lower = text.toLowerCase();
    final target = needle.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;
    while (cursor < text.length) {
      final match = lower.indexOf(target, cursor);
      if (match < 0) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }
      if (match > cursor) spans.add(TextSpan(text: text.substring(cursor, match)));
      spans.add(TextSpan(
        text: text.substring(match, match + needle.length),
        style: const TextStyle(backgroundColor: Color(0xFFFFE082), fontWeight: FontWeight.bold),
      ));
      cursor = match + needle.length;
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
