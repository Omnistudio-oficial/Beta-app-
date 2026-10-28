import 'package:beta_app/screens/call_dialog.dart';
import 'package:beta_app/screens/chat_calls.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class FakeCallSignaling implements ChatCallSignaling {
  @override
  Stream<List<ChatCallSignal>> watchCalls(String uid) => const Stream.empty();
  @override
  Future<String> createCall({required String callId, required String channelId, required String callerUid, required String peerUid, required String callerEmail, required String peerEmail, required String callerName, required String peerName, required String callerAvatarUrl, required String peerAvatarUrl, required bool isVideo}) async => callId;
  @override
  Future<void> writeSessionDescription(String callId, String role, String field, RTCSessionDescription description) async {}
  @override
  Future<void> writeIceCandidate(String callId, String role, RTCIceCandidate candidate) async {}
  @override
  Stream<DatabaseEvent> watchDescription(String callId, String field) => const Stream.empty();
  @override
  Stream<DatabaseEvent> watchCandidates(String callId, String role) => const Stream.empty();
  @override
  Stream<DatabaseEvent> watchStatus(String callId) => const Stream.empty();
  @override
  Future<void> updateStatus(String callId, String status) async {}
  @override
  Future<void> deleteCall(String callId) async {}
  @override
  Future<Map<Object?, Object?>> readPrivateChannel(String channelId) async => <Object?, Object?>{'isDirect': true, 'isGroup': false, 'members': <Object?>[]};
  @override
  Future<void> authorizeAnswer(String callId, {required String uid, required String channelId, required String callerUid, required String peerUid, required String currentEmail, required String callerEmail}) async {}
  @override
  Future<void> markConnected(String callId, {required String uid}) async {}
  @override
  Future<void> rejectCallSignal(String callId, {required String uid, required String channelId, required String callerUid, required String peerUid, required String currentEmail, required String callerEmail}) async {}
}

void main() {
  testWidgets('incoming call dialog exposes reject and answer actions without opening media', (tester) async {
    final controller = ChatCallController(signaling: FakeCallSignaling());
    const incoming = ChatCallSignal(callId: 'call-test', channelId: 'direct-test', callerUid: 'caller', peerUid: 'peer', callerName: 'Caller', peerName: 'Peer', isVideo: false, status: 'RINGING');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => Center(child: TextButton(onPressed: () => showDialog<void>(context: context, builder: (_) => ChatCallDialog(controller: controller, video: false, peerName: 'Caller', currentUid: 'peer', incoming: incoming)), child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-call-answer')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-call-reject')), findsOneWidget);
    controller.dispose();
  });
}
