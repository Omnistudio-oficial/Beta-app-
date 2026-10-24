import 'package:beta_app/screens/docs_screen.dart';
import 'package:beta_app/screens/docs_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDocumentsStorage implements DocumentsStorage {
  FakeDocumentsStorage([this.value]);

  String? value;
  bool failWrites = false;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    if (failWrites) throw StateError('private storage failure detail');
    this.value = value;
  }
}

void main() {
  Future<void> openCreateDialog(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('create-document')));
    await tester.pumpAndSettle();
  }

  Future<void> saveDocument(
    WidgetTester tester, {
    required String title,
    required String content,
  }) async {
    await tester.enterText(find.byKey(const Key('document-title-input')), title);
    await tester.enterText(
      find.byKey(const Key('document-content-input')),
      content,
    );
    await tester.tap(find.byKey(const Key('save-document')));
    await tester.pumpAndSettle();
  }

  testWidgets('creates, edits and persists documents across screen reloads',
      (tester) async {
    final storage = FakeDocumentsStorage();
    await tester.pumpWidget(MaterialApp(home: DocsScreen(storage: storage)));
    await tester.pumpAndSettle();
    expect(find.text('Aún no tienes documentos'), findsOneWidget);

    await openCreateDialog(tester);
    await saveDocument(tester, title: 'Notas', content: 'Primera versión');
    expect(find.text('Notas'), findsOneWidget);
    expect(find.text('Primera versión'), findsOneWidget);

    await tester.tap(find.byKey(const Key('document-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('document-title-input')),
      'Notas de clase',
    );
    await tester.enterText(
      find.byKey(const Key('document-content-input')),
      'Contenido actualizado',
    );
    await tester.tap(find.byKey(const Key('save-document')));
    await tester.pumpAndSettle();
    expect(find.text('Notas de clase'), findsOneWidget);
    expect(find.text('Contenido actualizado'), findsOneWidget);
    expect(find.text('Notas'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(home: DocsScreen(storage: storage)));
    await tester.pumpAndSettle();
    expect(find.text('Notas de clase'), findsOneWidget);
    expect(find.text('Contenido actualizado'), findsOneWidget);
  });

  testWidgets('searches by title or body and shows no matches', (tester) async {
    final storage = FakeDocumentsStorage();
    await tester.pumpWidget(MaterialApp(home: DocsScreen(storage: storage)));
    await tester.pumpAndSettle();
    await openCreateDialog(tester);
    await saveDocument(tester, title: 'Reunión', content: 'Plan de lanzamiento');
    await openCreateDialog(tester);
    await saveDocument(tester, title: 'Ideas', content: 'Receta de pan');

    await tester.enterText(find.byKey(const Key('document-search')), 'lanzamiento');
    await tester.pumpAndSettle();
    expect(find.text('Reunión'), findsOneWidget);
    expect(find.text('Ideas'), findsNothing);

    await tester.enterText(find.byKey(const Key('document-search')), 'no existe');
    await tester.pumpAndSettle();
    expect(find.text('No se encontraron documentos'), findsOneWidget);
  });

  testWidgets('requires a title and delete is persisted after confirmation',
      (tester) async {
    final storage = FakeDocumentsStorage();
    await tester.pumpWidget(MaterialApp(home: DocsScreen(storage: storage)));
    await tester.pumpAndSettle();
    await openCreateDialog(tester);
    await tester.enterText(find.byKey(const Key('document-content-input')), 'Texto');
    await tester.tap(find.byKey(const Key('save-document')));
    await tester.pump();
    expect(find.text('Escribe un título para el documento'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(find.byKey(const Key('document-title-input')), 'Borrador');
    await tester.tap(find.byKey(const Key('save-document')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-document-0')));
    await tester.pumpAndSettle();
    expect(find.text('Borrador'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete-document')));
    await tester.pumpAndSettle();
    expect(find.text('Aún no tienes documentos'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(home: DocsScreen(storage: storage)));
    await tester.pumpAndSettle();
    expect(find.text('Aún no tienes documentos'), findsOneWidget);
  });

  testWidgets('recovers safely from malformed JSON without showing exception',
      (tester) async {
    final storage = FakeDocumentsStorage('{not-json');
    await tester.pumpWidget(MaterialApp(home: DocsScreen(storage: storage)));
    await tester.pumpAndSettle();
    expect(find.text('Aún no tienes documentos'), findsOneWidget);
    expect(find.byKey(const Key('documents-recovery-notice')), findsOneWidget);
    expect(find.textContaining('FormatException'), findsNothing);
  });

  testWidgets('shows generic save error and keeps data when storage fails',
      (tester) async {
    final storage = FakeDocumentsStorage()..failWrites = true;
    await tester.pumpWidget(MaterialApp(home: DocsScreen(storage: storage)));
    await tester.pumpAndSettle();
    await openCreateDialog(tester);
    await saveDocument(tester, title: 'No guardado', content: 'Texto');
    expect(find.byKey(const Key('documents-error')), findsOneWidget);
    expect(find.textContaining('private storage failure detail'), findsNothing);
    expect(find.text('Aún no tienes documentos'), findsOneWidget);
  });
}
