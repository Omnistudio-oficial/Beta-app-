import 'dart:convert';

import 'package:beta_app/services/otp_handoff_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('creates a session only for HTTPS origins and authenticates with Firebase', () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'session_id': '11111111-2222-4333-8444-555555555555',
          'browser_token': 'temporary-browser-token',
          'origin': 'https://example.com',
          'method': 'email',
          'expires_at': DateTime.now().add(const Duration(seconds: 90)).toIso8601String(),
          'ttl_seconds': 90,
        }),
        201,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = OtpHandoffService(
      client: client,
      idTokenProvider: () async => 'firebase-id-token',
    );

    final session = await service.createSession(
      origin: 'https://example.com',
      method: 'email',
    );

    expect(session.origin, 'https://example.com');
    expect(session.method, 'email');
    expect(captured?.headers['authorization'], 'Bearer firebase-id-token');
    expect(jsonDecode(captured!.body)['origin'], 'https://example.com');

    await expectLater(
      service.createSession(origin: 'http://example.com', method: 'email'),
      throwsArgumentError,
    );
    service.close();
  });

  test('submits with explicit confirmation and consumes once for the same origin', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'POST' && request.url.path.endsWith('/code')) {
        return http.Response('{"accepted":true}', 202);
      }
      if (request.method == 'GET' && request.url.path.endsWith('/consume')) {
        return http.Response(
          '{"code":"123456","consumed":true}',
          200,
          headers: {'cache-control': 'no-store'},
        );
      }
      return http.Response('{"error":"unexpected"}', 404);
    });
    final service = OtpHandoffService(
      client: client,
      idTokenProvider: () async => 'firebase-id-token',
    );
    final session = OtpHandoffSession(
      id: '11111111-2222-4333-8444-555555555555',
      browserToken: 'temporary-browser-token',
      origin: 'https://example.com',
      method: 'authenticator',
      expiresAt: DateTime.now().add(const Duration(seconds: 90)),
    );

    final code = await service.submitAndConsume(
      session: session,
      code: '123456',
    );

    expect(code, '123456');
    expect(requests, hasLength(2));
    expect(requests.first.headers['authorization'], 'Bearer firebase-id-token');
    expect(jsonDecode(requests.first.body), {
      'code': '123456',
      'confirmed': true,
    });
    expect(requests.last.headers['authorization'], 'Bearer temporary-browser-token');
    expect(requests.last.headers['origin'], 'https://example.com');

    service.close();
  });

  test('rejects malformed OTP before any network request', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      return http.Response('{}', 200);
    });
    final service = OtpHandoffService(
      client: client,
      idTokenProvider: () async => 'firebase-id-token',
    );
    final session = OtpHandoffSession(
      id: '11111111-2222-4333-8444-555555555555',
      browserToken: 'temporary-browser-token',
      origin: 'https://example.com',
      method: 'sms',
      expiresAt: DateTime.now().add(const Duration(seconds: 90)),
    );

    await expectLater(
      service.submitAndConsume(session: session, code: '12ab'),
      throwsArgumentError,
    );
    expect(requestCount, 0);
    service.close();
  });
}
