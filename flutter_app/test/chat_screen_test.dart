import 'dart:async';

import 'package:beta_app/screens/chat_repository.dart';
import 'package:beta_app/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeChatRepository implements ChatRepository {
  final channels = StreamController<List<ChatChannel>>();
  final messages = StreamController<List<ChatMessage>>();
  final sent = <String>[];
  Object? channelError;

  @override
  Stream<List<ChatChannel>> watchChannels({required String uid, required String email}) {
    if (channelError case final error?) return Stream<List<ChatChannel>>.error(error);
    return channels.stream.map((value) => filterChannelsForIdentity(value, uid: uid, email: email));
  }

  @override
  Stream<List<ChatMessage>> watchMessages({required String uid, required String channelId}) => messages.stream;

  @override
  Future<void> sendText({required String uid, required String email, required String channelId, required String text}) async {
    if (text.trim().isEmpty) throw ArgumentError('blank');
    sent.add('$uid|$email|$channelId|${text.trim()}');
  }

  Future<void> close() async {
    await channels.close();
    await messages.close();
  }
}

void main() {
  const channelOne = ChatChannel(id: 'room-a', name: 'Room A', memberEmails: ['ALICE@example.com']);
  const channelTwo = ChatChannel(id: 'room-b', name: 'Room B', memberEmails: ['bob@example.com']);

  test('filters channel membership using generic UID and normalized email', () {
    final result = filterChannelsForIdentity([channelOne, channelTwo], uid: 'uid-alice', email: 'alice@EXAMPLE.com');
    expect(result.map((channel) => channel.id), ['room-a']);
    expect(filterChannelsForIdentity([channelOne], uid: '', email: 'alice@example.com'), isEmpty);
    expect(filterChannelsForIdentity([const ChatChannel(id: 'uid-room', name: 'UID room', memberUids: ['user-2'])], uid: 'user-2', email: ''), hasLength(1));
  });

  testWidgets('shows live member channels, streams messages, and sends text', (tester) async {
    final repo = FakeChatRepository();
    await tester.pumpWidget(MaterialApp(home: ChatScreen(repository: repo, identity: const ChatIdentity(uid: 'auth-user-82', email: 'alice@example.com'))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.channels.add([channelOne, channelTwo]);
    await tester.pump();
    expect(find.text('Room A'), findsOneWidget);
    expect(find.text('Room B'), findsNothing);
    await tester.tap(find.text('Room A'));
    await tester.pump();
    repo.messages.add(const [ChatMessage(id: 'message-1', senderName: 'Bob', senderEmail: 'bob@example.com', text: 'Hi there', timestamp: 1)]);
    await tester.pump();
    expect(find.text('Hi there'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    final sendButton = tester.widget<IconButton>(find.byKey(const ValueKey('chat-send-text')));
    expect(sendButton.onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  reply  ');
    await tester.pump();
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('chat-send-text'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('chat-send-text')));
    await tester.pump();
    expect(repo.sent, ['auth-user-82|alice@example.com|room-a|reply']);
    await tester.pumpWidget(const SizedBox.shrink());
    await repo.close();
  });

  testWidgets('reports channel-stream errors and supports retry affordance', (tester) async {
    final repo = FakeChatRepository()..channelError = StateError('offline fake');
    await tester.pumpWidget(MaterialApp(home: ChatScreen(repository: repo, identity: const ChatIdentity(uid: 'generic-uid', email: 'anyone@example.com'))));
    await tester.pump();
    expect(find.textContaining('offline fake'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await repo.close();
  });
}
