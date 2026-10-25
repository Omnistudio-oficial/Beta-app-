import 'dart:convert';
import 'dart:io';

import 'package:beta_app/screens/docs_screen.dart';
import 'package:beta_app/screens/docs_txt_export.dart';
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
  testWidgets('exports the selected local document as UTF-8 TXT without changing saved data',
      (tester) async {
    final originalDocument = <String, Object>{
      'id': 7,
      'title': 'Notas / clase',
      'content': 'Primera línea — café ☕',
      'updatedAt': DateTime.utc(2026, 10, 25).toIso8601String(),
    };
    final originalStorage = jsonEncode([originalDocument]);
    final storage = FakeDocumentsStorage(originalStorage);
    final files = <String, String>{};
    String? handedOffFilename;
    String? handedOffTitle;
    Rect? handedOffOrigin;
    final exporter = DocsTxtExporter(
      temporaryDirectoryProvider: () async => Directory('/tmp/docs-test'),
      writeFile: (file, content) async {
        files[file.uri.pathSegments.last] = content;
      },
      shareAction: ({required file, required title, required sharePositionOrigin}) async {
        handedOffFilename = file.uri.pathSegments.last;
        handedOffTitle = title;
        handedOffOrigin = sharePositionOrigin;
        // A normally completed native sheet includes user cancellation; it
        // must be treated as a completed hand-off, not as a Docs edit.
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: DocsScreen(storage: storage, txtExporter: exporter),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-document-7')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(handedOffTitle, 'Notas / clase');
    expect(handedOffFilename, 'Notas_-_clase.txt');
    expect(files['Notas_-_clase.txt'], 'Primera línea — café ☕');
    expect(handedOffOrigin, isNotNull);
    expect(storage.value, originalStorage);
    expect(find.textContaining('Elige dónde compartir o guardar'), findsOneWidget);
  });

  testWidgets('share-sheet errors leave the already-saved Docs document unchanged',
      (tester) async {
    final originalStorage = jsonEncode([
      <String, Object>{
        'id': 8,
        'title': 'Borrador',
        'content': 'Conservar exactamente',
        'updatedAt': DateTime.utc(2026, 10, 25).toIso8601String(),
      },
    ]);
    final storage = FakeDocumentsStorage(originalStorage);
    final exporter = DocsTxtExporter(
      temporaryDirectoryProvider: () async => Directory('/tmp/docs-test'),
      writeFile: (file, content) async {},
      shareAction: ({required file, required title, required sharePositionOrigin}) async {
        throw StateError('platform share failed');
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: DocsScreen(storage: storage, txtExporter: exporter),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-document-8')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(storage.value, originalStorage);
    expect(find.text('No se pudo preparar o compartir el archivo TXT.'), findsOneWidget);
  });

}
