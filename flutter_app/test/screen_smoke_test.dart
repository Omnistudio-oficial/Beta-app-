import 'package:beta_app/screens/ai_screen.dart';
import 'package:beta_app/screens/converter_screen.dart';
import 'package:beta_app/screens/docs_screen.dart';
import 'package:beta_app/screens/maps_screen.dart';
import 'package:beta_app/screens/social_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('migration screens build with their intended titles', (tester) async {
    final screens = <Widget>[
      const AIScreen(),
      const ConverterScreen(),
      const DocsScreen(),
      const MapsScreen(),
      const SocialScreen(),
    ];
    final titles = ['AI Assistant', 'Converter', 'Docs', 'Maps', 'Social'];

    for (var index = 0; index < screens.length; index++) {
      await tester.pumpWidget(MaterialApp(home: screens[index]));
      expect(find.text(titles[index]), findsOneWidget);
    }
  });
}
