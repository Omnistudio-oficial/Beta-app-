import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Background entry point required by FlutterFire on Android and Apple devices.
/// Keep this handler free of UI work and avoid writing message content to logs.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}

/// Client-side registration and message listeners for the Flutter app.
/// Registration tokens remain in memory until a private server-side token
/// endpoint is available; they are never written to broadly readable RTDB paths.
class FirebaseMessagingService {
  FirebaseMessagingService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;
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
  }) {
    if (_listenersInstalled) return;
    _listenersInstalled = true;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(onMessageOpened);
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
        _registeredUid = null;
        _token = null;
        return false;
      }

      if (Platform.isIOS) {
        // APNs registration must be ready before FlutterFire can request its FCM token.
        var apnsToken = await _messaging.getAPNSToken();
        for (var attempt = 0; apnsToken == null && attempt < 5; attempt++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          apnsToken = await _messaging.getAPNSToken();
        }
        if (apnsToken == null) return false;
      }

      _token = await _messaging.getToken();
      if (_token == null || _token!.isEmpty) return false;
      _registeredUid = uid;
      return true;
    } catch (_) {
      // Push is optional and must never block sign-in or startup.
      _registeredUid = null;
      _token = null;
      return false;
    }
  }

  void handleTokenRefresh(void Function(String token) onToken) {
    _messaging.onTokenRefresh.listen((token) {
      _token = token;
      onToken(token);
    });
  }

  Future<RemoteMessage?> getInitialMessage() async {
    try {
      return await _messaging.getInitialMessage();
    } catch (_) {
      return null;
    }
  }
}
