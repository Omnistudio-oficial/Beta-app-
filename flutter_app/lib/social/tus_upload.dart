import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const supabaseTusChunkBytes = 6 * 1024 * 1024;
const socialTusMaxFileBytes = 50 * 1024 * 1024;
bool isValidTusFileSize(int bytes) => bytes >= 1 && bytes <= socialTusMaxFileBytes;
const _tusVersion = '1.0.0';
const _tusRetryDelays = <Duration>[Duration(milliseconds: 300), Duration(milliseconds: 900), Duration(seconds: 2)];

class TusUploadSession {
  const TusUploadSession({required this.storagePath, required this.signedToken, this.uploadUrl});
  final String storagePath;
  final String signedToken;
  final Uri? uploadUrl;
  TusUploadSession withUploadUrl(Uri url) => TusUploadSession(storagePath: storagePath, signedToken: signedToken, uploadUrl: url);
  Map<String, Object?> toJson() => {'storagePath': storagePath, 'signedToken': signedToken, 'uploadUrl': uploadUrl?.toString()};
  static TusUploadSession? fromJson(Object? value) {
    if (value is! Map) return null;
    final path = value['storagePath'], token = value['signedToken'], rawUrl = value['uploadUrl'];
    if (path is! String || path.isEmpty || token is! String || token.isEmpty) return null;
    Uri? url;
    if (rawUrl is String && rawUrl.isNotEmpty) {
      url = Uri.tryParse(rawUrl);
      if (url == null || url.scheme != 'https') return null;
    }
    return TusUploadSession(storagePath: path, signedToken: token, uploadUrl: url);
  }
}

abstract interface class TusUploadSessionStore {
  Future<TusUploadSession?> load(File source);
  Future<void> save(File source, TusUploadSession session);
  Future<void> remove(File source);
  static TusUploadSessionStore appPrivate() => SecureTusUploadSessionStore();
}

/// Stores upload URLs and signed tokens in the platform secure keystore.
class SecureTusUploadSessionStore implements TusUploadSessionStore {
  SecureTusUploadSessionStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();
  static const _prefix = 'social_tus_session_';
  final FlutterSecureStorage _storage;
  @override
  Future<TusUploadSession?> load(File source) async {
    try {
      final raw = await _storage.read(key: '$_prefix${await _identity(source)}');
      return raw == null ? null : TusUploadSession.fromJson(jsonDecode(raw));
    } catch (_) { return null; }
  }
  @override
  Future<void> save(File source, TusUploadSession session) async => _storage.write(
      key: '$_prefix${await _identity(source)}', value: jsonEncode(session.toJson()));
  @override
  Future<void> remove(File source) async => _storage.delete(key: '$_prefix${await _identity(source)}');
  Future<String> _identity(File source) async {
    final stat = await source.stat();
    return sha256.convert(utf8.encode('${source.absolute.path}\n${stat.size}\n${stat.modified.millisecondsSinceEpoch}')).toString();
  }
}

class TusSessionExpiredException implements Exception {
  const TusSessionExpiredException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Supabase TUS client with signed uploads, 6 MiB chunks and bounded resumption.
class SupabaseTusUploader {
  SupabaseTusUploader({required http.Client client, required TusUploadSessionStore sessions})
      : _client = client, _sessions = sessions;
  final http.Client _client;
  final TusUploadSessionStore _sessions;

  Future<TusUploadSession> upload({
    required File source,
    required String mimeType,
    required Uri endpoint,
    required String bucket,
    required Future<TusUploadSession> Function() createSignedSession,
    required void Function(String storagePath) onStoragePath,
  }) async {
    final length = await source.length();
    if (!isValidTusFileSize(length)) throw ArgumentError('El archivo debe pesar entre 1 byte y 50 MiB.');
    var session = await _sessions.load(source) ?? await createSignedSession();
    onStoragePath(session.storagePath);
    await _sessions.save(source, session);
    for (var generation = 0; generation < 2; generation++) {
      try {
        final url = session.uploadUrl ?? await _create(endpoint, bucket, session, length, mimeType);
        if (session.uploadUrl == null) {
          session = session.withUploadUrl(url);
          await _sessions.save(source, session);
        }
        await _transfer(source, length, url, session.signedToken);
        await _sessions.remove(source);
        return session;
      } on TusSessionExpiredException {
        await _sessions.remove(source);
        if (generation != 0) rethrow;
        session = await createSignedSession();
        onStoragePath(session.storagePath);
        await _sessions.save(source, session);
      }
    }
    throw const TusSessionExpiredException('No se pudo renovar la sesión de carga.');
  }

