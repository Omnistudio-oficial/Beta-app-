import 'package:beta_app/screens/ai_screen.dart';
import 'package:beta_app/screens/converter_screen.dart';
import 'package:beta_app/screens/docs_screen.dart';
import 'package:beta_app/screens/maps_screen.dart';
import 'package:beta_app/screens/social_screen.dart';
import 'package:beta_app/social/social_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

class _EmptySocialService implements SocialService {
  @override
  String get currentUid => 'uid';
  @override
  Stream<List<SocialPost>> watchPublicFeed() => Stream.value(const []);
  @override
  Future<bool> canInteract(SocialPost post) async => true;
  @override
  Future<SocialProfile?> findProfileByExactHandle(String handle) async => null;
  @override
  Future<String?> followStatus(String targetUid) async => null;
  @override
  Future<String> toggleFollow(SocialProfile target) async => target.isPrivate ? 'pending' : 'accepted';
  @override
  Future<List<SocialFollowRequest>> pendingFollowRequests() async => const [];
  @override
  Future<void> acceptFollowRequest(String requesterUid) async {}
  @override
  Future<void> rejectFollowRequest(String requesterUid) async {}
  @override
  Stream<Set<String>> watchLikes(SocialPost post) => Stream.value(const {});
  @override
  Stream<List<SocialComment>> watchComments(SocialPost post) => Stream.value(const []);
  @override
  Future<void> toggleLike(SocialPost post, bool liked) async {}
  @override
  Future<void> addComment(SocialPost post, String text) async {}
  @override
  Stream<List<SocialPost>> watchMyPosts() => Stream.value(const []);
  @override
  Future<void> createPost({required String caption, required List<SocialMediaFile> media}) async {}
  @override
  Future<String> signedMediaUrl(SocialPost post, SocialMediaItem media) async => '';
}

void main() {
  testWidgets('migration screens build with their intended titles', (tester) async {
    final screens = <Widget>[
      const AIScreen(),
      const ConverterScreen(),
      const DocsScreen(),
      const MapsScreen(showMap: false, autoLocate: false),
      SocialScreen(service: _EmptySocialService()),
    ];
    final titles = ['AI Assistant', 'Converter', 'Docs', 'Maps', 'Social'];

    for (var index = 0; index < screens.length; index++) {
      await tester.pumpWidget(MaterialApp(home: screens[index]));
      expect(find.text(titles[index]), findsOneWidget);
    }
  });
}
