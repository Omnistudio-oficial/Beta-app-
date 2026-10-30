import 'dart:async';

import 'package:beta_app/app/startup_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows branded progress while initialization is pending',
      (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(
      StartupGate(
        initialize: () => completer.future,
        appBuilder: (_) => const MaterialApp(home: Scaffold(body: Text('Application ready'))),
      ),
    );

    expect(find.text('OmniStudio'), findsOneWidget);
    expect(find.text('Preparando la aplicación…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Application ready'), findsNothing);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('Application ready'), findsOneWidget);
  });

  testWidgets('renders the app after successful initialization',
      (tester) async {
    await tester.pumpWidget(
      StartupGate(
        initialize: () async {},
        appBuilder: (_) => const MaterialApp(home: Scaffold(body: Text('Application ready'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Application ready'), findsOneWidget);
    expect(find.text('OmniStudio'), findsNothing);
  });

  testWidgets('shows a safe error and retries initialization', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      StartupGate(
        initialize: () async {
          attempts++;
          if (attempts == 1) {
            throw StateError('private configuration detail');
          }
        },
        appBuilder: (_) => const MaterialApp(home: Scaffold(body: Text('Application ready'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No se pudo iniciar'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('private configuration detail'), findsNothing);
    expect(find.text('Application ready'), findsNothing);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Application ready'), findsOneWidget);
  });

  testWidgets('shows progress during a retry and then safe error if it fails',
      (tester) async {
    var attempts = 0;
    final retry = Completer<void>();
    await tester.pumpWidget(
      StartupGate(
        initialize: () {
          attempts++;
          return attempts == 1
              ? Future<void>.error(Exception('initial failure'))
              : retry.future;
        },
        appBuilder: (_) => const MaterialApp(home: Scaffold(body: Text('Application ready'))),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reintentar'));
    await tester.pump();

    expect(find.text('Preparando la aplicación…'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
    retry.completeError(Exception('second failure'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo iniciar'), findsOneWidget);
    expect(find.text('Application ready'), findsNothing);
  });
}
