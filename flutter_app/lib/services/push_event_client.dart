import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const _supabaseUrl = String.fromEnvironment('SUPABASE_PROJECT_URL');
const _publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// Best-effort request to an existing server-side event handler. Recipients are
/// deliberately absent: the Edge Function derives/validates them from its event.
Future<void> notifyVerifiedEvent({
  required FirebaseAuth auth,
  required String functionName,
  required Map<String, Object?> payload,
}) async {
  final url = _supabaseUrl;
  if (url.isEmpty || _publishableKey.isEmpty) return;
  try {
    final user = auth.currentUser;
    if (user == null) return;
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) return;
    final base = url.replaceFirst(RegExp(r'/$'), '');
    await http.post(
      Uri.parse('$base/functions/v1/$functionName'),
      headers: {
        'apikey': _publishableKey,
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      },
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 8));
  } catch (_) {
    // Push is auxiliary; a delivered chat/Social write must not be rolled back.
  }
}
