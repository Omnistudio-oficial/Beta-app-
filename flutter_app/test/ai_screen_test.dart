import 'package:beta_app/screens/ai_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selects template, edits it and prepares prompt', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AIScreen()));

    await tester.scrollUntilVisible(find.text('Resumir un texto'), 250);
    await tester.tap(find.text('Resumir un texto'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prompt-editor')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('prompt-editor')), 'Resume este texto: OmniStudio');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('prepare-prompt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prepare-prompt')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('prepared-prompt')), findsOneWidget);
    expect(find.text('Resume este texto: OmniStudio'), findsOneWidget);
    expect(find.textContaining('todavía no genera respuestas con IA'), findsOneWidget);
  });

  testWidgets('does not enable prepare button for a blank prompt', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AIScreen()));
    await tester.scrollUntilVisible(find.text('Crear notas de producto'), 250);
    await tester.tap(find.text('Crear notas de producto'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('prompt-editor')), '  ');
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byKey(const Key('prepare-prompt')));
    expect(button.onPressed, isNull);
  });
}
