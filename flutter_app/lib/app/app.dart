import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'package:beta_app/app/navigation_shell.dart';
import 'package:beta_app/screens/auth_screen.dart';
import 'package:beta_app/screens/splash_screen.dart';
import 'package:beta_app/services/firebase_messaging_service.dart';

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _messaging = FirebaseMessagingService();
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _messaging.installListeners(
      onForegroundMessage: _onForegroundMessage,
      onMessageOpened: _onMessageOpened,
      onTokenRefresh: (_) {},
    );
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _messaging.clearUser();
      } else {
        _messaging.registerForUser(user.uid);
      }
    });
    _handleInitialMessage();
  }

  Future<void> _handleInitialMessage() async {
    final message = await _messaging.getInitialMessage();
    if (message != null) _onMessageOpened(message);
  }

  void _onForegroundMessage(RemoteMessage message) {
    final parts = [message.notification?.title, message.notification?.body]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(parts.join(' — '))),
    );
  }

  void _onMessageOpened(RemoteMessage message) {
    // Deep-link routing will be added once the sender payload contract is set.
    _onForegroundMessage(message);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _messaging.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
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
          if (snapshot.hasData) return const NavigationShell();
          return const AuthScreen();
        },
      ),
    );
  }
}
