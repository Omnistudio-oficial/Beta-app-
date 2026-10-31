import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'chat_attachment.dart';
import 'chat_media_upload.dart';
import 'chat_message_schema.dart';

export 'chat_message_schema.dart';

class ChatMember {
  const ChatMember({required this.email, this.name = '', this.uid = '', this.role = 'member', this.canSendMessages = true, this.canSendMedia = true, this.canInviteMembers = true, this.avatarUrl = ''});
  final String email, name, uid, role, avatarUrl;
  final bool canSendMessages, canSendMedia, canInviteMembers;
  bool matches({required String uid, required String email}) =>
      (this.uid.isNotEmpty && this.uid == uid) || (email.trim().isNotEmpty && this.email.trim().toLowerCase() == email.trim().toLowerCase());
  Map<String, Object?> toMap() => {'email': email, 'name': name, if (uid.isNotEmpty) 'uid': uid, 'role': role, 'canSendMessages': canSendMessages, 'canSendMedia': canSendMedia, 'canInviteMembers': canInviteMembers, 'avatarUrl': avatarUrl};
  factory ChatMember.fromMap(Object? value) {
    final map = value is Map ? Map<Object?, Object?>.from(value) : <Object?, Object?>{};
    return ChatMember(email: '${map['email'] ?? ''}', name: '${map['name'] ?? ''}', uid: '${map['uid'] ?? ''}', role: '${map['role'] ?? 'member'}', canSendMessages: map['canSendMessages'] != false, canSendMedia: map['canSendMedia'] != false, canInviteMembers: map['canInviteMembers'] != false, avatarUrl: '${map['avatarUrl'] ?? ''}');
  }
}

class ChatChannel {
  const ChatChannel({required this.id, required this.name, this.lastMessage = '', this.memberEmails = const [], this.memberUids = const [], this.members = const [], this.creatorEmail = '', this.creatorUid = '', this.creatorName = '', this.description = '', this.groupPhotoUrl = '', this.isGroup = false, this.isDeleting = false, this.pendingDeletionTimestamp});
  final String id;
  final String name, lastMessage, creatorEmail, creatorUid, creatorName, description, groupPhotoUrl;
  final List<String> memberEmails, memberUids;
  final List<ChatMember> members;
  final bool isGroup, isDeleting;
  final int? pendingDeletionTimestamp;

