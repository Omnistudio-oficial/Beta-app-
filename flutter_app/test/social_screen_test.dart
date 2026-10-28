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
  final List<SocialProfile> lookups = [];
  final Map<String, String> statuses = {};
  final List<SocialProfile> followCalls = [];
  List<SocialFollowRequest> requests = const [];
  final List<String> acceptedRequests = [];
  final List<String> rejectedRequests = [];
  @override
  String get currentUid => 'uid';
  @override
  Stream<List<SocialPost>> watchPublicFeed() => publicFeed.stream;
  @override
  Future<bool> canInteract(SocialPost post) async => true;
  @override
  Future<SocialProfile?> findProfileByExactHandle(String handle) async {
    final normalized = handle.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
    // The fake directory includes only explicitly discoverable exact handles.
    for (final profile in lookups) {
      if (profile.username.toLowerCase() == normalized) return profile;
    }
    return null;
  }
  @override
  Future<String?> followStatus(String targetUid) async => statuses[targetUid];
  @override
  Future<String> toggleFollow(SocialProfile target) async {
    followCalls.add(target);
    final next = statuses[target.uid] == 'pending' || statuses[target.uid] == 'accepted' ? '' : target.isPrivate ? 'pending' : 'accepted';
    if (next.isEmpty) { statuses.remove(target.uid); } else { statuses[target.uid] = next; }
    return next;
  }
  @override
  Future<List<SocialFollowRequest>> pendingFollowRequests() async => requests.where((r) => !acceptedRequests.contains(r.uid) && !rejectedRequests.contains(r.uid)).toList();
  @override
  Future<void> acceptFollowRequest(String requesterUid) async { acceptedRequests.add(requesterUid); }
  @override
  Future<void> rejectFollowRequest(String requesterUid) async { rejectedRequests.add(requesterUid); }
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
    await tester.pump(const Duration(milliseconds: 1)); // Allow canInteract to resolve; other streams keep loading.
    await tester.pump();
    expect(find.text('Public Author'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Me gusta'));
    await tester.pump();
    expect(service.likeChanges, [true]);
    await tester.enterText(find.byKey(const ValueKey('social-comment')), 'A comment');
    await tester.tap(find.byIcon(Icons.send).first);
    await tester.pump();
    expect(service.comments, ['A comment']);
    await tester.enterText(find.byKey(const ValueKey('social-caption')), 'Hola mundo');
    final publishButton = find.text('Publicar');
    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.ensureVisible(publishButton);
    await tester.pumpAndSettle();
    await tester.tap(publishButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(service.captions, ['Hola mundo']);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('social-caption'))).controller!.text, isEmpty);
    expect(find.text('Publicación sincronizada con tu cuenta'), findsOneWidget);
    expect(find.textContaining('permanecen privadas por defecto'), findsOneWidget);
  });

  testWidgets('exact opt-in directory lookup does not enumerate or reveal unlisted handles', (tester) async {
    final service = _FakeSocialService();
    service.lookups.add(const SocialProfile(uid: 'private-uid', username: 'privateuser', displayName: 'Private person', visibility: 'private'));
    await tester.pumpWidget(MaterialApp(home: SocialScreen(service: service)));
    await tester.pump();
    expect(find.text('Private person'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('social-exact-handle')), 'private');
    await tester.tap(find.byTooltip('Buscar handle exacto'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('No se encontró una cuenta para ese handle exacto.'), findsOneWidget);
    expect(find.text('Private person'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('social-exact-handle')), '@privateuser');
    await tester.tap(find.byTooltip('Buscar handle exacto'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('Private person'), findsOneWidget);
    expect(service.followCalls, isEmpty, reason: 'Searching or selecting a profile must never follow without a tap.');
  });

  testWidgets('public follow is accepted immediately and can be undone from displayed public feed', (tester) async {
    final service = _FakeSocialService();
    await tester.pumpWidget(MaterialApp(home: SocialScreen(service: service)));
    await tester.pump();
    service.publicFeed.add(const [SocialPost(id: 'pub', ownerUid: 'public-uid', caption: 'Public post', createdAt: 10, username: 'publicuser', displayName: 'Public Author')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('Seguir'), findsOneWidget);
    expect(service.followCalls, isEmpty);
    await tester.tap(find.text('Seguir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(service.statuses['public-uid'], 'accepted');
    expect(find.text('Dejar de seguir'), findsOneWidget);
    await tester.tap(find.text('Dejar de seguir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(service.statuses.containsKey('public-uid'), isFalse);
  });

  testWidgets('private follow requests remain pending until target decision and can be cancelled', (tester) async {
    final service = _FakeSocialService()..lookups.add(const SocialProfile(uid: 'private-uid', username: 'locked', displayName: 'Locked profile', visibility: 'private'));
    await tester.pumpWidget(MaterialApp(home: SocialScreen(service: service)));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('social-exact-handle')), 'locked');
    await tester.tap(find.byTooltip('Buscar handle exacto'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(service.followCalls, isEmpty);
    await tester.tap(find.text('Seguir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(service.statuses['private-uid'], 'pending');
    expect(find.text('Cancelar solicitud'), findsOneWidget);
    await tester.tap(find.text('Cancelar solicitud'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(service.statuses.containsKey('private-uid'), isFalse);
  });

  testWidgets('only the target can act on pending follow requests; accept and reject clear the visible queue', (tester) async {
    final service = _FakeSocialService()..requests = const [
      SocialFollowRequest(uid: 'requester-a', username: 'alice', displayName: 'Alice'),
      SocialFollowRequest(uid: 'requester-b', username: 'bob', displayName: 'Bob'),
    ];
    await tester.pumpWidget(MaterialApp(home: SocialScreen(service: service)));
    await tester.pump();
    await tester.tap(find.text('Revisar solicitudes de seguimiento'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    await tester.tap(find.byTooltip('Aceptar solicitud alice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(service.acceptedRequests, ['requester-a']);
    await tester.tap(find.byTooltip('Rechazar solicitud bob'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(service.rejectedRequests, ['requester-b']);
    expect(find.text('No tienes solicitudes pendientes.'), findsOneWidget);
  });
}
