import 'package:beta_app/services/firebase_messaging_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Firebase Messaging permission policy', () {
    test('allows authorized and provisional permissions', () {
      expect(
        FirebaseMessagingService.permissionAllowsNotifications(
          AuthorizationStatus.authorized,
        ),
        isTrue,
      );
      expect(
        FirebaseMessagingService.permissionAllowsNotifications(
          AuthorizationStatus.provisional,
        ),
        isTrue,
      );
    });

    test('does not register when permission is denied or undecided', () {
      expect(
        FirebaseMessagingService.permissionAllowsNotifications(
          AuthorizationStatus.denied,
        ),
        isFalse,
      );
      expect(
        FirebaseMessagingService.permissionAllowsNotifications(
          AuthorizationStatus.notDetermined,
        ),
        isFalse,
      );
    });
  });
}
