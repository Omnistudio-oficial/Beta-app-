import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:beta_app/models/user_profile.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get usersCollection =>
      _db.collection('users');

  Future<void> saveUserProfile(UserProfile profile) async {
    await usersCollection.doc(profile.uid).set(profile.toMap(), SetOptions(merge: true));
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    final doc = await usersCollection.doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserProfile.fromMap(uid, doc.data()!);
  }

  Stream<UserProfile?> watchUserProfile(String uid) {
    return usersCollection.doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) return null;
      return UserProfile.fromMap(uid, snapshot.data()!);
    });
  }

  Future<void> updateUserField(String uid, String field, dynamic value) async {
    await usersCollection.doc(uid).update({field: value});
  }

  Future<void> addActivityLog(String uid, Map<String, dynamic> payload) async {
    await usersCollection.doc(uid).collection('activity').add(payload);
  }
}
