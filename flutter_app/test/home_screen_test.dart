import 'package:beta_app/app/app_destination.dart';
import 'package:beta_app/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home greets the user and opens a selected module', (tester) async {
    AppDestination? selectedIndex;
    var signedOut = false;
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        displayName: 'Cris',
        onNavigate: (destination) => selectedIndex = destination,
        onSignOut: () => signedOut = true,
      ),
    ));

    expect(find.text('Hola, Cris'), findsOneWidget);
    expect(find.text('Accesos rápidos'), findsOneWidget);
    expect(find.text('Documentos'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home_tool_chat')));
    expect(selectedIndex, AppDestination.chat);
    await tester.tap(find.byKey(const Key('home_sign_out')));
    expect(signedOut, isTrue);
  });

  testWidgets('home personalizes the greeting for another user', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(displayName: 'Ana', onNavigate: (_) {}, onSignOut: () {}),
    ));
    expect(find.text('Hola, Ana'), findsOneWidget);
  });

  testWidgets('home uses a generic greeting when the name is blank', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(displayName: '  ', onNavigate: (_) {}, onSignOut: () {}),
    ));
    expect(find.text('Bienvenido'), findsOneWidget);
  });
}
