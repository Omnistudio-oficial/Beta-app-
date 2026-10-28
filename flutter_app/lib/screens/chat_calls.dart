import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'chat_repository.dart';

class ChatCallSignal {
  const ChatCallSignal({required this.callId, required this.channelId, required this.callerUid, required this.peerUid, required this.callerName, required this.peerName, required this.isVideo, required this.status, this.callerEmail = '', this.peerEmail = '', this.callerAvatarUrl = '', this.peerAvatarUrl = '', this.startedAt = 0});
  final String callId, channelId, callerUid, peerUid, callerName, peerName, status, callerEmail, peerEmail, callerAvatarUrl, peerAvatarUrl;
  final bool isVideo;
  final int startedAt;
  bool get isIncoming => status == 'RINGING';

  factory ChatCallSignal.fromSnapshot(String id, Map<Object?, Object?> map) => ChatCallSignal(
    callId: id,
    channelId: '${map['channelId'] ?? ''}',
    callerUid: '${map['callerUid'] ?? ''}',
    peerUid: '${map['peerUid'] ?? ''}',
    callerName: '${map['callerName'] ?? ''}',
    peerName: '${map['peerName'] ?? ''}',
    isVideo: map['isVideo'] == true,
    status: '${map['status'] ?? 'RINGING'}',
    callerEmail: '${map['callerEmail'] ?? ''}',
    peerEmail: '${map['peerEmail'] ?? ''}',
    callerAvatarUrl: '${map['callerAvatarUrl'] ?? ''}',
    peerAvatarUrl: '${map['peerAvatarUrl'] ?? ''}',
    startedAt: (map['startTimeMs'] as num?)?.toInt() ?? 0,
  );
}

bool isAllowedOneToOneCall({required String channelId, required bool isGroup, required String callerUid, required String peerUid}) => channelId.startsWith('direct') && !isGroup && callerUid.isNotEmpty && peerUid.isNotEmpty && callerUid != peerUid;

List<ChatMember> chatMembersFromChannel(Map<Object?, Object?> channel) {
  final raw = channel['members'];
  final values = raw is List ? raw : raw is Map ? raw.values.toList() : const <Object?>[];
  return values.whereType<Map>().map(ChatMember.fromMap).toList(growable: false);
}

List<ChatMember> _membersFromChannel(Map<Object?, Object?> channel) {
  return chatMembersFromChannel(channel);
}

bool isAuthorizedOneToOneMembership({required String channelId, required bool isDirect, required bool isGroup, required List<ChatMember> members, required String callerUid, required String callerEmail, required String peerUid, required String peerEmail}) {
  if (!isAllowedOneToOneCall(channelId: channelId, isGroup: isGroup, callerUid: callerUid, peerUid: peerUid) || !isDirect || callerEmail.trim().isEmpty || peerEmail.trim().isEmpty || callerEmail.trim().toLowerCase() == peerEmail.trim().toLowerCase() || members.length != 2) return false;
  return members.any((member) => member.matches(uid: callerUid, email: callerEmail)) && members.any((member) => member.matches(uid: peerUid, email: peerEmail));
}

abstract interface class ChatCallSignaling {
  Stream<List<ChatCallSignal>> watchCalls(String uid);
  Future<String> createCall({required String callId, required String channelId, required String callerUid, required String peerUid, required String callerEmail, required String peerEmail, required String callerName, required String peerName, required String callerAvatarUrl, required String peerAvatarUrl, required bool isVideo});
  Future<void> writeSessionDescription(String callId, String role, String field, RTCSessionDescription description);
  Future<void> writeIceCandidate(String callId, String role, RTCIceCandidate candidate);
  Stream<DatabaseEvent> watchDescription(String callId, String field);
  Stream<DatabaseEvent> watchCandidates(String callId, String role);
  Stream<DatabaseEvent> watchStatus(String callId);
  Future<void> updateStatus(String callId, String status);
  Future<void> deleteCall(String callId);
  Future<Map<Object?, Object?>> readPrivateChannel(String channelId);
  Future<void> authorizeAnswer(String callId, {required String uid, required String channelId, required String callerUid, required String peerUid, required String currentEmail, required String callerEmail});
  Future<void> markConnected(String callId, {required String uid});
  Future<void> rejectCallSignal(String callId, {required String uid, required String channelId, required String callerUid, required String peerUid, required String currentEmail, required String callerEmail});
}

