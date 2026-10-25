import 'dart:io';
import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands an already-local Docs document to the native Android/iOS share sheet.
/// The app's saved document is never written or changed by an export.
typedef DocumentTxtShareAction = Future<void> Function({
  required File file,
  required String title,
  required Rect? sharePositionOrigin,
});

class DocsTxtExporter {
  DocsTxtExporter({
    Future<Directory> Function()? temporaryDirectoryProvider,
    DocumentTxtShareAction? shareAction,
    Future<void> Function(File file, String content)? writeFile,
  })  : _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? getTemporaryDirectory,
        _shareAction = shareAction ?? _shareWithPlatform,
        _writeFile = writeFile ?? _writeUtf8File;

  final Future<Directory> Function() _temporaryDirectoryProvider;
  final DocumentTxtShareAction _shareAction;
  final Future<void> Function(File file, String content) _writeFile;

  static Future<void> _writeUtf8File(File file, String content) =>
      file.writeAsString(content, encoding: utf8, flush: true);

  Future<void> export({
    required String title,
    required String content,
    Rect? sharePositionOrigin,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'A document title is required.');
    }

    final filename = '${_safeFilenameStem(normalizedTitle)}.txt';
    final directory = await _temporaryDirectoryProvider();
    final exportDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}omnistudio_docs_exports',
    );
    await exportDirectory.create(recursive: true);
    final file = File(
      '${exportDirectory.path}${Platform.pathSeparator}$filename',
    );
    await _writeFile(file, content);

    await _shareAction(
      file: file,
      title: normalizedTitle,
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  static String _safeFilenameStem(String title) {
    final safe = title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '-')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'^\.+|\.+$'), '');
    return safe.isEmpty ? 'documento' : safe;
  }

  static Future<void> _shareWithPlatform({
    required File file,
    required String title,
    required Rect? sharePositionOrigin,
  }) async {
    final filename = file.uri.pathSegments.last;
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/plain', name: filename)],
      subject: title,
      text: title,
      sharePositionOrigin: sharePositionOrigin,
    );
  }
}
