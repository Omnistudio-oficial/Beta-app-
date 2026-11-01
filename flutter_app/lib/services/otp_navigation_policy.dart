/// Strict origin checks for the private OTP browser.
///
/// Only HTTPS on the standard port is eligible. Origins are exact; this does
/// not use suffix or wildcard matching, so example.com.evil.test never
/// matches example.com.
class OtpNavigationPolicy {
  const OtpNavigationPolicy._();

  static String? httpsOrigin(Uri? uri) {
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443) {
      return null;
    }
    return uri.origin;
  }

  static bool isAllowed(Uri? uri, Set<String> allowedOrigins) {
    final origin = httpsOrigin(uri);
    return origin != null && allowedOrigins.contains(origin);
  }
}
