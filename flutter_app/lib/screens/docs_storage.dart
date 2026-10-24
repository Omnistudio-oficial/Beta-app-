import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A document stored locally on this device. No account or backend is involved.
class LocalDocument {
  const LocalDocument({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final String content;
  final DateTime updatedAt;

  LocalDocument copyWith({String? title, String? content, DateTime? updatedAt}) =>
      LocalDocument(
        id: id,
        title: title ?? this.title,
        content: content ?? this.content,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object> toJson() => <String, Object>{
        'id': id,
        'title': title,
        'content': content,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static LocalDocument? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    final title = value['title'];
    final content = value['content'];
    final updatedAt = value['updatedAt'];
    if (id is! int || title is! String || content is! String || updatedAt is! String) {
      return null;
    }
    final date = DateTime.tryParse(updatedAt);
    if (date == null || title.trim().isEmpty) return null;
    return LocalDocument(
      id: id,
      title: title,
      content: content,
      updatedAt: date,
    );
  }
}

/// Tiny injectable boundary so persistence can be tested without platform APIs.
abstract interface class DocumentsStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesDocumentsStorage implements DocumentsStorage {
  static const storageKey = 'omnistudio.flutter.local_documents.v1';

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(storageKey);
  }

  @override
  Future<void> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    final stored = await preferences.setString(storageKey, value);
    if (!stored) throw StateError('Local document storage was unavailable.');
  }
}

class DocumentsLoadResult {
  const DocumentsLoadResult(this.documents, {this.recoveredCorruption = false});

  final List<LocalDocument> documents;
  final bool recoveredCorruption;
}

/// Serializes the complete local document collection as one JSON value.
class LocalDocumentsRepository {
  LocalDocumentsRepository(this.storage);

  final DocumentsStorage storage;

  Future<DocumentsLoadResult> load() async {
    final encoded = await storage.read();
    if (encoded == null || encoded.isEmpty) return const DocumentsLoadResult([]);
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const DocumentsLoadResult([], recoveredCorruption: true);
      final documents = <LocalDocument>[];
      var recoveredCorruption = false;
      for (final item in decoded) {
        final document = LocalDocument.fromJson(item);
        if (document == null) {
          recoveredCorruption = true;
        } else {
          documents.add(document);
        }
      }
      documents.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return DocumentsLoadResult(documents, recoveredCorruption: recoveredCorruption);
    } on FormatException {
      return const DocumentsLoadResult([], recoveredCorruption: true);
    }
  }

  Future<void> save(List<LocalDocument> documents) =>
      storage.write(jsonEncode(documents.map((document) => document.toJson()).toList()));
}
