import 'package:beta_app/screens/auth_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows Google sign-in and keeps email/password sign-in',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));

    expect(find.text('Iniciar sesión con Google'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
  });

  testWidgets('Google cancellation is quiet and does not block later use',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: AuthScreen(onGoogleSignIn: () async {
        calls++;
        return null;
      }),
    ));

    await tester.tap(find.text('Iniciar sesión con Google'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Sesión iniciada correctamente'), findsNothing);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('Google errors are shown and registration hides Google option',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AuthScreen(onGoogleSignIn: () async {
        throw FirebaseAuthException(code: 'test-failure', message: 'Falló Google');
      }),
    ));

    await tester.tap(find.text('Iniciar sesión con Google'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Falló Google'), findsOneWidget);

    await tester.tap(find.text('¿No tienes cuenta? Regístrate'));
    await tester.pumpAndSettle();
    expect(find.text('Crear cuenta'), findsNWidgets(2));
    expect(find.text('Iniciar sesión con Google'), findsNothing);
  });
}
