import 'package:beta_app/services/workspace_sara_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkspaceQueryIntent', () {
    test('routes Gmail requests and strips service/command words', () {
      final intent = WorkspaceQueryIntent.parse('Sara, busca en Gmail correos de Liberty');
      expect(intent?.service, WorkspaceQueryService.gmail);
      expect(intent?.query.toLowerCase(), contains('liberty'));
      expect(intent?.query.toLowerCase(), isNot(contains('gmail')));
    });

    test('routes calendar requests', () {
      final intent = WorkspaceQueryIntent.parse('¿Qué tengo en Calendar esta semana?');
      expect(intent?.service, WorkspaceQueryService.calendar);
    });

    test('routes Drive file requests', () {
      final intent = WorkspaceQueryIntent.parse('Busca archivos PDF en Drive');
      expect(intent?.service, WorkspaceQueryService.drive);
    });

    test('does not treat unrelated prompts as workspace queries', () {
      expect(WorkspaceQueryIntent.parse('Explícame cómo funciona una ruta'), isNull);
      expect(WorkspaceQueryIntent.parse('  '), isNull);
    });
  });

  group('formatWorkspaceAnswer', () {
    test('gives truthful empty results for each read-only source', () {
      expect(formatWorkspaceAnswer(WorkspaceQueryService.gmail, const []), contains('No encontré correos'));
      expect(formatWorkspaceAnswer(WorkspaceQueryService.calendar, const []), contains('próximos 7 días'));
      expect(formatWorkspaceAnswer(WorkspaceQueryService.drive, const []), contains('No encontré archivos'));
    });

    test('formats a Gmail result using subject, sender, and snippet', () {
      final answer = formatWorkspaceAnswer(WorkspaceQueryService.gmail, [
        {'subject': 'Factura Liberty', 'from': 'Liberty', 'snippet': 'Total ₡12.000'},
      ]);
      expect(answer, contains('Factura Liberty'));
      expect(answer, contains('Liberty'));
      expect(answer, contains('₡12.000'));
    });

    test('formats calendar events and Drive files', () {
      expect(formatWorkspaceAnswer(WorkspaceQueryService.calendar, [
        {'summary': 'Cita', 'start': {'dateTime': '2026-10-28T09:00:00-06:00'}},
      ]), contains('Cita'));
      expect(formatWorkspaceAnswer(WorkspaceQueryService.drive, [
        {'name': 'Tarea.pdf', 'mimeType': 'application/pdf'},
      ]), contains('Tarea.pdf'));
    });
  });
}
