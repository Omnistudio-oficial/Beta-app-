import 'package:beta_app/models/chat_models.dart';

class AIService {
  Future<List<ChatMessage>> sendPrompt(String prompt) async {
    await Future.delayed(const Duration(milliseconds: 700));

    final userMessage = ChatMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      text: prompt,
      isUser: true,
      createdAt: DateTime.now(),
    );

    final aiMessage = ChatMessage(
      id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
      text: 'Respuesta generada por IA para: "$prompt"',
      isUser: false,
      createdAt: DateTime.now(),
    );

    return [userMessage, aiMessage];
  }
}
