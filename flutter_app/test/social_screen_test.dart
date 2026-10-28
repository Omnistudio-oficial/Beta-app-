import 'dart:async';

import 'package:beta_app/screens/social_screen.dart';
import 'package:beta_app/social/social_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSocialService implements SocialService {
  final controller = StreamController<List<SocialPost>>.broadcast();
  final publicFeed = StreamController<List<SocialPost>>.broadcast();
  final likeChanges = <bool>[];
  final comments = <String>[];
  final List<String> captions = [];
  @override
  String get currentUid => 'uid';
  @override
  Stream<List<SocialPost>> watchPublicFeed() => publicFeed.stream;
  @override
  Future<bool> canInteract(SocialPost post) async => true;
  @override
  Stream<Set<String>> watchLikes(SocialPost post) => Stream.value(const {});
  @override
  Stream<List<SocialComment>> watchComments(SocialPost post) => Stream.value(const []);
  @override
  Future<void> toggleLike(SocialPost post, bool liked) async { likeChanges.add(liked); }
  @override
  Future<void> addComment(SocialPost post, String text) async { comments.add(text); }
  @override
  Stream<List<SocialPost>> watchMyPosts() => controller.stream;
  @override
  Future<void> createPost({required String caption, required List<SocialMediaFile> media}) async {
    captions.add(caption);
    controller.add([SocialPost(id: 'p1', ownerUid: 'uid', caption: caption, createdAt: 1)]);
  }
  @override
  Future<String> signedMediaUrl(SocialPost post, SocialMediaItem media) async => 'https://example.invalid/private';
}

void main() {
  testWidgets('discloses private-by-default and synchronizes text post via service', (tester) async {
    final service = _FakeSocialService();
    addTearDown(service.controller.close);
    addTearDown(service.publicFeed.close);
    await tester.pumpWidget(MaterialApp(home: SocialScreen(service: service)));
    await tester.pump();
    expect(find.textContaining('permanecen privadas por defecto'), findsOneWidget);
    service.publicFeed.add(const [SocialPost(id: 'pub', ownerUid: 'other', caption: 'Public post', createdAt: 10, username: 'publicuser', displayName: 'Public Author')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1)); // Let canInteract resolve; other screen streams intentionally keep loading.
    await tester.pump();
    expect(find.text('Public Author'), findsOneWidget);
    await tester.tap(find.byTooltip('Me gusta'));
    await tester.pump();
    expect(service.likeChanges, [true]);
    await tester.enterText(find.byKey(const ValueKey('social-comment')), 'A comment');
    await tester.tap(find.byIcon(Icons.send).first);
    await tester.pump();
    expect(service.comments, ['A comment']);
    await tester.enterText(find.byKey(const ValueKey('social-caption')), 'Hola mundo');
    await tester.tap(find.text('Publicar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(service.captions, ['Hola mundo']);
    expect(find.text('Hola mundo'), findsOneWidget);
    expect(find.textContaining('permanecen privadas por defecto'), findsOneWidget);
  });
}
