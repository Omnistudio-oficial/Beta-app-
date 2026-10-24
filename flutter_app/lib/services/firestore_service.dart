import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> setUserProfile(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).set(data, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final snapshot = await _db.collection('users').doc(uid).get();
    return snapshot.exists ? snapshot.data() : null;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchUserProfile(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  Future<void> addLog(String collection, Map<String, dynamic> payload) async {
    await _db.collection(collection).add(payload);
  }
}
