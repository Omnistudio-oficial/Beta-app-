import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const String chatMediaSupabaseProjectUrl = 'https://ovttmxwtljfqizcetoxk.supabase.co';
const String chatMediaSupabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const int maxChatMediaBytes = 50 * 1024 * 1024;

/// Mirrors the deployed chat-media-access validation.ts allowlist. Keep exact,
/// MIME-based matches: no generic application/octet-stream uploads.
const Map<String, String> supportedChatMediaMimeExtensions = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif',
  'image/bmp': 'bmp', 'image/heic': 'heic', 'image/heif': 'heif',
  'video/mp4': 'mp4', 'video/quicktime': 'mov', 'video/webm': 'webm',
  'video/3gpp': '3gp', 'video/x-m4v': 'm4v', 'video/x-matroska': 'mkv',
  'video/x-msvideo': 'avi', 'video/x-flv': 'flv', 'video/x-ms-wmv': 'wmv',
  'audio/ogg': 'ogg', 'audio/mp4': 'm4a',
  'application/pdf': 'pdf', 'application/msword': 'doc', 'application/rtf': 'rtf',
  'application/json': 'json', 'application/zip': 'zip', 'application/vnd.ms-excel': 'xls',
  'application/vnd.ms-powerpoint': 'ppt',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
  'text/plain': 'txt', 'text/csv': 'csv',
};

String chatMediaTypeForMime(String mime) {
  final normalized = mime.split(';').first.trim().toLowerCase();
  if (!supportedChatMediaMimeExtensions.containsKey(normalized)) {
    throw FormatException('Este tipo de archivo no está admitido por el servidor: $normalized');
  }
  if (normalized == 'image/gif') return 'gif';
  if (normalized.startsWith('image/')) return 'image';
  if (normalized.startsWith('video/')) return 'video';
  if (normalized.startsWith('audio/')) return 'audio';
  return 'document';
}

class UploadedChatMedia {
  const UploadedChatMedia({required this.storagePath, required this.publicUrl});
  final String storagePath;
  final String publicUrl;
}

class ChatMediaUploadPermission {
  const ChatMediaUploadPermission({required this.storagePath, required this.signedUrl, required this.mimeType, required this.maxUploadBytes});
  final String storagePath;
  final Uri signedUrl;
  final String mimeType;
  final int maxUploadBytes;
}

ChatMediaUploadPermission parseChatMediaUploadPermission({
  required Map<String, Object?> response,
  required String ownerUid,
  required String expectedMimeType,
  required Uri projectUrl,
}) {
  final storagePath = response['storagePath'];
  final responseMime = response['mimeType'];
  final rawSignedUrl = response['signedUrl'];
  final maxBytes = response['maxUploadBytes'];
  if (storagePath is! String || responseMime != expectedMimeType || rawSignedUrl is! String || maxBytes is! num || maxBytes.toInt() <= 0 || maxBytes.toInt() > maxChatMediaBytes) {
    throw const FormatException('El permiso seguro de subida no es válido.');
  }
  if (!supportedChatMediaMimeExtensions.containsKey(expectedMimeType)) throw const FormatException('Tipo MIME no admitido.');
  final segments = storagePath.split('/');
  final uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
  final filename = segments.length == 5 ? segments[4].split('.') : <String>[];
  if (segments.length != 5 || segments[0] != 'users' || segments[1] != ownerUid || segments[2] != 'media' || !uuid.hasMatch(segments[3]) || filename.length != 2 || !uuid.hasMatch(filename[0]) || filename[1] != supportedChatMediaMimeExtensions[expectedMimeType]) {
    throw const FormatException('La ruta de subida no pertenece a la cuenta autenticada o no concuerda con el MIME.');
  }
  if (projectUrl.scheme != 'https' || projectUrl.host.isEmpty) throw const FormatException('La URL de Supabase debe usar HTTPS.');
  final signed = rawSignedUrl.startsWith('/storage/v1/') ? projectUrl.resolve(rawSignedUrl) : rawSignedUrl.startsWith('/object/') ? projectUrl.resolve('/storage/v1$rawSignedUrl') : projectUrl.resolve(rawSignedUrl);
  final expectedPath = '/storage/v1/object/upload/sign/chat-media/$storagePath';
  if (signed.scheme != 'https' || signed.host != projectUrl.host || signed.port != projectUrl.port || signed.path != expectedPath || (signed.queryParameters['token'] ?? '').isEmpty) {
    throw const FormatException('La URL firmada no corresponde al bucket chat-media.');
  }
  return ChatMediaUploadPermission(storagePath: storagePath, signedUrl: signed, mimeType: expectedMimeType, maxUploadBytes: maxBytes.toInt());
}