class FirebaseChatCallSignaling implements ChatCallSignaling {
  FirebaseChatCallSignaling({FirebaseDatabase? database}) : _database = database ?? FirebaseDatabase.instance;
  final FirebaseDatabase _database;
  DatabaseReference get _root => _database.ref('calls');

  @override
  Stream<List<ChatCallSignal>> watchCalls(String uid) {
    final user = FirebaseAuth.instance.currentUser;
    if (uid.isEmpty || user?.uid != uid) return Stream<List<ChatCallSignal>>.error(StateError('La sesión cambió.'));
    return Stream<List<ChatCallSignal>>.multi((controller) {
      var outgoingCalls = <String, ChatCallSignal>{};
      var incomingCalls = <String, ChatCallSignal>{};
      void publish() => controller.add({...outgoingCalls, ...incomingCalls}.values.toList());
      Map<String, ChatCallSignal> decode(DatabaseEvent event) {
        final out = <String, ChatCallSignal>{};
        final value = event.snapshot.value;
        if (value is Map) for (final entry in value.entries) { if (entry.key != null && entry.value is Map) out[entry.key.toString()] = ChatCallSignal.fromSnapshot(entry.key.toString(), Map<Object?, Object?>.from(entry.value as Map)); }
        return out;
      }
      final outgoing = _root.orderByChild('callerUid').equalTo(uid).onValue.listen((event) { outgoingCalls = decode(event); publish(); }, onError: controller.addError);
      final incoming = _root.orderByChild('peerUid').equalTo(uid).onValue.listen((event) { incomingCalls = decode(event); publish(); }, onError: controller.addError);
      controller.onCancel = () async { await outgoing.cancel(); await incoming.cancel(); };
    });
  }

