import 'dart:io';

import 'package:beta_app/screens/chat_media_actions.dart';
import 'package:beta_app/screens/chat_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('ChatMediaActions', () {
    late Directory temp;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('chat-media-actions-');
    });
    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('downloads only tapped URL into temp and invokes native-share seam', () async {
      Uri? fetched;
      String? sharedName;
      String? sharedMime;
      List<int>? sharedBytes;
      final actions = ChatMediaActions(
        get: (uri) async {
          fetched = uri;
          return http.Response.bytes([1, 2, 3], 200);
        },
        temporaryDirectory: () async => temp,
        share: (path, name, mime) async {
          sharedName = name;
          sharedMime = mime;
          sharedBytes = await File(path).readAsBytes();
        },
      );
      await actions.downloadAndShare(
        url: 'https://files.example.test/presigned/document.pdf',
        fileName: '../../private report.pdf',
        mimeType: 'application/pdf',
      );
      expect(fetched, Uri.parse('https://files.example.test/presigned/document.pdf'));
      expect(sharedName, 'private report.pdf');
      expect(sharedMime, 'application/pdf');
      expect(sharedBytes, [1, 2, 3]);
    });

    test('rejects unsafe URLs, failed responses and oversized/empty files', () async {
      var getCalls = 0;
      var shareCalls = 0;
      ChatMediaActions actions({required http.Response response}) => ChatMediaActions(
            get: (_) async { getCalls++; return response; },
            temporaryDirectory: () async => temp,
            share: (_, __, ___) async { shareCalls++; },
          );
      await expectLater(
        actions(response: http.Response.bytes([1], 200)).downloadAndShare(url: 'file:///etc/passwd', fileName: 'x', mimeType: ''),
        throwsFormatException,
      );
      await expectLater(
        actions(response: http.Response.bytes([], 200)).downloadAndShare(url: 'https://files.example.test/a', fileName: 'x', mimeType: ''),
        throwsFormatException,
      );
      await expectLater(
        actions(response: http.Response.bytes([1], 403)).downloadAndShare(url: 'https://files.example.test/a', fileName: 'x', mimeType: ''),
        throwsA(isA<HttpException>()),
      );
      expect(getCalls, 2);
      expect(shareCalls, 0);
    });
  });

  testWidgets('video playback starts only after tap and controller is disposed', (tester) async {
    final factory = _FakeVideoFactory();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatVideoPlayer(
      source: Uri.parse('https://files.example.test/video.mp4'),
      thumbnailUrl: null,
      controllerFactory: factory,
    ))));
    expect(factory.created, 0);
    expect(find.byKey(const ValueKey('chat-video-preview')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-video-preview')));
    await tester.pumpAndSettle();
    expect(factory.created, 1);
    expect(factory.controller!.initializeCalls, 1);
    expect(factory.controller!.playCalls, 1);
    expect(find.byKey(const ValueKey('chat-video-play-pause')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(factory.controller!.disposed, isTrue);
    expect(factory.controller!.listeners, isEmpty);
  });
}

class _FakeVideoFactory implements ChatVideoControllerFactory {
  int created = 0;
  _FakeVideoController? controller;
  @override
  ChatVideoController create(Uri source) {
    created++;
    return controller = _FakeVideoController();
  }
}

class _FakeVideoController implements ChatVideoController {
  final Set<VoidCallback> listeners = {};
  int initializeCalls = 0;
  int playCalls = 0;
  bool disposed = false;
  bool playing = false;
  bool initialized = false;
  @override bool get isInitialized => initialized;
  @override bool get isPlaying => playing;
  @override double get aspectRatio => 16 / 9;
  @override String? get error => null;
  @override Widget buildVideo() => const ColoredBox(color: Colors.black);
  @override Future<void> initialize() async { initializeCalls++; initialized = true; }
  @override Future<void> play() async { playCalls++; playing = true; }
  @override Future<void> pause() async { playing = false; }
  @override void addListener(VoidCallback listener) => listeners.add(listener);
  @override void removeListener(VoidCallback listener) => listeners.remove(listener);
  @override Future<void> dispose() async { disposed = true; initialized = false; }
}