  Future<Uri> _create(Uri endpoint, String bucket, TusUploadSession session, int length, String mimeType) async {
    final metadata = <String, String>{'bucketName': bucket, 'objectName': session.storagePath,
      'contentType': mimeType, 'cacheControl': '3600'}
        .entries.map((e) => '${e.key} ${base64.encode(utf8.encode(e.value))}').join(',');
    final request = http.Request('POST', endpoint)..headers.addAll({
      'Tus-Resumable': _tusVersion, 'Upload-Length': '$length', 'Upload-Metadata': metadata,
      'x-signature': session.signedToken,
    });
    final response = await _send(request);
    if (response.statusCode == 404 || response.statusCode == 410) throw const TusSessionExpiredException('La sesión de carga venció.');
    if (response.statusCode != 201) throw StateError('No se pudo iniciar la carga TUS (${response.statusCode}).');
    final location = response.headers['location'];
    if (location == null || location.isEmpty) throw StateError('El servidor no devolvió la URL de carga TUS.');
    final url = endpoint.resolve(location);
    if (url.scheme != 'https' || url.host != endpoint.host) throw StateError('La URL de carga TUS no es válida.');
    return url;
  }

  Future<void> _transfer(File source, int length, Uri url, String token) async {
    var offset = await _head(url, token, length);
    while (offset < length) {
      final end = (offset + supabaseTusChunkBytes).clamp(0, length).toInt();
      Object? lastError;
      var advanced = false;
      for (var attempt = 0; attempt <= _tusRetryDelays.length; attempt++) {
        if (attempt > 0) await Future<void>.delayed(_tusRetryDelays[attempt - 1]);
        try {
          final chunk = await source.openRead(offset, end).fold<List<int>>(<int>[], (all, part) => all..addAll(part));
          final request = http.Request('PATCH', url)
            ..headers.addAll({
              'Tus-Resumable': _tusVersion, 'Upload-Offset': '$offset',
              'Content-Type': 'application/offset+octet-stream', 'x-signature': token,
            })
            ..bodyBytes = chunk;
          final response = await _send(request);
          if (response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404 || response.statusCode == 410) throw const TusSessionExpiredException('La sesión de carga venció o dejó de ser válida.');
          if (response.statusCode == 204) {
            final next = int.tryParse(response.headers['upload-offset'] ?? '');
            if (next == null || next <= offset || next > length) throw StateError('El servidor devolvió un desplazamiento TUS no válido.');
            offset = next; advanced = true; break;
          }
          if (response.statusCode == 409) {
            final serverOffset = await _head(url, token, length);
            if (serverOffset > offset) { offset = serverOffset; advanced = true; break; }
            lastError = StateError('Conflicto al continuar la carga TUS.');
          } else {
            lastError = StateError('La carga TUS fue rechazada (${response.statusCode}).');
            if (response.statusCode >= 400 && response.statusCode < 500) throw lastError;
          }
        } on TusSessionExpiredException { rethrow; }
        catch (error) { lastError = error; }
        try {
          final serverOffset = await _head(url, token, length);
          if (serverOffset > offset) { offset = serverOffset; advanced = true; break; }
          if (serverOffset < offset) throw StateError('El servidor devolvió un desplazamiento TUS anterior.');
        } on TusSessionExpiredException { rethrow; }
        catch (error) { lastError = error; }
      }
      if (!advanced) throw StateError('La carga se interrumpió tras varios intentos: $lastError');
    }
  }

  Future<int> _head(Uri url, String token, int expectedLength) async {
    final response = await _send(http.Request('HEAD', url)..headers.addAll({'Tus-Resumable': _tusVersion, 'x-signature': token}));
    if (response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404 || response.statusCode == 410) throw const TusSessionExpiredException('La sesión de carga venció o dejó de ser válida.');
    if (response.statusCode != 200 && response.statusCode != 204) throw StateError('No se pudo consultar el avance TUS (${response.statusCode}).');
    final offset = int.tryParse(response.headers['upload-offset'] ?? '');
    final length = int.tryParse(response.headers['upload-length'] ?? '$expectedLength');
    if (offset == null || offset < 0 || offset > expectedLength || length != expectedLength) throw StateError('El servidor devolvió un estado TUS no válido.');
    return offset;
  }

  Future<http.StreamedResponse> _send(http.BaseRequest request) async {
    final response = await _client.send(request);
    await response.stream.drain<void>();
    return response;
  }
}
