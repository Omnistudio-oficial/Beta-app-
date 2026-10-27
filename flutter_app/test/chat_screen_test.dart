import 'dart:async';

import 'package:beta_app/screens/chat_attachment.dart';
import 'package:beta_app/screens/chat_drafts.dart';
import 'package:beta_app/screens/chat_repository.dart';
import 'package:beta_app/screens/chat_screen.dart';
import 'package:beta_app/screens/chat_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeChatRepository implements ChatRepository {
  // Broadcast + synchronous delivery keeps this fake independent of the
  // asynchronous single-subscription buffering used by the Firebase streams.
  final channels = StreamController<List<ChatChannel>>.broadcast(sync: true);
  List<ChatChannel> latestChannels = const [];
  final messages = StreamController<List<ChatMessage>>.broadcast(sync: true);
  final sent = <String>[];
  Object? channelError;
  Object? sendError;

  @override
  Stream<List<ChatChannel>> watchChannels({required String uid, required String email}) {
    if (channelError case final error?) return Stream<List<ChatChannel>>.error(error);
    return Stream<List<ChatChannel>>.multi((controller) {
      controller.add(filterChannelsForIdentity(latestChannels, uid: uid, email: email));
      final subscription = channels.stream.listen((value) {
        latestChannels = value;
        controller.add(filterChannelsForIdentity(value, uid: uid, email: email));
      });
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Stream<List<ChatMessage>> watchMessages({required String uid, required String channelId}) => messages.stream;

  @override
  Future<void> sendAttachment({required String uid, required String email, required String channelId, required ChatAttachment attachment, required String caption}) async => sent.add('media|$uid|$channelId|${attachment.name}|$caption');

  @override
  Future<void> toggleReaction({required String uid, required String channelId, required String messageId, required String emoji}) async {
    sent.add('reaction|$channelId|$messageId|$emoji');
  }

  @override
  Future<void> sendText({required String uid, required String email, required String channelId, required String text}) async {
    if (text.trim().isEmpty) throw ArgumentError('blank');
    if (sendError case final error?) throw error;
    sent.add('$uid|$email|$channelId|${text.trim()}');
  }

  @override
  Future<void> createGroup({required String uid, required String email, required String name, required String description, required List<String> memberEmails}) async {
    sent.add('create-group|$uid|${name.trim()}|${memberEmails.join(',')}');
  }
  @override
  Future<void> updateGroupInfo({required String uid, required String channelId, required String name, required String description}) async => sent.add('group-info|$channelId|$name|$description');
  @override
  Future<void> addGroupMember({required String uid, required String channelId, required String memberEmail}) async => sent.add('group-add|$channelId|$memberEmail');
  @override
  Future<void> removeGroupMember({required String uid, required String channelId, required String memberEmail}) async => sent.add('group-remove|$channelId|$memberEmail');
  @override
  Future<void> updateGroupMemberPermissions({required String uid, required String channelId, required String memberEmail, required bool canSendMessages, required bool canSendMedia}) async => sent.add('group-permission|$channelId|$memberEmail|$canSendMessages|$canSendMedia');
  @override
  Future<void> leaveGroup({required String uid, required String channelId}) async => sent.add('group-leave|$channelId');

  Future<void> close() async {
    await channels.close();
    await messages.close();
  }
}

class MemoryChatDraftStorage implements ChatDraftStorage {
  final values = <String, String>{};
  String _key(String uid, String channelId) => '$uid::$channelId';

  @override
  Future<String?> read({required String uid, required String channelId}) async => values[_key(uid, channelId)];

  @override
  Future<void> write({required String uid, required String channelId, required String text}) async {
    final key = _key(uid, channelId);
    if (text.isEmpty) {
      values.remove(key);
    } else {
      values[key] = text;
    }
  }

  @override
  Future<void> clear({required String uid, required String channelId}) async => values.remove(_key(uid, channelId));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  const channelOne = ChatChannel(id: 'room-a', name: 'Room A', memberEmails: ['ALICE@example.com']);
  const channelTwo = ChatChannel(id: 'room-b', name: 'Room B', memberEmails: ['bob@example.com']);

  Future<void> openScreen(FakeChatRepository repo, MemoryChatDraftStorage drafts, WidgetTester tester, {List<ChatChannel>? visibleChannels}) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(
      repository: repo,
      draftStorage: drafts,
      identity: const ChatIdentity(uid: 'alice-uid', email: 'alice@example.com'),
    )));
    repo.channels.add(visibleChannels ?? [channelOne, channelTwo]);
    await tester.pump();
  }

  Future<void> openRoom(WidgetTester tester, FakeChatRepository repo, String roomName) async {
    await tester.tap(find.text(roomName));
    await tester.pump();
    repo.messages.add(const []);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('displays localized message date and time but hides zero or invalid timestamps', (tester) async {
    final repo = FakeChatRepository();
    try {
      await tester.pumpWidget(MaterialApp(home: ChatScreen(
        repository: repo,
        identity: const ChatIdentity(uid: 'alice-uid', email: 'alice@example.com'),
      )));
      repo.channels.add([channelOne]);
      await tester.pump();
      await tester.tap(find.text('Room A'));
      await tester.pump();

      const validTimestamp = 1704207840000; // 2024-01-02 15:04:00 UTC
      repo.messages.add(const [
        ChatMessage(id: 'valid-time', senderName: 'Bob', senderEmail: 'bob@example.com', text: 'Timed', timestamp: validTimestamp),
        ChatMessage(id: 'zero-time', senderName: 'Bob', senderEmail: 'bob@example.com', text: 'Unstamped', timestamp: 0),
        ChatMessage(id: 'negative-time', senderName: 'Bob', senderEmail: 'bob@example.com', text: 'Invalid', timestamp: -1),
        ChatMessage(id: 'overflow-time', senderName: 'Bob', senderEmail: 'bob@example.com', text: 'Overflow', timestamp: 0x7fffffffffffffff),
      ]);
      await tester.pump();

      final messageContext = tester.element(find.text('Timed'));
      final localizations = MaterialLocalizations.of(messageContext);
      final localDateTime = DateTime.fromMillisecondsSinceEpoch(validTimestamp).toLocal();
      final expected = '${localizations.formatFullDate(localDateTime)} · ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(localDateTime), alwaysUse24HourFormat: MediaQuery.of(messageContext).alwaysUse24HourFormat)}';
      expect(find.text(expected), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-message-time-valid-time')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-message-time-zero-time')), findsNothing);
      expect(find.byKey(const ValueKey('chat-message-time-negative-time')), findsNothing);
      expect(find.byKey(const ValueKey('chat-message-time-overflow-time')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await repo.close();
    }
  });

  const searchMessages = <ChatMessage>[
    ChatMessage(id: '1', senderName: 'Maya', senderEmail: 'maya@example.com', text: 'Bring the blue notebook', timestamp: 1),
    ChatMessage(id: '2', senderName: 'Leo', senderEmail: 'leo@example.com', text: 'I will be there', timestamp: 2),
  ];

  test('filters local loaded messages by body, sender name or email; blank query restores all', () {
    expect(filterChatMessages(searchMessages, 'BLUE').map((m) => m.id), ['1']);
    expect(filterChatMessages(searchMessages, 'maya').map((m) => m.id), ['1']);
    expect(filterChatMessages(searchMessages, 'LEO@EXAMPLE').map((m) => m.id), ['2']);
    expect(filterChatMessages(searchMessages, '   '), searchMessages);
    expect(filterChatMessages(searchMessages, 'absent'), isEmpty);
  });

  testWidgets('highlights all matching text case-insensitively', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HighlightedChatText('Blue blue', query: 'BLU'))));
    final text = tester.widget<RichText>(find.byType(RichText));
    expect(text.text.toPlainText(), 'Blue blue');
    final matches = <TextSpan>[];
    void visit(InlineSpan span) {
      if (span is TextSpan) {
        if (span.style?.backgroundColor == const Color(0xFFFFE082)) matches.add(span);
        for (final child in span.children ?? const <InlineSpan>[]) { visit(child); }
      }
    }
    visit(text.text);
    expect(matches.map((span) => span.text), ['Blu', 'blu']);
  });

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
        repo.messages.add(const []);
        await tester.pump();
        repo.messages.add(const [ChatMessage(id: 'message-1', senderName: 'Bob', senderEmail: 'bob@example.com', text: 'Hi there', timestamp: 1)]);
        await tester.pump();
        expect(find.text('Hi there'), findsOneWidget);

        // Search is local to the current stream snapshot: no repository method
        // or Firebase operation is invoked when filtering, clearing, or exiting.
        await tester.tap(find.byKey(const ValueKey('chat-search-open')));
        await tester.pump();
        await tester.enterText(find.byKey(const ValueKey('chat-search-field')), 'missing');
        await tester.pump();
        expect(find.text('No se encontraron mensajes.'), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('chat-search-field')), 'BOB');
        await tester.pump();
        expect(find.text('Hi there'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('chat-search-clear')));
        await tester.pump();
        expect(find.text('Hi there'), findsOneWidget);
        await tester.tap(find.byTooltip('Cerrar búsqueda'));
        await tester.pump();
        expect(find.byKey(const ValueKey('chat-search-field')), findsNothing);
        expect(find.byKey(const ValueKey('chat-search-open')), findsOneWidget);

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
        await repo.close();
        print('[chat_screen_test] cleanup complete');
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets('restores a local draft, keeps failed sends, and clears after success', (tester) async {
    final repo = FakeChatRepository();
    final drafts = MemoryChatDraftStorage()..values['alice-uid::room-a'] = 'draft for room A';
    try {
      await openScreen(repo, drafts, tester, visibleChannels: [channelOne]);
      await openRoom(tester, repo, 'Room A');
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'draft for room A');
      repo.sendError = StateError('offline');
      await tester.enterText(find.byType(TextField), 'edited draft for room A');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.byKey(const ValueKey('chat-send-text')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'edited draft for room A');
      expect(drafts.values['alice-uid::room-a'], 'edited draft for room A');

      repo.sendError = null;
      await tester.tap(find.byKey(const ValueKey('chat-send-text')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
      expect(drafts.values.containsKey('alice-uid::room-a'), isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await repo.close();
    }
  });

  test('SharedPreferences draft storage persists per user and chat and clears only its own key', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = SharedPreferencesChatDraftStorage();
    await storage.write(uid: 'user-a', channelId: 'room-1', text: 'draft A1');
    await storage.write(uid: 'user-a', channelId: 'room-2', text: 'draft A2');
    await storage.write(uid: 'user-b', channelId: 'room-1', text: 'draft B1');
    expect(await storage.read(uid: 'user-a', channelId: 'room-1'), 'draft A1');
    expect(await storage.read(uid: 'user-a', channelId: 'room-2'), 'draft A2');
    expect(await storage.read(uid: 'user-b', channelId: 'room-1'), 'draft B1');
    await storage.clear(uid: 'user-a', channelId: 'room-1');
    expect(await storage.read(uid: 'user-a', channelId: 'room-1'), isNull);
    expect(await storage.read(uid: 'user-a', channelId: 'room-2'), 'draft A2');
    expect(await storage.read(uid: 'user-b', channelId: 'room-1'), 'draft B1');
  });

  test('SharedPreferences draft keys escape separators in IDs', () {
    expect(SharedPreferencesChatDraftStorage.keyFor(uid: 'a.b', channelId: 'c'), isNot(SharedPreferencesChatDraftStorage.keyFor(uid: 'a', channelId: 'b.c')));
  });

  testWidgets('copies the selected message text from its accessible actions menu', (tester) async {
    final repo = FakeChatRepository();
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    try {
      await tester.pumpWidget(MaterialApp(home: ChatScreen(
        repository: repo,
        identity: const ChatIdentity(uid: 'alice-uid', email: 'alice@example.com'),
      )));
      repo.channels.add([channelOne]);
      await tester.pump();
      await tester.tap(find.text('Room A'));
      await tester.pump();
      repo.messages.add(const [
        ChatMessage(id: 'copy-target', senderName: 'Bob', senderEmail: 'bob@example.com', text: '  Keep this exact text  ', timestamp: 1),
      ]);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('chat-message-copy-copy-target')));
      await tester.pump();

      expect(copiedText, '  Keep this exact text  ');
      expect(find.text('Mensaje copiado'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
      await repo.close();
    }
  });

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
      await repo.close();
    }
  });

  testWidgets('shows counts and toggles a reaction in the open message', (tester) async {
  final repo = FakeChatRepository();
  final drafts = MemoryChatDraftStorage();
  await openScreen(repo, drafts, tester);
  await openRoom(tester, repo, 'Room A');
  repo.messages.add(const [ChatMessage(id: 'react-1', senderName: 'Bob', senderEmail: 'bob@example.com', text: 'Hola', timestamp: 1, reactions: '👍,👍,❤️')]);
  await tester.pump();
  expect(find.text('👍 2'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('chat-reaction-react-1-👍')));
  await tester.pumpAndSettle();
  expect(repo.sent, contains('reaction|room-a|react-1|👍'));
  await repo.close();
});



