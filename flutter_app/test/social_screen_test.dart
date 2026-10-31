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
  String visibility = 'private';
  final List<String> visibilityUpdates = [];
  bool failVisibilityWrite = false;
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
  Future<String> currentVisibility() async => visibility;
  @override
  Future<void> updateCurrentVisibility(String value) async {
    visibilityUpdates.add(value);
    if (failVisibilityWrite) throw StateError('permission denied');
    visibility = value;
  }
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
  testWidgets('own-account visibility switch persists public/private choice', (tester) async {
    final service = _FakeSocialService();
    await tester.pumpWidget(MaterialApp(home: SocialScreen(service: service)));
    await tester.pump();
    expect(service.visibility, 'private');
    final privacySwitch = find.byKey(const ValueKey('social-own-visibility-switch'));
    expect(tester.widget<SwitchListTile>(privacySwitch).value, isFalse);
    await tester.tap(privacySwitch);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(service.visibilityUpdates, ['public']);
    expect(find.text('Cuenta pública'), findsOneWidget);
    await tester.tap(privacySwitch);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(service.visibilityUpdates, ['public', 'private']);
    expect(find.text('Cuenta privada'), findsOneWidget);
  });

  testWidgets('failed visibility update restores stored private setting', (tester) async {
    final service = _FakeSocialService()..failVisibilityWrite = true;
    await tester.pumpWidget(MaterialApp(home: SocialScreen(service: service)));
    await tester.pump();
    final privacySwitch = find.byKey(const ValueKey('social-own-visibility-switch'));
    await tester.tap(privacySwitch);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.widget<SwitchListTile>(privacySwitch).value, isFalse);
    expect(find.text('No se pudo guardar la privacidad. No se cambió la configuración.'), findsOneWidget);
  });

  test('visibility defaults fail-closed and public indexes only public posts', () {
    expect(SocialVisibilityPolicy.normalize(null), 'private');
    expect(SocialVisibilityPolicy.normalize('unknown'), 'private');
    expect(SocialVisibilityPolicy.shouldIndexPost('private'), isFalse);
    expect(SocialVisibilityPolicy.shouldIndexPost('public'), isTrue);
    const privatePost = <String, Object?>{'id': 'p', 'caption': 'private'};
    expect(SocialVisibilityPolicy.publicPostEntry('private', privatePost), isNull);
    expect(SocialVisibilityPolicy.publicPostEntry('public', privatePost), privatePost);
    expect(SocialVisibilityPolicy.publicFeedKey('owner', 'post'), 'owner_post');
    const posts = <String, Map<String, Object?>>{
      'one': {'id': 'one', 'caption': 'first'},
      'two': {'id': 'two', 'caption': 'second'},
    };
    expect(SocialVisibilityPolicy.publicPostIndexChanges('owner', posts, 'private'), {
      'publicFeed/owner_one': null,
      'publicFeed/owner_two': null,
    });
    expect(SocialVisibilityPolicy.publicPostIndexChanges('owner', posts, 'public'), {
      'publicFeed/owner_one': posts['one'],
      'publicFeed/owner_two': posts['two'],
    });
  });

  testWidgets('camera preview is opened only by an explicit Social tap', (tester) async {
    final service = _FakeSocialService();
    await tester.pumpWidget(MaterialApp(home: SocialScreen(service: service)));
    await tester.pump();
    final openCamera = find.byKey(const ValueKey('social-open-camera'));
    await tester.ensureVisible(openCamera);
    await tester.tap(openCamera);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Vista previa de cámara'), findsOneWidget);
    expect(find.byKey(const ValueKey('social-filter-dog-ears')), findsOneWidget);
    expect(find.byKey(const ValueKey('social-filter-glasses')), findsOneWidget);
    expect(find.byKey(const ValueKey('social-filter-crown')), findsOneWidget);
  });


  testWidgets('discloses private-by-default and synchronizes text post via service', (tester) async {
    final service = _FakeSocialService();
    addTearDown(service.controller.close);
    addTearDown(service.publicFeed.close);
    await tester.pumpWidget(MaterialApp(home: SocialScreen(service: service)));
    await tester.pump();
    expect(service.visibility, 'private');
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('social-own-visibility-switch'))).value, isFalse);
    expect(find.textContaining('privada por defecto'), findsOneWidget);
    expect(find.text('Cuenta privada'), findsOneWidget);
    service.publicFeed.add(const [SocialPost(id: 'pub', ownerUid: 'other', caption: 'Public post', createdAt: 10, username: 'publicuser', displayName: 'Public Author')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1)); // Allow canInteract to resolve; other streams keep loading.
    await tester.pump();
    expect(find.text('Public Author'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Me gusta'));
    await tester.pump();
    expect(service.likeChanges, [true]);
    final commentField = find.byKey(const ValueKey('social-comment'));
    await tester.ensureVisible(commentField);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(commentField, 'A comment');
    final sendComment = find.byIcon(Icons.send).first;
    await tester.ensureVisible(sendComment);
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.getRect(sendComment).overlaps(tester.getRect(find.byType(ListView).first)), isTrue);
    await tester.tap(sendComment);
    await tester.pump();
    expect(service.comments, ['A comment']);
    await tester.enterText(find.byKey(const ValueKey('social-caption')), 'Hola mundo');
    final publishButton = find.text('Publicar');
    await tester.dragUntilVisible(
      publishButton,
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.ensureVisible(publishButton);
    await tester.pump();
    await tester.tap(publishButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(service.captions, ['Hola mundo']);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('social-caption'))).controller!.text, isEmpty);
    expect(find.text('Publicación sincronizada con tu cuenta'), findsOneWidget);
    expect(find.textContaining('privada por defecto'), findsOneWidget);
    expect(find.text('Cuenta privada'), findsOneWidget);
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
