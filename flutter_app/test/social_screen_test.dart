import 'dart:async';

import 'package:beta_app/screens/social_screen.dart';
import 'package:beta_app/social/social_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSocialService implements SocialService {
  final controller = StreamController<List<SocialPost>>.broadcast();
  final List<String> captions = [];
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
    await tester.pumpWidget(MaterialApp(home: SocialScreen(service: service)));
    await tester.pump();
    expect(find.textContaining('permanecen privadas por defecto'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Hola mundo');
    await tester.tap(find.text('Publicar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(service.captions, ['Hola mundo']);
    expect(find.text('Hola mundo'), findsOneWidget);
    expect(find.textContaining('permanecen privadas por defecto'), findsOneWidget);
  });
}
