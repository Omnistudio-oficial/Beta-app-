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

class AiAgentPendingAction {
  const AiAgentPendingAction({
    required this.provider,
    required this.action,
    required this.details,
    required this.approvalId,
    required this.idempotencyKey,
    required this.expiresAt,
  });

  final String provider;
  final String action;
  final Map<String, dynamic> details;
  final String approvalId;
  final String idempotencyKey;
  final String expiresAt;

  factory AiAgentPendingAction.fromJson(Map<String, dynamic> json) {
    final details = json['details'];
    return AiAgentPendingAction(
      provider: json['provider'] is String ? json['provider'] as String : '',
      action: json['action'] is String ? json['action'] as String : '',
      details: details is Map<String, dynamic> ? details : const {},
      approvalId: json['approval_id'] is String ? json['approval_id'] as String : '',
      idempotencyKey: json['idempotency_key'] is String ? json['idempotency_key'] as String : '',
      expiresAt: json['expires_at'] is String ? json['expires_at'] as String : '',
    );
  }

  Map<String, dynamic> toExecuteJson() => {
        'provider': provider,
        'details': details,
        'approval_id': approvalId,
        'idempotency_key': idempotencyKey,
      };
}

class AiAgentChatResponse {
  const AiAgentChatResponse({
    required this.answer,
    required this.conversationId,
    required this.webSearchStatus,
    required this.webSources,
    this.pendingAction,
  });

  final String answer;
  final String? conversationId;
  final String webSearchStatus;
  final List<AiAgentWebSource> webSources;
  final AiAgentPendingAction? pendingAction;

  bool get requiresApproval => pendingAction != null;
  bool get usedWebSearch => webSearchStatus == 'searched';
}

/// Sends authenticated chat messages to the configured AI Agent Ultimate Worker (production by default).
/// Firebase ID tokens remain in memory and are never logged or persisted.
/// Conversation IDs are non-secret and are stored separately for each Firebase UID.
class AiAgentUltimateService {
  AiAgentUltimateService({http.Client? client})
      : _client = client ?? http.Client();

  static const String endpoint = String.fromEnvironment(
    'AI_AGENT_ULTIMATE_URL',
    defaultValue: 'https://ai-agent-ultimate.gonzalez24029.workers.dev/v1/chat',
  );

  Uri get _chatUri => Uri.parse(endpoint);
  Uri get _executeUri => _chatUri.replace(path: '/v1/chat/actions/execute');

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
          _chatUri,
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
      final pending = data['pending_action'];
      if (data['status'] == 'approval_required' && pending is Map<String, dynamic>) {
        final action = AiAgentPendingAction.fromJson(pending);
        if (action.provider.isNotEmpty && action.approvalId.isNotEmpty &&
            action.idempotencyKey.isNotEmpty && action.details.isNotEmpty) {
          return AiAgentChatResponse(
            answer: data['answer'] is String
                ? data['answer'] as String
                : 'Revisa la acción y confirma si deseas ejecutarla.',
            conversationId: null,
            webSearchStatus: 'not_requested',
            webSources: const [],
            pendingAction: action,
          );
        }
      }
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
      } else if (backendError == 'web_search_invalid_request') {
        message = 'Brave Search rechazó la consulta. Se limitó automáticamente a 75 palabras y 600 caracteres; inténtalo de nuevo con una pregunta más corta.';
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

  Future<Map<String, dynamic>> executePendingAction(
    AiAgentPendingAction action,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Inicia sesión en OmniStudio para autorizar esta acción.');
    }
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('No se pudo obtener la autenticación de Firebase.');
    }
    final response = await _client
        .post(
          _executeUri,
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(action.toExecuteJson()),
        )
        .timeout(const Duration(seconds: 45));
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } on FormatException {
      // Never expose provider response bodies or credentials in UI errors.
    }
    if (response.statusCode != 200) {
      final error = data['error'] is String ? data['error'] as String : '';
      if (error == 'valid_one_time_approval_required') {
        throw StateError('La autorización venció o ya fue utilizada. Solicita la acción de nuevo.');
      }
      throw StateError('El proveedor no pudo completar la acción. Código HTTP: ${response.statusCode}.');
    }
    final result = data['result'];
    if (result is! Map<String, dynamic>) {
      throw StateError('El servidor no confirmó el resultado de la acción.');
    }
    return result;
  }

  Future<void> startNewConversation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_conversationKey(user.uid));
  }

  void close() => _client.close();
}
