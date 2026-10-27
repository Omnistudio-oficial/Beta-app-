import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// User-initiated, read-only access to Gmail, Calendar, and Drive.
/// OAuth access tokens live only in this instance's memory and are never persisted.
class GoogleWorkspaceReadOnlyService {
  GoogleWorkspaceReadOnlyService({http.Client? client}) : _client = client ?? http.Client();

  static const scopes = <String>[
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/calendar.events.readonly',
    'https://www.googleapis.com/auth/drive.readonly',
  ];

  final http.Client _client;
  String? _accessToken;
  String? _email;

  bool get isConnected => _accessToken != null;
  String? get connectedEmail => _email;

  Future<void> connect() async {
    final signIn = GoogleSignIn.instance;
    await signIn.initialize();
    final account = await signIn.authenticate();
    final authorization = await account.authorizationClient.authorizeScopes(scopes);
    final token = authorization.accessToken;
    if (token.isEmpty) throw StateError('Google no devolvió un permiso válido.');
    _accessToken = token;
    _email = account.email;
  }

  Future<void> disconnect() async {
    _accessToken = null;
    _email = null;
    await GoogleSignIn.instance.disconnect();
  }

  /// Sends the user's natural-language question and the in-memory Google OAuth
  /// token to Sara's existing Groq Workspace backend. The backend handles
  /// interpretation and read-only connector calls; no Google token is persisted.
  Future<String> askSara(String question, {String? firebaseIdToken}) async {
    final googleToken = _accessToken;
    if (googleToken == null) throw StateError('Conecta Google Workspace primero.');
    final user = FirebaseAuth.instance.currentUser;
    final idToken = firebaseIdToken ?? await user?.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Inicia sesión en OmniStudio para consultar a Sara.');
    }
    final response = await _client.post(
      Uri.https('rasaserveria.onrender.com', '/api/rasa/groq/workspace'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'text': question.trim(),
        'connectors': {
          'gmail': googleToken,
          'calendar': googleToken,
          'drive': googleToken,
        },
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Sara no pudo consultar Workspace (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respuesta inesperada de Sara.');
    }
    final answer = decoded['text'];
    if (answer is! String || answer.trim().isEmpty) {
      throw StateError('Sara no recibió una respuesta utilizable.');
    }
    return answer.trim();
  }

  Future<List<Map<String, dynamic>>> searchEmails(String query) async {
    final result = await _get(
      Uri.https('gmail.googleapis.com', '/gmail/v1/users/me/messages', {
        'q': query.trim().isEmpty ? 'in:inbox' : query.trim(),
        'maxResults': '5',
      }),
    );
    final messages = (result['messages'] as List<dynamic>? ?? const []);
    return Future.wait(messages.map((item) async {
      final id = (item as Map<String, dynamic>)['id'] as String?;
      if (id == null) return <String, dynamic>{};
      final message = await _get(Uri.https('gmail.googleapis.com', '/gmail/v1/users/me/messages/$id', {
        'format': 'metadata',
        'metadataHeaders': 'From,Subject,Date',
      }));
      final payload = message['payload'] as Map<String, dynamic>? ?? const {};
      final headers = (payload['headers'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
      final normalized = <String, String>{
        for (final header in headers)
          (header['name'] as String? ?? '').toLowerCase(): (header['value'] as String? ?? ''),
      };
      return <String, dynamic>{
        'id': message['id'],
        'snippet': message['snippet'] ?? '',
        'from': normalized['from'] ?? '',
        'subject': normalized['subject'] ?? '(sin asunto)',
        'date': normalized['date'] ?? '',
      };
    }));
  }

  Future<List<Map<String, dynamic>>> upcomingEvents() async {
    final now = DateTime.now().toUtc();
    final end = now.add(const Duration(days: 7));
    final result = await _get(Uri.https('www.googleapis.com', '/calendar/v3/calendars/primary/events', {
      'timeMin': now.toIso8601String(),
      'timeMax': end.toIso8601String(),
      'singleEvents': 'true',
      'orderBy': 'startTime',
      'maxResults': '10',
    }));
    return (result['items'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> searchDrive(String query) async {
    final escaped = query.trim().replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    final q = query.trim().isEmpty ? 'trashed = false' : "name contains '$escaped' and trashed = false";
    final result = await _get(Uri.https('www.googleapis.com', '/drive/v3/files', {
      'q': q,
      'pageSize': '10',
      'orderBy': 'modifiedTime desc',
      'fields': 'files(id,name,mimeType,modifiedTime,webViewLink)',
    }));
    return (result['files'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final token = _accessToken;
    if (token == null) throw StateError('Conecta Google Workspace primero.');
    final response = await _client.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Google Workspace respondió con error (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) throw const FormatException('Respuesta inesperada de Google.');
    return decoded;
  }
}
