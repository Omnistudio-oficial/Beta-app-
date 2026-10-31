import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'docs_storage.dart';

/// Auth-scoped operations for the RTDB documents/{uid}/{docId} namespace.
abstract interface class CloudDocumentsRepository {
  String? get currentUid;
  Stream<List<LocalDocument>> watch(String uid);
  Future<void> create(String uid, LocalDocument document);
  Future<void> update(String uid, LocalDocument document);
  Future<void> delete(String uid, int documentId);
}

class FirebaseCloudDocumentsRepository implements CloudDocumentsRepository {
  FirebaseCloudDocumentsRepository({FirebaseAuth? auth, FirebaseDatabase? database})
      : _auth = auth ?? FirebaseAuth.instance,
        _database = database ?? FirebaseDatabase.instance;

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;

  @override
  String? get currentUid => _auth.currentUser?.uid;

  DatabaseReference _userDocuments(String uid) {
    if (uid.isEmpty || currentUid != uid) {
      throw StateError('Document access requires the authenticated account UID.');
    }
    return _database.ref('documents/$uid');
  }

  @override
  Stream<List<LocalDocument>> watch(String uid) =>
      _userDocuments(uid).onValue.map((event) {
        final documents = <LocalDocument>[];
        for (final child in event.snapshot.children) {
          final value = child.value;
          if (value is! Map) continue;
          final document = LocalDocument.fromJson(<String, dynamic>{
            'id': int.tryParse(child.key ?? ''),
            'title': value['title'],
            'content': value['content'],
            'updatedAt': value['updatedAt'],
          });
          if (document != null && value['ownerUid'] == uid) documents.add(document);
        }
        documents.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return documents;
      });

  Map<String, Object> _record(String uid, LocalDocument document) =>
      <String, Object>{...document.toJson(), 'ownerUid': uid};

  @override
  Future<void> create(String uid, LocalDocument document) async {
    await _userDocuments(uid).child(document.id.toString()).set(_record(uid, document));
  }

  @override
  Future<void> update(String uid, LocalDocument document) async {
    await _userDocuments(uid).child(document.id.toString()).set(_record(uid, document));
  }

  @override
  Future<void> delete(String uid, int documentId) async {
    await _userDocuments(uid).child(documentId.toString()).remove();
  }
}
