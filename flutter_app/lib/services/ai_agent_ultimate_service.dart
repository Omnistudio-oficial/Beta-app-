import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Sends authenticated chat messages to the production AI Agent Ultimate Worker.
/// The Firebase ID token is kept in memory and is never logged or persisted.
class AiAgentUltimateService {
  AiAgentUltimateService({http.Client? client})
      : _client = client ?? http.Client();

  static const String endpoint =
      'https://ai-agent-ultimate.gonzalez24029.workers.dev/v1/chat';

  final http.Client _client;

  Future<String> sendMessage(String prompt) async {
    final normalizedPrompt = prompt.trim();
    if (normalizedPrompt.isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'El mensaje está vacío.');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Inicia sesión en OmniStudio para conversar.');
    }

    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('No se pudo obtener la autenticación de Firebase.');
    }

    final response = await _client
        .post(
          Uri.parse(endpoint),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'prompt': normalizedPrompt}),
        )
        .timeout(const Duration(seconds: 45));

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } on FormatException {
      // Keep errors generic; never expose response bodies or tokens.
    }

    if (response.statusCode == 202) {
      return 'Esta solicitud requiere autorización. No se ejecutó ninguna acción.';
    }
    if (response.statusCode == 401) {
      throw StateError('Firebase rechazó la sesión. Vuelve a iniciar sesión.');
    }
    if (response.statusCode != 200) {
      throw StateError(
        'AI Agent Ultimate no pudo responder (' +
            response.statusCode.toString() +
            ').',
      );
    }

    final answer = data['answer'];
    if (answer is String && answer.trim().isNotEmpty) {
      return answer.trim();
    }
    throw StateError('AI Agent Ultimate no devolvió una respuesta válida.');
  }

  void close() => _client.close();
}
