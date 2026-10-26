import 'package:beta_app/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const localOnlyNotice =
      'Modo local: los mensajes no se envían a otras personas ni se sincronizan';
  const messagesKey = 'flutter_chat_local_messages_v1';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('starts empty and sends a message locally', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Chat'), findsOneWidget);
    expect(find.text(localOnlyNotice), findsOneWidget);
    expect(find.text('Aún no hay mensajes. Escribe uno para empezar.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Mensaje de prueba');
    await tester.pump();
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(find.text('Mensaje de prueba'), findsOneWidget);
    expect(find.text(localOnlyNotice), findsOneWidget);
    expect(SharedPreferences.getInstance().then((p) => p.getStringList(messagesKey)),
        completion(['Mensaje de prueba']));
  });

  testWidgets('restores local messages after screen reload', (tester) async {
    SharedPreferences.setMockInitialValues({messagesKey: ['Guardado en este dispositivo']});
    await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Guardado en este dispositivo'), findsOneWidget);
    expect(find.text(localOnlyNotice), findsOneWidget);
  });

  testWidgets('blank send is disabled and does not add a message', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
    await tester.pumpAndSettle();

    final sendButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(sendButton.onPressed, isNull);
    expect(find.text('Aún no hay mensajes. Escribe uno para empezar.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });
}
