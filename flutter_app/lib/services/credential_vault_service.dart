import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Shared Android/iOS client for the Cloudflare credential vault.
/// Configure with --dart-define=AI_AGENT_BASE_URL=https://<deployed-worker-host>.
class CredentialVaultService {
  CredentialVaultService({
    FirebaseAuth? auth,
    http.Client? client,
    String? baseUrl,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? http.Client(),
        _baseUrl = (baseUrl ?? const String.fromEnvironment('AI_AGENT_BASE_URL')).replaceFirst(RegExp(r'/+$'), '');

  final FirebaseAuth _auth;
  final http.Client _client;
  final String _baseUrl;

  Uri _uri(String path) {
    if (_baseUrl.isEmpty || !Uri.parse(_baseUrl).hasScheme) {
      throw StateError('AI Agent Ultimate no está configurado.');
    }
    return Uri.parse('$_baseUrl$path');
  }

  Future<Map<String, String>> _headers() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Inicia sesión para continuar.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) throw StateError('No se pudo verificar la sesión.');
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'};
  }

  Future<Map<String, dynamic>> _request(String method, String path, {Map<String, dynamic>? body}) async {
    final headers = await _headers();
    final uri = _uri(path);
    late http.Response response;
    switch (method) {
      case 'GET':
        response = await _client.get(uri, headers: headers);
      case 'POST':
        response = await _client.post(uri, headers: headers, body: jsonEncode(body));
      case 'PATCH':
        response = await _client.patch(uri, headers: headers, body: jsonEncode(body));
      case 'DELETE':
        response = await _client.delete(uri, headers: headers);
      default:
        throw UnsupportedError('Método HTTP no permitido.');
    }
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = decoded is Map ? decoded['error']?.toString() : null;
      throw CredentialVaultException(response.statusCode, code ?? 'request_failed');
    }
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<List<Map<String, dynamic>>> list() async {
    final result = await _request('GET', '/v1/credentials');
    return (result['credentials'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> save({
    required String label,
    required String websiteUrl,
    String? username,
    String? password,
    bool draft = false,
  }) => _request('POST', '/v1/credentials', body: {
        'label': label,
        'website_url': websiteUrl,
        if (username != null) 'username': username,
        if (password != null) 'password': password,
        'status': draft ? 'draft' : 'active',
      });

  Future<Map<String, dynamic>> update({
    required String id,
    required String label,
    required String websiteUrl,
    String? username,
    String? password,
    bool draft = false,
  }) => _request('PATCH', '/v1/credentials/$id', body: {
        'label': label,
        'website_url': websiteUrl,
        if (username != null) 'username': username,
        if (password != null) 'password': password,
        'status': draft ? 'draft' : 'active',
      });

  Future<void> delete(String id) async {
    await _request('DELETE', '/v1/credentials/$id');
  }

  void dispose() => _client.close();
}

class CredentialVaultException implements Exception {
  const CredentialVaultException(this.statusCode, this.code);
  final int statusCode;
  final String code;
  @override
  String toString() => 'CredentialVaultException($statusCode, $code)';
}