testWidgets('shows on-device translation controls and manual action', (tester) async {
  final repo = FakeChatRepository();
  final drafts = MemoryChatDraftStorage();
  await openScreen(repo, drafts, tester);
  await openRoom(tester, repo, 'Room A');
  repo.messages.add(const [ChatMessage(id: 'translate-1', senderName: 'Bob', senderEmail: 'bob@example.com', text: 'Hello there', timestamp: 1)]);
  await tester.pump();
  expect(find.byKey(const ValueKey('chat-translation-target')), findsOneWidget);
  expect(find.byKey(const ValueKey('chat-auto-translate')), findsOneWidget);
  expect(find.byKey(const ValueKey('chat-translate-translate-1')), findsOneWidget);
  await repo.close();
});



  testWidgets('creates a group from the chat list with provided member emails', (tester) async {
    final repo = FakeChatRepository();
    final drafts = MemoryChatDraftStorage();
    await openScreen(repo, drafts, tester);
    await tester.tap(find.byKey(const ValueKey('chat-create-group')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('create-group-name')), 'Study group');
    await tester.enterText(find.byKey(const ValueKey('create-group-members')), 'bob@example.com, cara@example.com');
    await tester.tap(find.byKey(const ValueKey('create-group-submit')));
    await tester.pumpAndSettle();
    expect(repo.sent, contains('create-group|alice-uid|Study group|bob@example.com,cara@example.com'));
    await repo.close();
  });

  testWidgets('opens group management for an owned group and shows member permissions', (tester) async {
    final repo = FakeChatRepository();
    final drafts = MemoryChatDraftStorage();
    const group = ChatChannel(id: 'group-a', name: 'Study group', creatorEmail: 'alice@example.com', creatorUid: 'alice-uid', isGroup: true, members: [ChatMember(email: 'alice@example.com', name: 'Alice', uid: 'alice-uid', role: 'owner'), ChatMember(email: 'bob@example.com', name: 'Bob')]);
    await openScreen(repo, drafts, tester, visibleChannels: [group]);
    await openRoom(tester, repo, 'Study group');
    await tester.tap(find.byKey(const ValueKey('chat-manage-group')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('manage-chat-group-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-group-member-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('permission-messages-bob@example.com')), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    await repo.close();
  });
}