abstract interface class ChatMediaUploadGateway {
  Future<UploadedChatMedia> upload({required String uid, required String filePath, required String fileName, required String mimeType, required String mediaType});
  Future<void> delete({required String uid, required String storagePath});
}

/// Signed upload access only; Firebase ID token is exchanged for a short-lived
/// grant. The app never has the Supabase service-role secret. The bucket itself
/// is PUBLIC: possession of a URL is sufficient to read the uploaded object.
class FirebaseChatMediaUploadGateway implements ChatMediaUploadGateway {
  FirebaseChatMediaUploadGateway({FirebaseAuth? auth, http.Client? client, Uri? projectUrl, String? publishableKey})
      : _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _projectUrl = projectUrl ?? Uri.parse(chatMediaSupabaseProjectUrl),
        _publishableKey = publishableKey ?? chatMediaSupabasePublishableKey;
  final FirebaseAuth _auth;
  final http.Client _client;
  final bool _ownsClient;
  final Uri _projectUrl;
  final String _publishableKey;

  Future<String> _idToken(String uid) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != uid) throw StateError('La sesión de Firebase cambió.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) throw StateError('No se pudo verificar la sesión de Firebase.');
    return token;
  }

  @override
  Future<UploadedChatMedia> upload({required String uid, required String filePath, required String fileName, required String mimeType, required String mediaType}) async {
    final normalized = mimeType.split(';').first.trim().toLowerCase();
    final category = chatMediaTypeForMime(normalized);
    if (category != mediaType) throw FormatException('El tipo seleccionado no concuerda con $normalized.');
    final file = File(filePath);
    final size = await file.length();
    if (size <= 0 || size > maxChatMediaBytes) throw const FormatException('El archivo debe tener entre 1 byte y 50 MiB.');
    final token = await _idToken(uid);
    final headers = <String, String>{HttpHeaders.authorizationHeader: 'Bearer $token', HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8', if (_publishableKey.isNotEmpty) 'apikey': _publishableKey};
    final permissionResponse = await _client.post(_projectUrl.resolve('/functions/v1/chat-media-access'), headers: headers, body: jsonEncode({'mediaType': mediaType, 'mimeType': normalized, 'sizeBytes': size})).timeout(const Duration(seconds: 30));
    if (permissionResponse.statusCode < 200 || permissionResponse.statusCode >= 300) throw HttpException('No se pudo autorizar la subida (${permissionResponse.statusCode}): ${_detail(permissionResponse.body)}');
    final decoded = jsonDecode(permissionResponse.body);
    if (decoded is! Map) throw const FormatException('Respuesta de permiso no válida.');
    final permission = parseChatMediaUploadPermission(response: Map<String, Object?>.from(decoded), ownerUid: uid, expectedMimeType: normalized, projectUrl: _projectUrl);
    if (size > permission.maxUploadBytes) throw const FormatException('El archivo supera el límite concedido de 50 MiB.');
    final uploadHeaders = <String, String>{HttpHeaders.contentTypeHeader: normalized, if (_publishableKey.isNotEmpty) 'apikey': _publishableKey};
    final result = await _client.put(permission.signedUrl, headers: uploadHeaders, body: await file.readAsBytes()).timeout(const Duration(minutes: 3));
    if (result.statusCode < 200 || result.statusCode >= 300) throw HttpException('Supabase Storage rechazó la subida (${result.statusCode}): ${_detail(result.body)}');
    return UploadedChatMedia(storagePath: permission.storagePath, publicUrl: _projectUrl.resolve('/storage/v1/object/public/chat-media/${permission.storagePath}').toString());
  }

  @override
  Future<void> delete({required String uid, required String storagePath}) async {
    if (!storagePath.startsWith('users/$uid/media/') || storagePath.contains('..')) throw ArgumentError('Ruta no válida para limpieza.');
    final token = await _idToken(uid);
    final response = await _client.post(_projectUrl.resolve('/functions/v1/delete-chat-media'), headers: {HttpHeaders.authorizationHeader: 'Bearer $token', HttpHeaders.contentTypeHeader: 'application/json', if (_publishableKey.isNotEmpty) 'apikey': _publishableKey}, body: jsonEncode({'storagePath': storagePath})).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('No se pudo limpiar el archivo subido (${response.statusCode}).');
  }

  String _detail(String body) {
    try {
      final value = jsonDecode(body);
      if (value is Map) {
        final detail = value['error'] ?? value['message'];
        if (detail is String) return detail.substring(0, detail.length.clamp(0, 300));
      }
    } catch (_) {}
    final trimmed = body.trim();
    return trimmed.substring(0, trimmed.length.clamp(0, 300));
  }

  void close() { if (_ownsClient) _client.close(); }
}