  @override
  Future<String> createCall({required String callId, required String channelId, required String callerUid, required String peerUid, required String callerEmail, required String peerEmail, required String callerName, required String peerName, required String callerAvatarUrl, required String peerAvatarUrl, required bool isVideo}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.uid != callerUid || callerUid.isEmpty || peerUid.isEmpty || callerUid == peerUid || !isAllowedOneToOneCall(channelId: channelId, isGroup: false, callerUid: callerUid, peerUid: peerUid)) throw StateError('Las llamadas requieren un chat directo entre dos cuentas distintas.');
    final ref = _root.child(callId);
    final callerKey = callerEmail.replaceAll('.', '_').replaceAll('@', '_at_');
    final peerKey = peerEmail.replaceAll('.', '_').replaceAll('@', '_at_');
    if (callerEmail.trim().isEmpty || peerEmail.trim().isEmpty || callerEmail.trim().toLowerCase() == peerEmail.trim().toLowerCase()) throw StateError('No pude verificar que las dos cuentas sean distintas.');
    // Current app profiles are normally keyed by Firebase Auth UID. Legacy
    // profiles may be keyed by the sanitized email, as in the Kotlin client.
    final caller = await _readProfile(callerUid, callerKey, callerEmail);
    final peer = await _readProfile(peerUid, peerKey, peerEmail);
    final callerData = caller.value is Map ? Map<Object?, Object?>.from(caller.value as Map) : <Object?, Object?>{};
    final peerData = peer.value is Map ? Map<Object?, Object?>.from(peer.value as Map) : <Object?, Object?>{};
    if ('${callerData['uid'] ?? ''}' != callerUid || '${peerData['uid'] ?? ''}' != peerUid || '${callerData['email'] ?? ''}'.trim().toLowerCase() != callerEmail.trim().toLowerCase() || '${peerData['email'] ?? ''}'.trim().toLowerCase() != peerEmail.trim().toLowerCase()) throw StateError('No pude verificar los perfiles de ambas cuentas.');
    final existing = await _root.orderByChild('callerUid').equalTo(callerUid).get();
    if (existing.value is Map && (existing.value as Map).containsKey(callId)) throw StateError('Ya existe una llamada con este identificador.');
    final channelSnapshot = await _database.ref('chats/$channelId').get();
    if (channelSnapshot.value is! Map) throw StateError('No se encontró el chat directo.');
    final channel = Map<Object?, Object?>.from(channelSnapshot.value as Map);
    if (channel['isGroup'] == true || channel['isDirect'] != true) throw StateError('Las llamadas solo están disponibles en chats privados 1:1.');
    final callerEmailClean = callerEmail.trim().toLowerCase();
    final peerEmailClean = peerEmail.trim().toLowerCase();
    if (!channelId.startsWith('direct')) throw StateError('Las llamadas solo funcionan en chats directos.');
    final members = _membersFromChannel(channel);
    if (!isAuthorizedOneToOneMembership(channelId: channelId, isDirect: channel['isDirect'] == true, isGroup: channel['isGroup'] == true, members: members, callerUid: callerUid, callerEmail: callerEmailClean, peerUid: peerUid, peerEmail: peerEmailClean)) throw StateError('Las dos cuentas no aparecen en un chat privado directo de solo dos integrantes.');
    await ref.set({'callId': callId, 'channelId': channelId, 'callerUid': callerUid, 'peerUid': peerUid, 'callerEmail': callerEmail, 'peerEmail': peerEmail, 'callerName': callerName, 'peerName': peerName, 'callerAvatarUrl': callerAvatarUrl, 'peerAvatarUrl': peerAvatarUrl, 'isVideo': isVideo, 'status': 'RINGING', 'startTimeMs': ServerValue.timestamp});
    return callId;
  }

  Future<DataSnapshot> _readProfile(String uid, String legacyEmailKey, String email) async {
    final byUid = await _database.ref('users/$uid').get();
    if (byUid.exists) return byUid;
    final byLegacyKey = await _database.ref('users/$legacyEmailKey').get();
    if (byLegacyKey.exists) return byLegacyKey;
    final matches = await _database.ref('users').orderByChild('email').equalTo(email.trim()).get();
    return matches.children.isEmpty ? byLegacyKey : matches.children.first;
  }

  Future<Map<Object?, Object?>> _requireParticipant(String callId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('La sesión cambió.');
    final snapshot = await _root.orderByChild('callerUid').equalTo(user.uid).get();
    final peerSnapshot = await _root.orderByChild('peerUid').equalTo(user.uid).get();
    final callerData = snapshot.value is Map ? (snapshot.value as Map)[callId] : null;
    final peerData = peerSnapshot.value is Map ? (peerSnapshot.value as Map)[callId] : null;
    final ownedCall = callerData is Map ? callerData : peerData;
    if (ownedCall is! Map) throw StateError('La llamada no pertenece a esta cuenta.');
    return Map<Object?, Object?>.from(ownedCall);
  }

  Future<void> _requireRole(String callId, String role) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('La sesión cambió.');
    if (role != 'caller' && role != 'callee') throw StateError('Rol de señalización inválido.');
    final data = await _requireParticipant(callId);
    final field = role == 'caller' ? 'callerUid' : 'peerUid';
    if (data[field] != user.uid) throw StateError('No puedes escribir la señal de la otra persona.');
  }

  Stream<DatabaseEvent> _authorizedCallData(String callId, String childPath, {required bool childAdded}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream<DatabaseEvent>.error(StateError('La sesión cambió.'));
    return _root.orderByChild('callerUid').equalTo(user.uid).onValue.asyncExpand((callerEvent) {
      final callerData = callerEvent.snapshot.value;
      if (callerData is Map && callerData.containsKey(callId)) {
        final ref = _root.child(callId).child(childPath);
        return childAdded ? ref.onChildAdded : ref.onValue;
      }
      return _root.orderByChild('peerUid').equalTo(user.uid).onValue.asyncExpand((peerEvent) {
        final peerData = peerEvent.snapshot.value;
        if (peerData is Map && peerData.containsKey(callId)) {
          final ref = _root.child(callId).child(childPath);
          return childAdded ? ref.onChildAdded : ref.onValue;
        }
        return const Stream<DatabaseEvent>.empty();
      });
    });
  }

  @override
  Future<void> writeSessionDescription(String callId, String role, String field, RTCSessionDescription description) async {
    await _requireRole(callId, role);
    final permitted = (role == 'caller' && field == 'offer') || (role == 'callee' && field == 'answer');
    if (!permitted) throw StateError('El participante no puede publicar esa descripción.');
    final ref = _root.child(callId).child('rtc/$field');
    if ((await ref.get()).exists) throw StateError('La descripción de la llamada ya fue publicada.');
    await ref.set({'type': description.type, 'sdp': description.sdp});
  }
  @override
  Future<void> writeIceCandidate(String callId, String role, RTCIceCandidate candidate) async {
    if (role != 'caller' && role != 'callee') throw StateError('Rol de señalización inválido.');
    await _requireRole(callId, role);
    await _root.child(callId).child('rtc/candidates/$role').push().set({'candidate': candidate.candidate, 'sdpMid': candidate.sdpMid, 'sdpMLineIndex': candidate.sdpMLineIndex});
  }
  @override
  Stream<DatabaseEvent> watchDescription(String callId, String field) => _authorizedCallData(callId, 'rtc/$field', childAdded: false);
  @override
  Stream<DatabaseEvent> watchCandidates(String callId, String role) => _authorizedCallData(callId, 'rtc/candidates/$role', childAdded: true);
  @override
  Stream<DatabaseEvent> watchStatus(String callId) => _authorizedCallData(callId, 'status', childAdded: false);
  @override
  Future<void> updateStatus(String callId, String status) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('La sesión cambió.');
    final data = await _requireParticipant(callId);
    final allowed = status == 'ENDED' || (status == 'CONNECTED' && user.uid == data['peerUid'] && data['status'] == 'RINGING');
    if (!allowed) throw StateError('No puedes cambiar el estado de esta llamada.');
    await _root.child(callId).child('status').set(status);
  }
  @override
  Future<void> deleteCall(String callId) async {
    await _requireParticipant(callId);
    await _root.child(callId).remove();
  }
  @override
  Future<Map<Object?, Object?>> readPrivateChannel(String channelId) async {
    final snapshot = await _database.ref('chats/$channelId').get();
    if (snapshot.value is! Map) throw StateError('No se encontró el chat directo.');
    return Map<Object?, Object?>.from(snapshot.value as Map);
  }



  Future<void> _authorizeIncoming(String callId, {required String uid, required String channelId, required String callerUid, required String peerUid, required String currentEmail, required String callerEmail}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (!channelId.startsWith('direct') || user?.uid != uid || user?.email?.trim().toLowerCase() != currentEmail.trim().toLowerCase() || uid != peerUid || callerUid == peerUid) throw StateError('Esta llamada no está dirigida a tu cuenta.');
    final callData = await _requireParticipant(callId);
    if (callData['channelId'] != channelId || callData['callerUid'] != callerUid || callData['peerUid'] != peerUid || callData['status'] != 'RINGING') throw StateError('La llamada cambió o ya no está disponible.');
    final callerProfile = await _readProfile(callerUid, callerEmail.replaceAll('.', '_').replaceAll('@', '_at_'), callerEmail);
    final peerProfile = await _readProfile(peerUid, currentEmail.replaceAll('.', '_').replaceAll('@', '_at_'), currentEmail);
    final callerMap = callerProfile.value is Map ? Map<Object?, Object?>.from(callerProfile.value as Map) : <Object?, Object?>{};
    final peerMap = peerProfile.value is Map ? Map<Object?, Object?>.from(peerProfile.value as Map) : <Object?, Object?>{};
    if ('${callerMap['uid'] ?? ''}' != callerUid || '${peerMap['uid'] ?? ''}' != peerUid || '${callerMap['email'] ?? ''}'.trim().toLowerCase() != callerEmail.trim().toLowerCase() || '${peerMap['email'] ?? ''}'.trim().toLowerCase() != currentEmail.trim().toLowerCase()) throw StateError('No pude verificar los perfiles de ambas cuentas.');
    final channel = await readPrivateChannel(channelId);
    if (channel['isDirect'] != true || channel['isGroup'] == true) throw StateError('Las llamadas solo están disponibles en chats privados 1:1.');
    final members = _membersFromChannel(channel);
    if (!isAuthorizedOneToOneMembership(channelId: channelId, isDirect: channel['isDirect'] == true, isGroup: channel['isGroup'] == true, members: members, callerUid: callerUid, callerEmail: callerEmail, peerUid: uid, peerEmail: currentEmail)) throw StateError('No pude verificar que ambas cuentas pertenezcan a este chat directo de dos integrantes.');
  }


  @override
  Future<void> authorizeAnswer(String callId, {required String uid, required String channelId, required String callerUid, required String peerUid, required String currentEmail, required String callerEmail}) async {
    await _authorizeIncoming(callId, uid: uid, channelId: channelId, callerUid: callerUid, peerUid: peerUid, currentEmail: currentEmail, callerEmail: callerEmail);
  }

  @override
  Future<void> rejectCallSignal(String callId, {required String uid, required String channelId, required String callerUid, required String peerUid, required String currentEmail, required String callerEmail}) async {
    await _authorizeIncoming(callId, uid: uid, channelId: channelId, callerUid: callerUid, peerUid: peerUid, currentEmail: currentEmail, callerEmail: callerEmail);
    await _root.child(callId).child('status').set('ENDED');
  }

  @override
  Future<void> markConnected(String callId, {required String uid}) async {
    final data = await _requireParticipant(callId);
    if (data['peerUid'] != uid || FirebaseAuth.instance.currentUser?.uid != uid || data['status'] != 'RINGING') throw StateError('No puedes responder esta llamada.');
    await _root.child(callId).child('status').set('CONNECTED');
  }
}

