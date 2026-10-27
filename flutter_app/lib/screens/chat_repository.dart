import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'chat_attachment.dart';
import 'chat_media_upload.dart';
import 'chat_message_schema.dart';

export 'chat_message_schema.dart';

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

abstract interface class ChatRepository {
  Stream<List<ChatChannel>> watchChannels({required String uid, required String email});
  Stream<List<ChatMessage>> watchMessages({required String uid, required String channelId});
  Future<void> sendText({required String uid, required String email, required String channelId, required String text});
  Future<void> toggleReaction({required String uid, required String channelId, required String messageId, required String emoji});
  Future<void> sendAttachment({required String uid, required String email, required String channelId, required ChatAttachment attachment, required String caption});
}

/// Uses the existing chats/{channelId}/messages schema. Membership filtering is
/// deliberately client-side because the deployed RTDB rules currently permit
/// every authenticated user to read all of /chats.
class FirebaseChatRepository implements ChatRepository {
  FirebaseChatRepository({FirebaseAuth? auth, FirebaseDatabase? database, ChatMediaUploadGateway? mediaGateway})
      : _auth = auth ?? FirebaseAuth.instance,
        _database = database ?? FirebaseDatabase.instance,
        _mediaGateway = mediaGateway ?? FirebaseChatMediaUploadGateway(auth: auth);

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;
  final ChatMediaUploadGateway _mediaGateway;

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
        messages.add(ChatMessage.fromMap(entry.key.toString(), channelId, map));
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
  Future<void> toggleReaction({required String uid, required String channelId, required String messageId, required String emoji}) async {
    final user = _requireUser(uid);
    await _ensureMember(uid, user.email ?? '', channelId);
    if (messageId.isEmpty) throw ArgumentError('No se encontró el mensaje.');
    final ref = _database.ref('chats/$channelId/messages/$messageId/reactions');
    await ref.runTransaction((currentValue) {
      final current = currentValue is String ? currentValue : '';
      return Transaction.success(toggleChatReaction(current, emoji));
    });
  }

  @override
  Future<void> sendAttachment({required String uid, required String email, required String channelId, required ChatAttachment attachment, required String caption}) async {
    final user = _requireUser(uid);
    if (email.trim().isEmpty || user.email?.trim().toLowerCase() != email.trim().toLowerCase()) throw StateError('La identidad de la sesión no coincide.');
    await _ensureMember(uid, email, channelId);
    await uploadThenSendChatMedia(
      attachment: attachment,
      caption: caption,
      upload: (_) => _mediaGateway.upload(uid: uid, filePath: attachment.path, fileName: attachment.name, mimeType: attachment.mimeType, mediaType: attachment.mediaType),
      cleanup: (path) => _mediaGateway.delete(uid: uid, storagePath: path),
      writeMessage: (selected, uploaded, cleanCaption) async {
        final current = _requireUser(uid);
        if (current.email?.trim().toLowerCase() != email.trim().toLowerCase()) throw StateError('La cuenta cambió durante la subida.');
        await _ensureMember(uid, email, channelId);
        final now = DateTime.now().millisecondsSinceEpoch;
        final ref = _database.ref('chats/$channelId/messages').push();
        final id = ref.key;
        if (id == null) throw StateError('No se pudo crear el mensaje.');
        final sender = current.displayName?.trim().isNotEmpty == true ? current.displayName!.trim() : email.split('@').first;
        final message = betaChatAttachmentMessage(messageId: id, channelId: channelId, senderId: uid, senderName: sender, senderEmail: email, caption: cleanCaption, timestamp: now, attachment: selected, mediaUrl: uploaded.publicUrl);
        await ref.set(message);
        // Preview metadata is auxiliary. Do not roll back/delete the object after
        // the durable RTDB message is successfully written.
        try {
          await _database.ref('chats/$channelId').update({'lastMessageText': message['text'], 'lastMessageTimestamp': now, 'lastMessageSender': sender, 'lastUpdated': now});
        } catch (_) { /* the live message remains successfully sent */ }
      },
    );
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
