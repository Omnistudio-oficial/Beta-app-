import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AiAgentWebSource {
  const AiAgentWebSource({
    required this.title,
    required this.url,
    required this.description,
  });

  final String title;
  final String url;
  final String description;

  factory AiAgentWebSource.fromJson(Map<String, dynamic> json) {
    return AiAgentWebSource(
      title: json['title'] is String ? json['title'] as String : 'Fuente web',
      url: json['url'] is String ? json['url'] as String : '',
      description:
          json['description'] is String ? json['description'] as String : '',
    );
  }
}

class AiAgentChatResponse {
  const AiAgentChatResponse({
    required this.answer,
    required this.conversationId,
    required this.webSearchStatus,
    required this.webSources,
  });

  final String answer;
  final String? conversationId;
  final String webSearchStatus;
  final List<AiAgentWebSource> webSources;

  bool get usedWebSearch => webSearchStatus == 'searched';
}

/// Sends authenticated chat messages to the production AI Agent Ultimate Worker.
/// Firebase ID tokens remain in memory and are never logged or persisted.
/// Conversation IDs are non-secret and are stored separately for each Firebase UID.
class AiAgentUltimateService {
  AiAgentUltimateService({http.Client? client})
      : _client = client ?? http.Client();

  static const String endpoint =
      'https://ai-agent-ultimate.gonzalez24029.workers.dev/v1/chat';

  final http.Client _client;

  String _conversationKey(String uid) => 'ai_agent_conversation_id_$uid';

  Future<AiAgentChatResponse> sendMessage(
    String prompt, {
    bool webSearch = false,
  }) async {
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

    final preferences = await SharedPreferences.getInstance();
    final conversationId = preferences.getString(_conversationKey(user.uid));
    final requestBody = <String, dynamic>{
      'prompt': normalizedPrompt,
      'web_search': webSearch,
      if (conversationId != null && conversationId.isNotEmpty)
        'conversation_id': conversationId,
    };

    final response = await _client
        .post(
          Uri.parse(endpoint),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(requestBody),
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
      throw StateError(
        'Esta solicitud requiere autorización. No se ejecutó ninguna acción.',
      );
    }
    if (response.statusCode == 401) {
      throw StateError('Firebase rechazó la sesión. Vuelve a iniciar sesión.');
    }
    if (response.statusCode == 503 &&
        data['error'] == 'web_search_not_configured') {
      throw StateError('La búsqueda web no está configurada en el servidor.');
    }
    if (response.statusCode != 200) {
      final backendError = data['error'] is String ? data['error'] as String : '';
      final stage = data['stage'] is String ? data['stage'] as String : '';
      final requestId =
          data['request_id'] is String ? data['request_id'] as String : '';
      String message;
      if (backendError == 'web_search_invalid_credentials') {
        message = 'Brave Search rechazó las credenciales configuradas.';
      } else if (backendError == 'web_search_rate_limited') {
        message = 'Brave Search alcanzó su límite de solicitudes. Inténtalo más tarde.';
      } else if (backendError == 'web_search_provider_error' ||
          backendError == 'web_search_request_failed' ||
          backendError == 'web_search_invalid_response') {
        message = 'Brave Search no pudo completar la búsqueda.';
      } else if (backendError.startsWith('workers_ai_')) {
        message = 'El servicio de inteligencia artificial no pudo generar la respuesta.';
      } else if (backendError.startsWith('supabase_')) {
        message = 'El servicio de conversación y almacenamiento tuvo un problema.';
      } else {
        message = 'AI Agent Ultimate encontró un error interno';
        if (stage.isNotEmpty) message += ' durante: $stage';
        message += '.';
      }
      if (requestId.isNotEmpty) message += ' Referencia: $requestId';
      throw StateError(message);
    }

    final answer = data['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw StateError('AI Agent Ultimate no devolvió una respuesta válida.');
    }

    final newConversationId = data['conversation_id'];
    if (newConversationId is String && newConversationId.isNotEmpty) {
      await preferences.setString(
        _conversationKey(user.uid),
        newConversationId,
      );
    }

    final rawSources = data['web_sources'];
    final sources = rawSources is List
        ? rawSources
            .whereType<Map<String, dynamic>>()
            .map(AiAgentWebSource.fromJson)
            .where((source) => source.url.startsWith('https://') ||
                source.url.startsWith('http://'))
            .toList(growable: false)
        : const <AiAgentWebSource>[];

    return AiAgentChatResponse(
      answer: answer.trim(),
      conversationId:
          newConversationId is String ? newConversationId : conversationId,
      webSearchStatus: data['web_search'] is String
          ? data['web_search'] as String
          : 'not_requested',
      webSources: sources,
    );
  }

  Future<void> startNewConversation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_conversationKey(user.uid));
  }

  void close() => _client.close();
}