class ChatCallController extends ChangeNotifier {
  ChatCallController({ChatCallSignaling? signaling, FirebaseAuth? auth}) : _signaling = signaling ?? FirebaseChatCallSignaling(), _auth = auth ?? FirebaseAuth.instance;
  final ChatCallSignaling _signaling;
  final FirebaseAuth _auth;
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription<DatabaseEvent>? _descriptionSub, _candidateSub, _statusSub;
  StreamSubscription<DatabaseEvent>? _callerCandidatesSub, _calleeCandidatesSub;
  bool _closed = false, isMuted = false, isCameraEnabled = true;
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];
  String? lastFinishedCallId;
  String status = 'Preparando llamada';
  ChatCallSignal? call;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get isVideo => call?.isVideo ?? false;

  Future<ChatCallSignal> startOutgoing({required ChatChannel channel, required String uid, required String email, required String displayName, required ChatMember peer, required bool video}) async {
    if (!isAllowedOneToOneCall(channelId: channel.id, isGroup: channel.isGroup, callerUid: uid, peerUid: peer.uid)) throw StateError('Las llamadas solo están disponibles en chats privados 1:1.');
    if (!channel.includesIdentity(uid: uid, email: email) || !peer.email.isNotEmpty || peer.uid.isEmpty || peer.uid == uid) throw StateError('No pude verificar las dos cuentas del chat.');
    final callId = 'call_${DateTime.now().microsecondsSinceEpoch}_${uid.substring(0, uid.length.clamp(1, 8))}';
    final current = _auth.currentUser;
    if (current?.uid != uid) throw StateError('La sesión cambió.');
    final channelMap = await _signaling.readPrivateChannel(channel.id);
    if (channelMap['isGroup'] == true || channelMap['isDirect'] != true) throw StateError('Las llamadas solo están disponibles en chats privados 1:1.');
    final members = _membersFromChannel(channelMap);
    if (!isAuthorizedOneToOneMembership(channelId: channel.id, isDirect: channelMap['isDirect'] == true, isGroup: channelMap['isGroup'] == true, members: members, callerUid: uid, callerEmail: email, peerUid: peer.uid, peerEmail: peer.email)) throw StateError('No pude verificar que ambas cuentas pertenezcan a este chat directo de dos integrantes.');
    call = ChatCallSignal(callId: callId, channelId: channel.id, callerUid: uid, peerUid: peer.uid, callerName: displayName.isNotEmpty ? displayName : email.split('@').first, peerName: peer.name.isNotEmpty ? peer.name : peer.email.split('@').first, callerEmail: email, peerEmail: peer.email, callerAvatarUrl: current?.photoURL ?? '', peerAvatarUrl: peer.avatarUrl, isVideo: video, status: 'RINGING');
    try { await _signaling.createCall(callId: callId, channelId: channel.id, callerUid: uid, peerUid: peer.uid, callerEmail: email, peerEmail: peer.email, callerName: call!.callerName, peerName: call!.peerName, callerAvatarUrl: call!.callerAvatarUrl, peerAvatarUrl: call!.peerAvatarUrl, isVideo: video); _watchRemoteStatus(callId); await _prepare(call!, outgoing: true); } catch (_) { try { await _signaling.updateStatus(callId, 'ENDED'); } catch (_) {} await _release(); call = null; rethrow; }
    return call!;
  }

  Future<void> rejectIncoming(ChatCallSignal incoming, {required String uid}) async {
    if (incoming.peerUid != uid || incoming.callerUid == uid) throw StateError('Esta llamada no está dirigida a tu cuenta.');
    final channelData = await _signaling.readPrivateChannel(incoming.channelId);
    final rawMembers = channelData['members'];
    final members = rawMembers is List ? rawMembers.whereType<Map>().map(ChatMember.fromMap).toList() : <ChatMember>[];
    final currentEmail = (_auth.currentUser?.email ?? '').trim();
    if (_auth.currentUser?.uid != uid || channelData['isDirect'] != true || channelData['isGroup'] == true || !members.any((member) => member.matches(uid: uid, email: currentEmail)) || !members.any((member) => member.matches(uid: incoming.callerUid, email: incoming.callerEmail))) throw StateError('No pude verificar esta llamada y sus participantes.');
    await _signaling.rejectCallSignal(incoming.callId, uid: uid, channelId: incoming.channelId, callerUid: incoming.callerUid, peerUid: incoming.peerUid, currentEmail: _auth.currentUser?.email ?? '', callerEmail: incoming.callerEmail);
    lastFinishedCallId = incoming.callId;
    status = 'Llamada rechazada'; notifyListeners();
  }

  Future<void> verifyIncoming(ChatCallSignal incoming, {required String uid}) async {
    if (_auth.currentUser?.uid != uid || incoming.peerUid != uid || incoming.callerUid == uid || incoming.status != 'RINGING') throw StateError('Esta llamada no está dirigida a tu cuenta.');
    await _signaling.authorizeAnswer(incoming.callId, uid: uid, channelId: incoming.channelId, callerUid: incoming.callerUid, peerUid: incoming.peerUid, currentEmail: _auth.currentUser?.email ?? '', callerEmail: incoming.callerEmail);
  }

  Future<void> answerIncoming(ChatCallSignal incoming, {required String uid}) async {
    if (_auth.currentUser?.uid != uid) throw StateError('La sesión cambió.');
    if (incoming.peerUid != uid || !incoming.channelId.startsWith('direct') || incoming.callerUid == uid) throw StateError('Esta llamada no está dirigida a tu cuenta.');
    await verifyIncoming(incoming, uid: uid);
    call = incoming;
    try {
      await _prepare(incoming, outgoing: false);
      await _signaling.markConnected(incoming.callId, uid: uid);
      _watchRemoteStatus(incoming.callId);
    } catch (_) {
      try { await _signaling.updateStatus(incoming.callId, 'ENDED'); } catch (_) {}
      await _release();
      lastFinishedCallId = incoming.callId;
      call = null;
      rethrow;
    }
  }

  void _watchRemoteStatus(String callId) {
    _statusSub = _signaling.watchStatus(callId).listen((event) {
      if (event.snapshot.value == 'CONNECTED' && call?.callId == callId && status.startsWith('Llamando')) {
        status = 'Conectando…';
        notifyListeners();
      }
      if (event.snapshot.value == 'ENDED' && call?.callId == callId) {
        unawaited(_release());
        lastFinishedCallId = callId;
        call = null;
        status = 'Llamada finalizada';
        notifyListeners();
      }
    });
  }

  Future<void> _prepare(ChatCallSignal active, {required bool outgoing}) async {
    final user = _auth.currentUser;
    if (user == null || (user.uid != active.callerUid && user.uid != active.peerUid)) throw StateError('La sesión no pertenece a esta llamada.');
    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': active.isVideo ? {'facingMode': 'user', 'width': 640, 'height': 480} : false});
    _peer = await createPeerConnection({'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}], 'sdpSemantics': 'unified-plan'});
    for (final track in _localStream!.getTracks()) { await _peer!.addTrack(track, _localStream!); }
    final localRole = outgoing ? 'caller' : 'callee';
    final remoteRole = outgoing ? 'callee' : 'caller';
    _peer!.onIceCandidate = (candidate) { if (candidate.candidate != null) unawaited(_signaling.writeIceCandidate(active.callId, localRole, candidate)); };
    _peer!.onTrack = (event) { if (event.streams.isNotEmpty) { _remoteStream = event.streams.first; status = 'Conectada'; notifyListeners(); } };
    _peer!.onConnectionState = (state) {
      status = switch (state) {
        RTCPeerConnectionState.RTCPeerConnectionStateConnected => 'Conectada',
        RTCPeerConnectionState.RTCPeerConnectionStateConnecting => 'Conectando…',
        RTCPeerConnectionState.RTCPeerConnectionStateDisconnected => 'Reconectando…',
        RTCPeerConnectionState.RTCPeerConnectionStateFailed => 'No se pudo conectar entre estas redes',
        RTCPeerConnectionState.RTCPeerConnectionStateClosed => 'Llamada finalizada',
        _ => status,
      };
      notifyListeners();
    };
    _candidateSub = _signaling.watchCandidates(active.callId, remoteRole).listen((event) async {
      final value = event.snapshot.value;
      if (value is! Map) return;
      final candidate = RTCIceCandidate('${value['candidate'] ?? ''}', value['sdpMid'] as String?, (value['sdpMLineIndex'] as num?)?.toInt());
      if (await _peer?.getRemoteDescription() == null) {
        _pendingRemoteCandidates.add(candidate);
      } else {
        await _peer?.addCandidate(candidate);
      }
    });
    if (outgoing) {
      final offer = await _peer!.createOffer();
      await _peer!.setLocalDescription(offer);
      _descriptionSub = _signaling.watchDescription(active.callId, 'answer').listen((event) async {
        final value = event.snapshot.value;
        if (value is Map && await _peer?.getRemoteDescription() == null) {
          await _peer?.setRemoteDescription(RTCSessionDescription('${value['sdp'] ?? ''}', '${value['type'] ?? 'answer'}'));
          await _flushRemoteCandidates();
        }
      });
      await _signaling.writeSessionDescription(active.callId, localRole, 'offer', offer);
      status = 'Llamando a ${active.peerName}';
    } else {
      final offerEvent = await _signaling.watchDescription(active.callId, 'offer').firstWhere((event) => event.snapshot.value is Map);
      final value = Map<Object?, Object?>.from(offerEvent.snapshot.value as Map);
      await _peer!.setRemoteDescription(RTCSessionDescription('${value['sdp'] ?? ''}', '${value['type'] ?? 'offer'}'));
      await _flushRemoteCandidates();
      final answer = await _peer!.createAnswer();
      await _peer!.setLocalDescription(answer);
      await _signaling.writeSessionDescription(active.callId, localRole, 'answer', answer);
      status = 'Conectando con ${active.callerName}';
    }
    notifyListeners();
  }

  Future<void> _flushRemoteCandidates() async {
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) { await _peer?.addCandidate(candidate); }
  }

  void toggleMute() { isMuted = !isMuted; for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) { track.enabled = !isMuted; } notifyListeners(); }
  void toggleCamera() { isCameraEnabled = !isCameraEnabled; for (final track in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) { track.enabled = isCameraEnabled; } notifyListeners(); }
  Future<void> switchCamera() async { final tracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]; if (tracks.isNotEmpty) await tracks.first.switchCamera(); }

  Future<void> endCall() async {
    final active = call;
    try {
      if (active != null) await _signaling.updateStatus(active.callId, 'ENDED');
    } finally {
      await _release();
      lastFinishedCallId = active?.callId;
      status = 'Llamada finalizada';
      call = null;
      notifyListeners();
    }
  }

  Future<void> _release() async {
    await _descriptionSub?.cancel(); await _candidateSub?.cancel(); await _statusSub?.cancel();
    await _callerCandidatesSub?.cancel(); await _calleeCandidatesSub?.cancel();
    _descriptionSub = null; _candidateSub = null; _statusSub = null; _callerCandidatesSub = null; _calleeCandidatesSub = null;
    await _peer?.close(); _peer = null;
    _pendingRemoteCandidates.clear();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) { await track.stop(); }
    await _localStream?.dispose(); _localStream = null;
    await _remoteStream?.dispose(); _remoteStream = null;
  }

  @override
  void dispose() { if (!_closed) { _closed = true; unawaited(_release()); } super.dispose(); }
}

/// Turns a WebRTC media stream into the video renderer used by the call sheet.
class ChatCallVideoView extends StatefulWidget {
  const ChatCallVideoView({super.key, required this.stream, this.mirror = false});
  final MediaStream? stream;
  final bool mirror;
  @override State<ChatCallVideoView> createState() => _ChatCallVideoViewState();
}
class _ChatCallVideoViewState extends State<ChatCallVideoView> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  @override void initState() { super.initState(); _renderer.initialize().then((_) { _renderer.srcObject = widget.stream; if (mounted) setState(() {}); }); }
  @override void didUpdateWidget(covariant ChatCallVideoView oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.stream != widget.stream) _renderer.srcObject = widget.stream; }
  @override void dispose() { _renderer.srcObject = null; unawaited(_renderer.dispose()); super.dispose(); }
  @override Widget build(BuildContext context) => RTCVideoView(_renderer, mirror: widget.mirror, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
}
