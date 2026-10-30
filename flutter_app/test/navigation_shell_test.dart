import 'package:beta_app/app/app_destination.dart';
import 'package:beta_app/app/navigation_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dashboard shortcuts open consolidated modules and bottom navigation returns home', (tester) async {
    final overrides = <AppDestination, Widget>{
      for (final destination in authenticatedDestinations.where((destination) => destination != AppDestination.home))
        destination: Scaffold(body: Center(child: Text('module_${destination.name}'))),
    };
    await tester.pumpWidget(MaterialApp(
      home: NavigationShell(pageOverrides: overrides, displayName: 'Cris', onSignOut: () {}),
    ));

    expect(find.text('Hola, Cris'), findsOneWidget);
    for (final entry in <({Key key, AppDestination destination})>[
      (key: const Key('home_tool_chat'), destination: AppDestination.chat),
      (key: const Key('home_tool_música'), destination: AppDestination.music),
      (key: const Key('home_tool_maps'), destination: AppDestination.maps),
      (key: const Key('home_tool_asistente_ia'), destination: AppDestination.assistant),
      (key: const Key('home_tool_documentos'), destination: AppDestination.docs),
      (key: const Key('home_tool_social'), destination: AppDestination.social),
      (key: const Key('home_tool_convertir'), destination: AppDestination.converter),
      (key: const Key('home_tool_perfil'), destination: AppDestination.profile),
    ]) {
      await tester.ensureVisible(find.byKey(entry.key));
      await tester.tap(find.byKey(entry.key));
      await tester.pumpAndSettle();
      expect(find.text('module_${entry.destination.name}'), findsOneWidget);
      await tester.tap(find.byKey(const Key('navigation_home')));
      await tester.pumpAndSettle();
      expect(find.text('Hola, Cris'), findsOneWidget);
    }
  });

  test('authenticated destination registry contains each implemented route once and excludes auth', () {
    expect(authenticatedDestinations.toSet().length, authenticatedDestinations.length);
    expect(authenticatedDestinations, containsAll(<AppDestination>[
      AppDestination.home,
      AppDestination.chat,
      AppDestination.music,
      AppDestination.maps,
      AppDestination.assistant,
      AppDestination.docs,
      AppDestination.social,
      AppDestination.converter,
      AppDestination.profile,
    ]));
    expect(authenticatedDestinations, isNot(contains('auth')));
  });
}
