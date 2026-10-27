import 'dart:async';

import 'package:beta_app/screens/chat_attachment.dart';
import 'package:beta_app/screens/chat_repository.dart';
import 'package:beta_app/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeChatRepository implements ChatRepository {
  // Broadcast + synchronous delivery keeps this fake independent of the
  // asynchronous single-subscription buffering used by the Firebase streams.
  final channels = StreamController<List<ChatChannel>>.broadcast(sync: true);
  final messages = StreamController<List<ChatMessage>>.broadcast(sync: true);
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
  Future<void> sendAttachment({required String uid, required String email, required String channelId, required ChatAttachment attachment, required String caption}) async => sent.add('media|$uid|$channelId|${attachment.name}|$caption');

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

  testWidgets(
    'shows live member channels, streams messages, and sends text',
    (tester) async {
      final repo = FakeChatRepository();
      try {
        print('[chat_screen_test] mounting chat screen');
        await tester.pumpWidget(MaterialApp(home: ChatScreen(repository: repo, identity: const ChatIdentity(uid: 'auth-user-82', email: 'alice@example.com'))));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        print('[chat_screen_test] emitting channels');
        repo.channels.add([channelOne, channelTwo]);
        await tester.pump();
        expect(find.text('Room A'), findsOneWidget);
        expect(find.text('Room B'), findsNothing);

        print('[chat_screen_test] opening channel and emitting message');
        await tester.tap(find.text('Room A'));
        await tester.pump();
        repo.messages.add(const [ChatMessage(id: 'message-1', senderName: 'Bob', senderEmail: 'bob@example.com', text: 'Hi there', timestamp: 1)]);
        await tester.pump();
        expect(find.text('Hi there'), findsOneWidget);

        print('[chat_screen_test] checking and sending text');
        await tester.enterText(find.byType(TextField), '');
        await tester.pump();
        expect(tester.widget<IconButton>(find.byKey(const ValueKey('chat-send-text'))).onPressed, isNull);
        await tester.enterText(find.byType(TextField), '  reply  ');
        await tester.pump();
        expect(tester.widget<IconButton>(find.byKey(const ValueKey('chat-send-text'))).onPressed, isNotNull);
        await tester.tap(find.byKey(const ValueKey('chat-send-text')));
        await tester.pump();
        expect(repo.sent, ['auth-user-82|alice@example.com|room-a|reply']);
      } finally {
        print('[chat_screen_test] disposing screen and closing fake streams');
        // StreamController.close waits for active listeners to cancel. Dispose
        // the screen first so both StreamBuilder subscriptions are cancelled.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(); // flush StreamBuilder subscription cancellations
        await repo.close().timeout(const Duration(seconds: 5));
        print('[chat_screen_test] cleanup complete');
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets('reports channel-stream errors and supports retry affordance', (tester) async {
    final repo = FakeChatRepository()..channelError = StateError('offline fake');
    try {
      await tester.pumpWidget(MaterialApp(home: ChatScreen(repository: repo, identity: const ChatIdentity(uid: 'generic-uid', email: 'anyone@example.com'))));
      await tester.pump();
      expect(find.textContaining('offline fake'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(); // flush StreamBuilder subscription cancellation
      await repo.close().timeout(const Duration(seconds: 5));
    }
  }, timeout: const Timeout(Duration(seconds: 45)));
}
