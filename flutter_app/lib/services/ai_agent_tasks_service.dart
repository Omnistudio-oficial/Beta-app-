import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AiAgentTask {
  const AiAgentTask({
    required this.id,
    required this.status,
    this.result,
    this.errorCode,
    this.createdAt,
  });

  final String id;
  final String status;
  final Map<String, dynamic>? result;
  final String? errorCode;
  final String? createdAt;

  factory AiAgentTask.fromJson(Map<String, dynamic> json) => AiAgentTask(
        id: (json['id'] ?? json['task_id'] ?? '').toString(),
        status: (json['status'] ?? 'unknown').toString(),
        result: json['result'] is Map<String, dynamic>
            ? json['result'] as Map<String, dynamic>
            : null,
        errorCode: json['error_code'] as String?,
        createdAt: json['created_at'] as String?,
      );
}

class AiAgentTaskStep {
  const AiAgentTaskStep({
    required this.number,
    required this.name,
    required this.status,
    this.output,
  });

  final int number;
  final String name;
  final String status;
  final Map<String, dynamic>? output;

  factory AiAgentTaskStep.fromJson(Map<String, dynamic> json) =>
      AiAgentTaskStep(
        number: (json['step_number'] as num?)?.toInt() ?? 0,
        name: (json['agent_name'] ?? 'step').toString(),
        status: (json['status'] ?? 'pending').toString(),
        output: json['output'] is Map<String, dynamic>
            ? json['output'] as Map<String, dynamic>
            : null,
      );
}

class AiAgentTaskCreated {
  const AiAgentTaskCreated({
    required this.taskId,
    required this.status,
    this.approvalId,
  });

  final String taskId;
  final String status;
  final String? approvalId;
}

class AiAgentTasksService {
  AiAgentTasksService({http.Client? client})
      : _client = client ?? http.Client();

  static const String _baseUrl =
      'https://ai-agent-ultimate.gonzalez24029.workers.dev';
  static const String _historyKey = 'ai_agent_task_ids_';

  final http.Client _client;

  Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Inicia sesión en OmniStudio para usar las tareas.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('No se pudo validar tu sesión de Firebase.');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final headers = await _headers();
    final uri = Uri.parse('$_baseUrl$path');
    final response = switch (method) {
      'POST' => await _client.post(uri, headers: headers, body: jsonEncode(body ?? {})),
      _ => await _client.get(uri, headers: headers),
    }.timeout(const Duration(seconds: 45));

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } on FormatException {
      // Do not expose raw server responses or authentication material.
    }

    if (response.statusCode == 401) {
      throw StateError('Tu sesión expiró. Vuelve a iniciar sesión.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = (data['error'] ?? 'request_failed').toString();
      throw StateError(_friendlyError(code, response.statusCode));
    }
    return data;
  }

  String _friendlyError(String code, int status) {
    switch (code) {
      case 'task_not_found':
        return 'No se encontró esta tarea.';
      case 'no_pending_approval':
        return 'Esta tarea ya no tiene una aprobación pendiente.';
      case 'approval_already_decided':
        return 'La aprobación ya fue procesada.';
      default:
        return 'No se pudo completar la solicitud (HTTP $status).';
    }
  }

  Future<AiAgentTaskCreated> createTask(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty) throw ArgumentError('Escribe qué debe hacer Sara.');
    final data = await _request('POST', '/v1/tasks', body: {'prompt': text});
    final id = data['task_id'];
    if (id is! String || id.isEmpty) {
      throw StateError('El servidor no devolvió el identificador de la tarea.');
    }
    final user = FirebaseAuth.instance.currentUser!;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_historyKey${user.uid}';
    final ids = prefs.getStringList(key) ?? <String>[];
    await prefs.setStringList(key, [id, ...ids.where((item) => item != id)].take(30).toList());
    return AiAgentTaskCreated(
      taskId: id,
      status: (data['status'] ?? 'queued').toString(),
      approvalId: data['approval_id'] as String?,
    );
  }

  Future<AiAgentTask> getTask(String id) async {
    final data = await _request('GET', '/v1/tasks/$id');
    return AiAgentTask.fromJson(data);
  }

  Future<List<AiAgentTaskStep>> getSteps(String id) async {
    final data = await _request('GET', '/v1/tasks/$id/steps');
    final rows = data['steps'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(AiAgentTaskStep.fromJson)
        .toList(growable: false);
  }

  Future<void> decide(String id, {required bool approve}) async {
    await _request('POST', '/v1/tasks/$id/decision', body: {
      'decision': approve ? 'approve' : 'reject',
    });
  }

  Future<List<String>> getSavedTaskIds() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const [];
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('$_historyKey${user.uid}') ?? const [];
  }

  void close() => _client.close();
}
