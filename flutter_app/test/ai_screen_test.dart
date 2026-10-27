import 'package:beta_app/screens/ai_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selects template, edits it and prepares prompt', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AIScreen()));

    await tester.scrollUntilVisible(find.text('Resumir un texto'), 220, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resumir un texto'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('prompt-editor')), 220, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prompt-editor')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('prompt-editor')), 'Resume este texto: OmniStudio');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('prepare-prompt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prepare-prompt')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('prepared-prompt')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('prepared-prompt')),
        matching: find.text('Resume este texto: OmniStudio'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('does not enable prepare button for a blank prompt', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AIScreen()));
    await tester.scrollUntilVisible(find.text('Crear notas de producto').first, 220, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear notas de producto'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('prompt-editor')), 220, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('prompt-editor')), '  ');
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byKey(const Key('prepare-prompt')));
    expect(button.onPressed, isNull);
  });
  testWidgets('shows read-only Google Workspace connection in Sara', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AIScreen()));
    await tester.scrollUntilVisible(find.byKey(const Key('google-workspace-card')), 220, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('google-workspace-card')), findsOneWidget);
    expect(find.text('Conexión de solo lectura para Gmail, Calendar y Drive. Sara no enviará, editará ni borrará datos.'), findsOneWidget);
    expect(find.byKey(const Key('google-workspace-connect')), findsOneWidget);
  });

  testWidgets('Sara requests Google connection only when Workspace context is enabled', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AIScreen()));
    await tester.scrollUntilVisible(find.byKey(const Key('sara-workspace-context')), 220, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sara-workspace-context')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('sara-workspace-chat-input')), 220, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sara-workspace-chat-input')), 'Busca correos en Gmail');
    await tester.tap(find.byKey(const Key('sara-workspace-chat-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Conecta Google Workspace primero'), findsOneWidget);
  });
}
