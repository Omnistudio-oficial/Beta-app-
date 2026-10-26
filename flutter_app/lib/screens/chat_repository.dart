import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class ChatChannel {
  const ChatChannel({required this.id, required this.name, this.lastMessage = '', this.memberEmails = const [], this.memberUids = const [], this.creatorEmail = '', this.creatorUid = ''});
  final String id;
  final String name;
  final String lastMessage;
  final List<String> memberEmails;
  final List<String> memberUids;
  final String creatorEmail;
  final String creatorUid;

  bool includesIdentity({required String uid, required String email}) {
    final normalized = email.trim().toLowerCase();
    final hasEmail = normalized.isNotEmpty && (memberEmails.any((member) => member.trim().toLowerCase() == normalized) || creatorEmail.trim().toLowerCase() == normalized);
    final hasUid = uid.trim().isNotEmpty && (memberUids.contains(uid.trim()) || creatorUid.trim() == uid.trim());
    return hasEmail || hasUid;
  }
}

List<ChatChannel> filterChannelsForIdentity(Iterable<ChatChannel> channels, {required String uid, required String email}) {
  if (uid.trim().isEmpty) return const [];
  return channels.where((channel) => channel.includesIdentity(uid: uid, email: email)).toList(growable: false);
}

class ChatMessage {
  const ChatMessage({required this.id, required this.senderName, required this.senderEmail, required this.text, required this.timestamp});
  final String id;
  final String senderName;
  final String senderEmail;
  final String text;
  final int timestamp;
}

abstract interface class ChatRepository {
  Stream<List<ChatChannel>> watchChannels({required String uid, required String email});
  Stream<List<ChatMessage>> watchMessages({required String uid, required String channelId});
  Future<void> sendText({required String uid, required String email, required String channelId, required String text});
}

/// Uses the existing chats/{channelId}/messages schema. Membership filtering is
/// deliberately client-side because the deployed RTDB rules currently permit
/// every authenticated user to read all of /chats.
class FirebaseChatRepository implements ChatRepository {
  FirebaseChatRepository({FirebaseAuth? auth, FirebaseDatabase? database})
      : _auth = auth ?? FirebaseAuth.instance,
        _database = database ?? FirebaseDatabase.instance;

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;

  User _requireUser(String uid) {
    final user = _auth.currentUser;
    if (user == null || user.uid != uid) throw StateError('La sesión cambió. Vuelve a abrir Chat.');
    return user;
  }

  @override
  Stream<List<ChatChannel>> watchChannels({required String uid, required String email}) async* {
    _requireUser(uid);
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) throw StateError('La cuenta no tiene un correo disponible.');
    await for (final event in _database.ref('chats').onValue) {
      _requireUser(uid);
      final value = event.snapshot.value;
      if (value is! Map) {
        yield const [];
        continue;
      }
      final channels = <ChatChannel>[];
      for (final entry in value.entries) {
        if (entry.key == null || entry.value is! Map) continue;
        final map = Map<Object?, Object?>.from(entry.value as Map);
        final rawMembers = map['members'];
        final members = rawMembers is List
            ? rawMembers.whereType<Map>().map((member) => '${member['email'] ?? ''}'.trim().toLowerCase()).toList()
            : <String>[];
        final creatorEmail = '${map['creatorEmail'] ?? ''}'.trim().toLowerCase();
        final rawMemberUids = rawMembers is List
            ? rawMembers.whereType<Map>().map((member) => '${member['uid'] ?? ''}'.trim()).where((memberUid) => memberUid.isNotEmpty).toList()
            : <String>[];
        final creatorUid = '${map['creatorUid'] ?? ''}'.trim();
        if (!members.contains(normalizedEmail) && creatorEmail != normalizedEmail && !rawMemberUids.contains(uid) && creatorUid != uid) continue;
        final name = '${map['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        channels.add(ChatChannel(
          id: entry.key.toString(),
          name: name,
          lastMessage: '${map['lastMessageText'] ?? map['lastMessage'] ?? ''}',
          memberEmails: members,
          memberUids: rawMemberUids,
          creatorEmail: creatorEmail,
          creatorUid: creatorUid,
        ));
      }
      yield channels;
    }
  }

  @override
  Stream<List<ChatMessage>> watchMessages({required String uid, required String channelId}) async* {
    final user = _requireUser(uid);
    await _ensureMember(uid, user.email ?? '', channelId);
    await for (final event in _database.ref('chats/$channelId/messages').onValue) {
      _requireUser(uid);
      final value = event.snapshot.value;
      if (value is! Map) {
        yield const [];
        continue;
      }
      final messages = <ChatMessage>[];
      for (final entry in value.entries) {
        if (entry.key == null || entry.value is! Map) continue;
        final map = Map<Object?, Object?>.from(entry.value as Map);
        messages.add(ChatMessage(
          id: entry.key.toString(),
          senderName: '${map['senderName'] ?? 'Usuario'}',
          senderEmail: '${map['senderEmail'] ?? ''}',
          text: '${map['text'] ?? ''}',
          timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
        ));
      }
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      yield messages;
    }
  }

  Future<void> _ensureMember(String uid, String email, String channelId) async {
    _requireUser(uid);
    final snapshot = await _database.ref('chats/$channelId').get();
    final value = snapshot.value;
    if (value is! Map) throw StateError('No se encontró este chat.');
    final map = Map<Object?, Object?>.from(value);
    final normalizedEmail = email.trim().toLowerCase();
    final rawMembers = map['members'];
    final members = rawMembers is List
        ? rawMembers.whereType<Map>().map((member) => '${member['email'] ?? ''}'.trim().toLowerCase()).toList()
        : <String>[];
    final memberUids = rawMembers is List ? rawMembers.whereType<Map>().map((member) => '${member['uid'] ?? ''}'.trim()).toList() : <String>[];
    if (!members.contains(normalizedEmail) && '${map['creatorEmail'] ?? ''}'.trim().toLowerCase() != normalizedEmail && !memberUids.contains(uid) && '${map['creatorUid'] ?? ''}'.trim() != uid) {
      throw StateError('No perteneces a este chat.');
    }
  }

  @override
  Future<void> sendText({required String uid, required String email, required String channelId, required String text}) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) throw ArgumentError('Escribe un mensaje antes de enviarlo.');
    final user = _requireUser(uid);
    if (email.trim().isEmpty || user.email?.trim().toLowerCase() != email.trim().toLowerCase()) {
      throw StateError('La identidad de la sesión no coincide.');
    }
    await _ensureMember(uid, email, channelId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final ref = _database.ref('chats/$channelId/messages').push();
    final id = ref.key;
    if (id == null) throw StateError('No se pudo crear el mensaje.');
    final senderName = user.displayName?.trim().isNotEmpty == true ? user.displayName!.trim() : email.split('@').first;
    await ref.set({
      'firestoreId': id,
      'channelId': channelId,
      'senderId': uid,
      'senderName': senderName,
      'senderEmail': email,
      'text': cleanText,
      'timestamp': now,
      'deliveryStatus': 'enviado',
      'reactions': '',
    });
    _requireUser(uid);
    await _database.ref('chats/$channelId').update({
      'lastMessageText': cleanText,
      'lastMessageTimestamp': now,
      'lastMessageSender': senderName,
      'lastUpdated': now,
    });
  }
}
