import 'package:beta_app/services/otp_navigation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OtpNavigationPolicy', () {
    test('accepts HTTPS origins on the standard port', () {
      expect(
        OtpNavigationPolicy.httpsOrigin(Uri.parse('https://login.example.com/path')),
        'https://login.example.com',
      );
    });

    test('rejects HTTP, non-standard ports, and embedded credentials', () {
      expect(OtpNavigationPolicy.httpsOrigin(Uri.parse('http://example.com')), isNull);
      expect(OtpNavigationPolicy.httpsOrigin(Uri.parse('https://example.com:8443')), isNull);
      expect(
        OtpNavigationPolicy.httpsOrigin(Uri.parse('https://user:pass@example.com')),
        isNull,
      );
    });

    test('matches exact origins and never trusts lookalike suffixes', () {
      final allowed = <String>{'https://example.com'};

      expect(
        OtpNavigationPolicy.isAllowed(Uri.parse('https://example.com/login'), allowed),
        isTrue,
      );
      expect(
        OtpNavigationPolicy.isAllowed(Uri.parse('https://sub.example.com'), allowed),
        isFalse,
      );
      expect(
        OtpNavigationPolicy.isAllowed(Uri.parse('https://example.com.evil.test'), allowed),
        isFalse,
      );
    });
  });
}
