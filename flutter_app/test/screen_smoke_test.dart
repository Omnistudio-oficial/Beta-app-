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
      const MapsScreen(),
      SocialScreen(service: _EmptySocialService()),
    ];
    final titles = ['AI Assistant', 'Converter', 'Docs', 'Maps', 'Social'];

    for (var index = 0; index < screens.length; index++) {
      await tester.pumpWidget(MaterialApp(home: screens[index]));
      expect(find.text(titles[index]), findsOneWidget);
    }
  });
}
