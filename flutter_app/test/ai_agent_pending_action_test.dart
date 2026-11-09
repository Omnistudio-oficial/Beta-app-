import 'package:flutter_test/flutter_test.dart';
import 'package:beta_app/services/ai_agent_ultimate_service.dart';

void main() {
  test('parses a pending GitHub repository approval without executing it', () {
    final action = AiAgentPendingAction.fromJson({
      'provider': 'github',
      'action': 'create_repository',
      'details': {
        'action': 'create_repository',
        'name': 'prueba',
        'private': true,
        'auto_init': true,
      },
      'approval_id': '123e4567-e89b-12d3-a456-426614174000',
      'idempotency_key': '123e4567-e89b-12d3-a456-426614174001',
      'expires_at': '2026-11-09T02:00:00.000Z',
    });

    expect(action.provider, 'github');
    expect(action.action, 'create_repository');
    expect(action.details['name'], 'prueba');
    expect(action.details['private'], isTrue);
    expect(action.toExecuteJson()['approval_id'], action.approvalId);
    expect(action.toExecuteJson()['idempotency_key'], action.idempotencyKey);
  });

  test('parses a pending Slack message approval', () {
    final action = AiAgentPendingAction.fromJson({
      'provider': 'slack',
      'action': 'send_message',
      'details': {'channel': 'C12345678', 'text': 'Hola equipo'},
      'approval_id': '123e4567-e89b-12d3-a456-426614174000',
      'idempotency_key': '123e4567-e89b-12d3-a456-426614174001',
      'expires_at': '2026-11-09T02:00:00.000Z',
    });

    expect(action.provider, 'slack');
    expect(action.details['channel'], 'C12345678');
    expect(action.details['text'], 'Hola equipo');
  });
}
