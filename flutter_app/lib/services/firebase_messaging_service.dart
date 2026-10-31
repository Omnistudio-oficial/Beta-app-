import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Background entry point required by FlutterFire on Android and Apple devices.
/// Keep the handler free of UI work and never log message content or tokens.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();
}

/// Client-side permission, registration, and receive listeners.
/// Tokens stay in memory until a private server endpoint is implemented.
class FirebaseMessagingService {
  FirebaseMessagingService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String? _registeredUid;
  String? _token;
  bool _listenersInstalled = false;

  String? get currentToken => _token;

  static bool permissionAllowsNotifications(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  void installListeners({
    required void Function(RemoteMessage message) onForegroundMessage,
    required void Function(RemoteMessage message) onMessageOpened,
    required void Function(String token) onTokenRefresh,
  }) {
    if (_listenersInstalled) return;
    _listenersInstalled = true;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _subscriptions.add(FirebaseMessaging.onMessage.listen(onForegroundMessage));
    _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen(onMessageOpened));
    _subscriptions.add(_messaging.onTokenRefresh.listen((token) {
      _token = token;
      onTokenRefresh(token);
    }));
  }

  Future<bool> registerForUser(String uid) async {
    if (uid.trim().isEmpty) return false;
    if (_registeredUid == uid && _token != null) return true;
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (!permissionAllowsNotifications(settings.authorizationStatus)) {
        clearUser();
        return false;
      }
      if (Platform.isIOS) {
        var apnsToken = await _messaging.getAPNSToken();
        for (var attempt = 0; apnsToken == null && attempt < 5; attempt++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          apnsToken = await _messaging.getAPNSToken();
        }
        if (apnsToken == null) return false;
      }
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return false;
      _token = token;
      _registeredUid = uid;
      return true;
    } catch (_) {
      clearUser();
      return false;
    }
  }

  void clearUser() {
    _registeredUid = null;
    _token = null;
  }

  Future<RemoteMessage?> getInitialMessage() async {
    try {
      return await _messaging.getInitialMessage();
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _listenersInstalled = false;
  }
}
