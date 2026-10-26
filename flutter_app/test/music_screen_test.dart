import 'package:beta_app/screens/music_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('selects a track and saves it to local favorites', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MusicScreen()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('track-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('track-2')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('selected-track')),
        matching: find.text('Velvet Horizon'),
      ),
      findsOneWidget,
    );
    expect(find.text('La reproducción aún no está conectada.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('selected-track-favorite')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('music_favorite_ids'), ['2']);
  });

  testWidgets('filters to favorites and restores the full library', (tester) async {
    SharedPreferences.setMockInitialValues({'music_favorite_ids': ['3']});
    await tester.pumpWidget(const MaterialApp(home: MusicScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('toggle-favorites-filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('track-3')), findsOneWidget);
    expect(find.byKey(const Key('track-1')), findsNothing);

    await tester.tap(find.byKey(const Key('toggle-favorites-filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('track-1')), findsOneWidget);
  });
}
