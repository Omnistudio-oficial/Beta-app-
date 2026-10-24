import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:beta_app/app/navigation_shell.dart';
import 'package:beta_app/screens/auth_screen.dart';
import 'package:beta_app/screens/splash_screen.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OmniStudio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SplashScreen();
          }

          if (snapshot.hasData) {
            return const NavigationShell();
          }

          return const AuthScreen();
        },
      ),
    );
  }
}
