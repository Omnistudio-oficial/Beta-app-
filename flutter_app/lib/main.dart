import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:beta_app/app/app.dart';
import 'package:beta_app/app/startup_gate.dart';

Future<void> _initializeFirebase() async {
  // Firebase.initializeApp can be retried safely if an earlier attempt
  // registered the default app before failing later in bootstrap.
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    StartupGate(
      initialize: _initializeFirebase,
      appBuilder: (_) => const AppRoot(),
    ),
  );
}
