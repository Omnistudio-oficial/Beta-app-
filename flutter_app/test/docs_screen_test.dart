import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beta_app/screens/docs_screen.dart';
import 'package:beta_app/screens/docs_cloud_repository.dart';
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


class FakeCloudDocumentsRepository implements CloudDocumentsRepository {
  FakeCloudDocumentsRepository(this.uid);
  final String? uid;
  final docs = <String, Map<int, LocalDocument>>{};
  final requestedPaths = <String>[];
  final controller = StreamController<List<LocalDocument>>.broadcast();
  @override
  String? get currentUid => uid;
  @override
  Stream<List<LocalDocument>> watch(String userUid) {
    requestedPaths.add('documents/$userUid');
    return Stream<List<LocalDocument>>.multi((out) {
      out.add(docs[userUid]?.values.toList() ?? const []);
      final sub = controller.stream.listen(out.add, onError: out.addError);
      out.onCancel = sub.cancel;
    });
  }
  void _emit(String userUid) => controller.add(docs[userUid]?.values.toList() ?? const []);
  @override
  Future<void> create(String userUid, LocalDocument doc) async {
    requestedPaths.add('documents/$userUid/${doc.id}');
    (docs[userUid] ??= {})[doc.id] = doc;
    _emit(userUid);
  }
  @override
  Future<void> update(String userUid, LocalDocument doc) async => create(userUid, doc);
  @override
  Future<void> delete(String userUid, int id) async {
    requestedPaths.add('documents/$userUid/$id');
    docs[userUid]?.remove(id);
    _emit(userUid);
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

  testWidgets('cloud documents use the authenticated UID path and stream updates', (tester) async {
    final cloud = FakeCloudDocumentsRepository('user-a');
    cloud.docs['user-b'] = {7: LocalDocument(id: 7, title: 'Private B', content: 'B', updatedAt: DateTime.utc(2026))};
    await tester.pumpWidget(MaterialApp(home: DocsScreen(cloudRepository: cloud)));
    await tester.pumpAndSettle();
    expect(cloud.requestedPaths, contains('documents/user-a'));
    expect(find.text('Private B'), findsNothing);

    await openCreateDialog(tester);
    await saveDocument(tester, title: 'Cloud note', content: 'Saved to account');
    await tester.pumpAndSettle();
    expect(find.text('Cloud note'), findsOneWidget);
    expect(cloud.requestedPaths.any((path) => path.startsWith('documents/user-a/')), isTrue);
    expect(cloud.docs['user-b']!.values.single.title, 'Private B');

    final card = find.byType(ListTile).first;
    await tester.tap(card);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('document-content-input')), 'Updated across devices');
    await tester.tap(find.byKey(const Key('save-document')));
    await tester.pumpAndSettle();
    expect(find.text('Updated across devices'), findsOneWidget);
    expect(cloud.docs['user-b']!.values.single.title, 'Private B');

    await tester.tap(find.byTooltip('Eliminar Cloud note'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-document')));
    await tester.pumpAndSettle();
    expect(find.text('Cloud note'), findsNothing);
    expect(cloud.docs['user-a'], isEmpty);
    expect(cloud.docs['user-b']!.values.single.title, 'Private B');
    await cloud.controller.close();
  });

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
      createDirectory: (directory) async {},
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
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
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
      createDirectory: (directory) async {},
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
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(storage.value, originalStorage);
    expect(find.text('No se pudo preparar o compartir el archivo TXT.'), findsOneWidget);
  });

}
