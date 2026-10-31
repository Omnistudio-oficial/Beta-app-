import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;

const _registryAppId = 'com.omnistudio.omnistudioFlutterPrototype';
const _defaultSupabaseUrl = String.fromEnvironment('SUPABASE_PROJECT_URL');
const _defaultSupabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// Background entry point required by FlutterFire on Android and Apple devices.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();
}

/// FCM registration and client receipt for Flutter Android/iOS.
/// The raw token is sent only to the private Supabase Edge Function over HTTPS;
/// it is never written into Firebase RTDB or printed to logs.
class FirebaseMessagingService {
  FirebaseMessagingService({
    FirebaseMessaging? messaging,
    FirebaseAuth? auth,
    http.Client? client,
    String? supabaseUrl,
    String? publishableKey,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? http.Client(),
        _supabaseUrl = supabaseUrl ?? _defaultSupabaseUrl,
        _publishableKey = publishableKey ?? _defaultSupabasePublishableKey;

  final FirebaseMessaging _messaging;
  final FirebaseAuth _auth;
  final http.Client _client;
  final String _supabaseUrl;
  final String _publishableKey;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String? _registeredUid;
  String? _token;
  bool _listenersInstalled = false;

  String? get currentToken => _token;
  String? get currentUid => _registeredUid;
  static bool permissionAllowsNotifications(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized || status == AuthorizationStatus.provisional;

  void installListeners({
    required void Function(RemoteMessage message) onForegroundMessage,
    required void Function(RemoteMessage message) onMessageOpened,
  }) {
    if (_listenersInstalled) return;
    _listenersInstalled = true;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _subscriptions.add(FirebaseMessaging.onMessage.listen(onForegroundMessage));
    _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen(onMessageOpened));
    _subscriptions.add(_messaging.onTokenRefresh.listen((token) {
      _token = token;
      final uid = _registeredUid;
      if (uid != null) unawaited(_persistToken(uid, token));
    }));
  }

  Future<bool> registerForUser(String uid) async {
    if (uid.trim().isEmpty) return false;
    try {
      final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
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
      return await _persistToken(uid, token);
    } catch (_) {
      clearUser();
      return false;
    }
  }

  Future<bool> _persistToken(String uid, String token) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.uid != uid) return false;
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) return false;
      final base = _supabaseUrl.replaceFirst(RegExp(r'/$'), '');
      final response = await _client.post(
        Uri.parse('$base/functions/v1/register-fcm-device'),
        headers: {
          'apikey': _publishableKey,
          'authorization': 'Bearer $idToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'action': 'register',
          'appId': _registryAppId,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'token': token,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Sends an authenticated self-test notification through the Supabase Edge Function.
  /// The server rejects recipient UIDs other than the caller's verified Firebase UID.
  Future<bool> sendSelfTestNotification() async {
    try {
      final user = _auth.currentUser;
      if (user == null || _token == null || user.uid != _registeredUid) return false;
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) return false;
      final base = _supabaseUrl.replaceFirst(RegExp(r'/$'), '');
      final response = await _client.post(
        Uri.parse('$base/functions/v1/send-flutter-push'),
        headers: {
          'apikey': _publishableKey,
          'authorization': 'Bearer $idToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'recipientUid': user.uid,
          'title': 'Prueba de notificaciones',
          'body': 'La conexión de OmniStudio está lista para probar.',
          'data': {'eventType': 'self_test'},
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Call before signing out while the Firebase user is still available.
  Future<bool> unregisterCurrentDevice(String uid) async {
    final token = _token;
    if (token == null || uid != _registeredUid) return false;
    try {
      final user = _auth.currentUser;
      if (user == null || user.uid != uid) return false;
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) return false;
      final base = _supabaseUrl.replaceFirst(RegExp(r'/$'), '');
      final response = await _client.post(
        Uri.parse('$base/functions/v1/register-fcm-device'),
        headers: {
          'apikey': _publishableKey,
          'authorization': 'Bearer $idToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'action': 'unregister',
          'appId': _registryAppId,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'token': token,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        clearUser();
        return true;
      }
    } catch (_) {
      // Keep app sign-out available if the optional push registry is offline.
    }
    return false;
  }

  void clearUser() {
    _registeredUid = null;
    _token = null;
  }

  Future<RemoteMessage?> getInitialMessage() async {
    try { return await _messaging.getInitialMessage(); } catch (_) { return null; }
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _listenersInstalled = false;
  }
}
