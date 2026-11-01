import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

typedef OtpIdTokenProvider = Future<String?> Function();

class OtpHandoffSession {
  const OtpHandoffSession({
    required this.id,
    required this.browserToken,
    required this.origin,
    required this.method,
    required this.expiresAt,
  });

  final String id;
  final String browserToken;
  final String origin;
  final String method;
  final DateTime expiresAt;

  factory OtpHandoffSession.fromJson(Map<String, dynamic> json) {
    final id = json['session_id'];
    final token = json['browser_token'];
    final origin = json['origin'];
    final method = json['method'];
    final expiresAt = json['expires_at'];
    if (id is! String ||
        token is! String ||
        origin is! String ||
        method is! String ||
        expiresAt is! String) {
      throw const FormatException('Respuesta de sesión OTP inválida.');
    }
    return OtpHandoffSession(
      id: id,
      browserToken: token,
      origin: origin,
      method: method,
      expiresAt: DateTime.parse(expiresAt),
    );
  }
}

/// Handles only the short-lived OTP relay. Tokens and OTP values remain in
/// memory; this service never writes them to preferences, chat, or analytics.
class OtpHandoffService {
  OtpHandoffService({
    http.Client? client,
    OtpIdTokenProvider? idTokenProvider,
  })  : _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider ?? _firebaseIdToken;

  static const String _baseUrl =
      'https://ai-agent-ultimate.gonzalez24029.workers.dev/v1/otp/handoffs';

  final http.Client _client;
  final OtpIdTokenProvider _idTokenProvider;

  static Future<String?> _firebaseIdToken() async {
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  Future<String> _requireIdToken() async {
    final token = await _idTokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('Inicia sesión en OmniStudio para usar la verificación.');
    }
    return token;
  }

  Uri _sessionUri(String sessionId, [String? action]) {
    final suffix = action == null ? '' : '/$action';
    return Uri.parse('$_baseUrl/$sessionId$suffix');
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      // A generic error is returned below; never surface raw server content.
    }
    return const {};
  }

  void _check(http.Response response, Set<int> accepted) {
    if (accepted.contains(response.statusCode)) return;
    final error = _decode(response)['error'];
    switch (error) {
      case 'unauthorized':
        throw StateError('La sesión de OmniStudio venció. Inicia sesión de nuevo.');
      case 'otp_session_expired':
        throw StateError('La sesión OTP venció. Inicia una verificación nueva.');
      case 'invalid_otp_format':
        throw StateError('El código debe contener entre 4 y 10 dígitos.');
      case 'otp_already_submitted':
        throw StateError('Ya se envió un código en esta sesión. Inicia otra.');
      case 'forbidden':
        throw StateError('La sesión no coincide con el usuario o sitio autorizado.');
      default:
        throw StateError('No se pudo completar la transferencia OTP (' + response.statusCode.toString() + ').');
    }
  }

  Future<OtpHandoffSession> createSession({
    required String origin,
    required String method,
  }) async {
    final uri = Uri.tryParse(origin);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.origin != origin ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        !{'email', 'sms', 'authenticator'}.contains(method)) {
      throw ArgumentError('Se requiere un origen HTTPS y un método OTP válido.');
    }

    final token = await _requireIdToken();
    final response = await _client
        .post(
          Uri.parse(_baseUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'origin': origin, 'method': method}),
        )
        .timeout(const Duration(seconds: 15));
    _check(response, {201});
    return OtpHandoffSession.fromJson(_decode(response));
  }

  /// Sends the user-entered code to the temporary relay and immediately
  /// consumes it back into the native app for explicit insertion by the user.
  Future<String> submitAndConsume({
    required OtpHandoffSession session,
    required String code,
  }) async {
    if (!RegExp(r'^\d{4,10}$').hasMatch(code)) {
      throw ArgumentError('El código debe contener entre 4 y 10 dígitos.');
    }
    if (DateTime.now().isAfter(session.expiresAt)) {
      throw StateError('La sesión OTP venció. Inicia una verificación nueva.');
    }

    final idToken = await _requireIdToken();
    final submitted = await _client
        .post(
          _sessionUri(session.id, 'code'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'code': code, 'confirmed': true}),
        )
        .timeout(const Duration(seconds: 15));
    _check(submitted, {202});

    final consumed = await _client
        .get(
          _sessionUri(session.id, 'consume'),
          headers: {
            'Authorization': 'Bearer ' + session.browserToken + '',
            'Origin': session.origin,
            'Accept': 'application/json',
            'Cache-Control': 'no-store',
          },
        )
        .timeout(const Duration(seconds: 15));
    _check(consumed, {200});
    final payload = _decode(consumed);
    final returnedCode = payload['code'];
    if (payload['consumed'] != true || returnedCode is! String) {
      throw StateError('El servidor no confirmó el consumo único del código.');
    }
    return returnedCode;
  }

  Future<void> cancelSession(OtpHandoffSession session) async {
    final token = await _requireIdToken();
    final response = await _client
        .delete(
          _sessionUri(session.id),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 10));
    _check(response, {200});
  }

  void close() => _client.close();
}
