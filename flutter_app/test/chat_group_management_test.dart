import 'package:beta_app/screens/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group members preserve Main-compatible fields through RTDB serialization', () {
    const member = ChatMember(email: 'member@example.com', name: 'Member', uid: 'member-uid', role: 'member', canSendMessages: false, canSendMedia: true, canInviteMembers: false, avatarUrl: 'https://example.com/avatar.png');
    final restored = ChatMember.fromMap(member.toMap());
    expect(restored.email, member.email);
    expect(restored.name, member.name);
    expect(restored.uid, member.uid);
    expect(restored.role, member.role);
    expect(restored.canSendMessages, isFalse);
    expect(restored.canSendMedia, isTrue);
    expect(restored.canInviteMembers, isFalse);
    expect(restored.avatarUrl, member.avatarUrl);
  });

  test('group channel retains owner, group settings, and member details', () {
    const channel = ChatChannel(id: 'group-1', name: 'Study group', creatorEmail: 'owner@example.com', creatorUid: 'owner-uid', creatorName: 'Owner', description: 'Classwork', groupPhotoUrl: 'https://example.com/group.png', isGroup: true, members: [ChatMember(email: 'owner@example.com', name: 'Owner', uid: 'owner-uid', role: 'owner'), ChatMember(email: 'member@example.com', name: 'Member')]);
    expect(channel.includesIdentity(uid: 'member-uid', email: 'MEMBER@example.com'), isTrue);
    expect(channel.isGroup, isTrue);
    expect(channel.creatorUid, 'owner-uid');
    expect(channel.members, hasLength(2));
    expect(channel.members.last.email, 'member@example.com');
  });
}
