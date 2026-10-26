import 'package:beta_app/screens/social_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('creates a local post and persists it after screen reload', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SocialScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('social-post-input')), 'Mi primera publicación');
    await tester.pump();
    await tester.tap(find.byKey(const Key('social-create-post')));
    await tester.pumpAndSettle();

    expect(find.text('Mi primera publicación'), findsOneWidget);
    expect(find.textContaining('no se comparten ni sincronizan'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('social_local_posts'), hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MaterialApp(home: SocialScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Mi primera publicación'), findsOneWidget);
  });

  testWidgets('deletes a local post and saves the empty list', (tester) async {
    SharedPreferences.setMockInitialValues({
      'social_local_posts': ['{"id":"p1","text":"Publicación guardada"}'],
    });
    await tester.pumpWidget(const MaterialApp(home: SocialScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete-post-p1')));
    await tester.pumpAndSettle();

    expect(find.text('Aún no tienes publicaciones locales.'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('social_local_posts'), isEmpty);
  });

  testWidgets('does not enable empty post submission', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SocialScreen()));
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(find.byKey(const Key('social-create-post')));
    expect(button.onPressed, isNull);
  });
}
