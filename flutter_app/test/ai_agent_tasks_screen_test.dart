import 'package:beta_app/screens/ai_agent_tasks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows autonomous task composer and history', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AiAgentTasksScreen()));
    await tester.pump();
    expect(find.text('¿Qué debe hacer Sara?'), findsOneWidget);
    expect(find.byKey(const Key('agent-task-prompt')), findsOneWidget);
    expect(find.byKey(const Key('agent-task-create')), findsOneWidget);
    expect(find.text('Historial de tareas'), findsOneWidget);
    expect(find.textContaining('Todavía no hay tareas'), findsOneWidget);
  });
}