  bool includesIdentity({required String uid, required String email}) {
    final normalized = email.trim().toLowerCase();
    final hasEmail = normalized.isNotEmpty && (memberEmails.any((member) => member.trim().toLowerCase() == normalized) || creatorEmail.trim().toLowerCase() == normalized);
    final hasUid = uid.trim().isNotEmpty && (memberUids.contains(uid.trim()) || creatorUid.trim() == uid.trim());
    return hasEmail || hasUid || members.any((member) => member.matches(uid: uid, email: email));
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
  Future<void> createGroup({required String uid, required String email, required String name, required String description, required List<String> memberEmails});
  Future<void> updateGroupInfo({required String uid, required String channelId, required String name, required String description});
  Future<void> addGroupMember({required String uid, required String channelId, required String memberEmail});
  Future<void> removeGroupMember({required String uid, required String channelId, required String memberEmail});
  Future<void> updateGroupMemberPermissions({required String uid, required String channelId, required String memberEmail, required bool canSendMessages, required bool canSendMedia});
  Future<void> leaveGroup({required String uid, required String channelId});
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
        final memberValues = rawMembers is List ? rawMembers : rawMembers is Map ? rawMembers.values.toList() : const [];
        final parsedMembers = memberValues.map(ChatMember.fromMap).where((member) => member.email.isNotEmpty || member.uid.isNotEmpty).toList();
        final members = parsedMembers.map((member) => member.email.trim().toLowerCase()).where((member) => member.isNotEmpty).toList();
        final creatorEmail = '${map['creatorEmail'] ?? ''}'.trim().toLowerCase();
        final rawMemberUids = parsedMembers.map((member) => member.uid.trim()).where((memberUid) => memberUid.isNotEmpty).toList();
        final creatorUid = '${map['creatorUid'] ?? ''}'.trim();
        if (!members.contains(normalizedEmail) && creatorEmail != normalizedEmail && !rawMemberUids.contains(uid) && creatorUid != uid) continue;
        final name = '${map['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        channels.add(ChatChannel(
          id: entry.key.toString(), name: name,
          lastMessage: '${map['lastMessageText'] ?? map['lastMessage'] ?? ''}',
          memberEmails: members, memberUids: rawMemberUids, members: parsedMembers,
          creatorEmail: creatorEmail, creatorUid: creatorUid,
          creatorName: '${map['creatorName'] ?? ''}', description: '${map['description'] ?? ''}',
          groupPhotoUrl: '${map['groupPhotoUrl'] ?? ''}', isGroup: map['isGroup'] == true,
          isDeleting: map['isDeleting'] == true,
          pendingDeletionTimestamp: (map['pendingDeletionTimestamp'] as num?)?.toInt(),
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

  Future<(User, Map<Object?, Object?>)> _requireGroupOwner(String uid, String channelId) async {
    final user = _requireUser(uid);
    final snapshot = await _database.ref('chats/$channelId').get();
    if (snapshot.value is! Map) throw StateError('No se encontró el grupo.');
    final data = Map<Object?, Object?>.from(snapshot.value as Map);
    if (data['isGroup'] != true) throw StateError('Esta conversación no es un grupo.');
    if ('${data['creatorUid'] ?? ''}' != uid && '${data['creatorEmail'] ?? ''}'.trim().toLowerCase() != (user.email ?? '').trim().toLowerCase()) throw StateError('Solo el creador puede administrar este grupo.');
    return (user, data);
  }

  List<ChatMember> _membersFrom(Object? value) {
    final values = value is List ? value : value is Map ? value.values.toList() : const [];
    return values.map(ChatMember.fromMap).where((member) => member.email.isNotEmpty || member.uid.isNotEmpty).toList();
  }

  Future<void> _writeGroupMembers(String uid, String channelId, List<ChatMember> members) async {
    await _requireGroupOwner(uid, channelId);
    await _database.ref('chats/$channelId').update({'members': members.map((member) => member.toMap()).toList(), 'lastUpdated': ServerValue.timestamp});
  }

  @override
  Future<void> createGroup({required String uid, required String email, required String name, required String description, required List<String> memberEmails}) async {
    final user = _requireUser(uid);
    if (user.email?.trim().toLowerCase() != email.trim().toLowerCase()) throw StateError('La identidad de la sesión no coincide.');
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Escribe un nombre para el grupo.');
    final ref = _database.ref('chats').push();
    final channelId = ref.key;
    if (channelId == null) throw StateError('No se pudo crear el grupo.');
    final owner = ChatMember(email: email.trim(), name: user.displayName?.trim().isNotEmpty == true ? user.displayName!.trim() : email.split('@').first, uid: uid, role: 'owner');
    final uniqueEmails = memberEmails.map((value) => value.trim()).where((value) => value.isNotEmpty && value.toLowerCase() != email.trim().toLowerCase()).toSet();
    if (uniqueEmails.any((value) => !value.contains('@') || value.contains(' '))) throw ArgumentError('Revisa el correo de los integrantes.');
    final members = [owner, ...uniqueEmails.map((memberEmail) => ChatMember(email: memberEmail, name: memberEmail.split('@').first))];
    await ref.set({'id': channelId, 'name': cleanName, 'description': description.trim(), 'iconEmoji': '👥', 'isDirect': false, 'isGroup': true, 'groupPhotoUrl': '', 'creatorEmail': email.trim(), 'creatorUid': uid, 'creatorName': owner.name, 'members': members.map((member) => member.toMap()).toList(), 'isDeleting': false, 'lastUpdated': ServerValue.timestamp});
  }

  @override
  Future<void> updateGroupInfo({required String uid, required String channelId, required String name, required String description}) async {
    await _requireGroupOwner(uid, channelId);
    if (name.trim().isEmpty) throw ArgumentError('El nombre del grupo no puede quedar vacío.');
    await _database.ref('chats/$channelId').update({'name': name.trim(), 'description': description.trim(), 'lastUpdated': ServerValue.timestamp});
  }

  @override
  Future<void> addGroupMember({required String uid, required String channelId, required String memberEmail}) async {
    final email = memberEmail.trim();
    if (!email.contains('@') || email.contains(' ')) throw ArgumentError('Escribe un correo válido.');
    final result = await _requireGroupOwner(uid, channelId);
    final data = result.$2;
    final members = _membersFrom(data['members']);
    if (members.any((member) => member.email.toLowerCase() == email.toLowerCase())) return;
    members.add(ChatMember(email: email, name: email.split('@').first));
    await _writeGroupMembers(uid, channelId, members);
  }

  @override
  Future<void> removeGroupMember({required String uid, required String channelId, required String memberEmail}) async {
    final result = await _requireGroupOwner(uid, channelId);
    final data = result.$2;
    final ownerEmail = '${data['creatorEmail'] ?? ''}'.trim().toLowerCase();
    final email = memberEmail.trim().toLowerCase();
    if (email == ownerEmail) throw StateError('No puedes retirar al creador del grupo.');
    final members = _membersFrom(data['members']);
    await _writeGroupMembers(uid, channelId, members.where((member) => member.email.toLowerCase() != email).toList());
  }

  @override
  Future<void> updateGroupMemberPermissions({required String uid, required String channelId, required String memberEmail, required bool canSendMessages, required bool canSendMedia}) async {
    final result = await _requireGroupOwner(uid, channelId);
    final data = result.$2;
    final members = _membersFrom(data['members']);
    final index = members.indexWhere((member) => member.email.toLowerCase() == memberEmail.trim().toLowerCase());
    if (index < 0) throw StateError('No se encontró ese integrante.');
    members[index] = ChatMember(email: members[index].email, name: members[index].name, uid: members[index].uid, role: members[index].role, canSendMessages: canSendMessages, canSendMedia: canSendMedia, canInviteMembers: members[index].canInviteMembers, avatarUrl: members[index].avatarUrl);
    await _writeGroupMembers(uid, channelId, members);
  }

  @override
  Future<void> leaveGroup({required String uid, required String channelId}) async {
    final user = _requireUser(uid);
    final email = (user.email ?? '').trim().toLowerCase();
    final snapshot = await _database.ref('chats/$channelId').get();
    if (snapshot.value is! Map) throw StateError('No se encontró el grupo.');
    final data = Map<Object?, Object?>.from(snapshot.value as Map);
    if (data['isGroup'] != true) throw StateError('Esta conversación no es un grupo.');
    if ('${data['creatorUid'] ?? ''}' == uid || '${data['creatorEmail'] ?? ''}'.trim().toLowerCase() == email) throw StateError('El creador no puede salir sin transferir la administración.');
    final members = _membersFrom(data['members']).where((member) => !member.matches(uid: uid, email: email)).toList();
    await _database.ref('chats/$channelId').update({'members': members.map((member) => member.toMap()).toList(), 'lastUpdated': ServerValue.timestamp});
  }

  Future<void> _ensureCanSend(String uid, String email, String channelId, {bool media = false}) async {
    final snapshot = await _database.ref('chats/$channelId').get();
    if (snapshot.value is! Map) throw StateError('No se encontró este chat.');
    final data = Map<Object?, Object?>.from(snapshot.value as Map);
    if (data['isGroup'] != true) return;
    final user = _requireUser(uid);
    final members = _membersFrom(data['members']);
    final matchingMembers = members.where((member) => member.matches(uid: uid, email: email)).toList();
    final current = matchingMembers.isEmpty ? null : matchingMembers.first;
    if (current == null && '${data['creatorUid'] ?? ''}' != uid && '${data['creatorEmail'] ?? ''}'.trim().toLowerCase() != email.trim().toLowerCase()) throw StateError('No perteneces a este grupo.');
    if (media && current?.canSendMedia == false) throw StateError('El creador no habilitó el envío de archivos en este grupo.');
    if (!media && current?.canSendMessages == false) throw StateError('El creador no habilitó el envío de mensajes en este grupo.');
    if (user.uid != uid) throw StateError('La sesión cambió. Vuelve a abrir Chat.');
  }

  Future<void> _ensureMember(String uid, String email, String channelId) async {
    _requireUser(uid);
    final snapshot = await _database.ref('chats/$channelId').get();
    final value = snapshot.value;
    if (value is! Map) throw StateError('No se encontró este chat.');
    final map = Map<Object?, Object?>.from(value);
    final normalizedEmail = email.trim().toLowerCase();
    final parsedMembers = _membersFrom(map['members']);
    final members = parsedMembers.map((member) => member.email.trim().toLowerCase()).toList();
    final memberUids = parsedMembers.map((member) => member.uid.trim()).toList();
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
    await _ensureCanSend(uid, email, channelId, media: true);
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
    await _ensureCanSend(uid, email, channelId);
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
