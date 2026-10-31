import 'package:beta_app/screens/chat_calls.dart';
import 'package:beta_app/screens/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('call eligibility requires a direct channel, a non-group, and two different verified users', () {
    expect(isAllowedOneToOneCall(channelId: 'direct_123', isGroup: false, callerUid: 'a', peerUid: 'b'), isTrue);
    expect(isAllowedOneToOneCall(channelId: 'group_123', isGroup: false, callerUid: 'a', peerUid: 'b'), isFalse);
    expect(isAllowedOneToOneCall(channelId: 'direct_123', isGroup: true, callerUid: 'a', peerUid: 'b'), isFalse);
    expect(isAllowedOneToOneCall(channelId: 'direct_123', isGroup: false, callerUid: 'a', peerUid: 'a'), isFalse);
    expect(isAllowedOneToOneCall(channelId: 'direct_123', isGroup: false, callerUid: '', peerUid: 'b'), isFalse);
    expect(isAllowedOneToOneCall(channelId: 'direct_123', isGroup: false, callerUid: 'a', peerUid: ''), isFalse);
    expect(isAllowedOneToOneCall(channelId: 'direct_123_suffix', isGroup: false, callerUid: 'a', peerUid: 'b'), isTrue);
  });

  test('call membership authorization requires exactly both verified channel members', () {
    const members = <ChatMember>[
      ChatMember(uid: 'caller', email: 'caller@example.com'),
      ChatMember(uid: 'peer', email: 'peer@example.com'),
    ];
    expect(isAuthorizedOneToOneMembership(channelId: 'direct_room', isDirect: true, isGroup: false, members: members, callerUid: 'caller', callerEmail: 'caller@example.com', peerUid: 'peer', peerEmail: 'peer@example.com'), isTrue);
    expect(isAuthorizedOneToOneMembership(channelId: 'direct_room', isDirect: true, isGroup: false, members: members.take(1).toList(), callerUid: 'caller', callerEmail: 'caller@example.com', peerUid: 'peer', peerEmail: 'peer@example.com'), isFalse);
    expect(isAuthorizedOneToOneMembership(channelId: 'direct_room', isDirect: true, isGroup: false, members: [...members, const ChatMember(uid: 'intruder', email: 'x@example.com')], callerUid: 'caller', callerEmail: 'caller@example.com', peerUid: 'peer', peerEmail: 'peer@example.com'), isFalse);
    expect(isAuthorizedOneToOneMembership(channelId: 'direct_room', isDirect: true, isGroup: false, members: members, callerUid: 'caller', callerEmail: 'Caller@example.com', peerUid: 'peer', peerEmail: 'peer@example.com'), isTrue);
    expect(isAuthorizedOneToOneMembership(channelId: 'group_room', isDirect: false, isGroup: true, members: members, callerUid: 'caller', callerEmail: 'caller@example.com', peerUid: 'peer', peerEmail: 'peer@example.com'), isFalse);
    expect(isAuthorizedOneToOneMembership(channelId: 'direct_room', isDirect: true, isGroup: false, members: members, callerUid: 'caller', callerEmail: 'caller@example.com', peerUid: 'outsider', peerEmail: 'outsider@example.com'), isFalse);
  });

  test('membership parser accepts both deployed list and keyed member formats', () {
    final listMembers = chatMembersFromChannel({'members': [
      {'uid': 'caller', 'email': 'caller@example.com'},
      {'uid': 'peer', 'email': 'peer@example.com'},
    ]});
    final keyedMembers = chatMembersFromChannel({'members': {
      'caller-key': {'uid': 'caller', 'email': 'caller@example.com'},
      'peer-key': {'uid': 'peer', 'email': 'peer@example.com'},
    }});
    expect(listMembers.map((member) => member.uid), containsAll(['caller', 'peer']));
    expect(keyedMembers.map((member) => member.uid), containsAll(['caller', 'peer']));
  });

  test('call signal reads current Main-compatible participant and media fields', () {
    final signal = ChatCallSignal.fromSnapshot('call-1', {
      'channelId': 'direct_room', 'callerUid': 'caller', 'peerUid': 'peer',
      'callerName': 'Caller', 'peerName': 'Peer', 'callerEmail': 'a@example.com',
      'peerEmail': 'b@example.com', 'isVideo': true, 'status': 'RINGING',
      'startTimeMs': 1234,
    });
    expect(signal.callId, 'call-1');
    expect(signal.isVideo, isTrue);
    expect(signal.status, 'RINGING');
    expect(signal.startedAt, 1234);
    expect(signal.peerUid, 'peer');
  });
}
