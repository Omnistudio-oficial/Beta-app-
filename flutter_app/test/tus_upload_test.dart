import 'dart:io';

import 'package:beta_app/social/tus_upload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemorySessions implements TusUploadSessionStore {
  TusUploadSession? value;
  @override
  Future<TusUploadSession?> load(File source) async => value;
  @override
  Future<void> save(File source, TusUploadSession session) async { value = session; }
  @override
  Future<void> remove(File source) async { value = null; }
}

http.Response response(int status, [Map<String, String> headers = const {}]) => http.Response('', status, headers: headers);

void main() {
  group('TUS file cap', () {
    test('enforces the exact 50 MiB limit without allocating a large file', () {
      expect(isValidTusFileSize(1), isTrue);
      expect(isValidTusFileSize(50 * 1024 * 1024), isTrue);
      expect(isValidTusFileSize(50 * 1024 * 1024 + 1), isFalse);
      expect(isValidTusFileSize(0), isFalse);
    });
  });

  group('SupabaseTusUploader', () {
    late Directory dir;
    late File source;
    late MemorySessions sessions;
    final endpoint = Uri.https('project.storage.supabase.co', '/storage/v1/upload/resumable');

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('social_tus_test');
      source = File('${dir.path}/source.bin')..writeAsBytesSync([1, 2, 3, 4, 5]);
      sessions = MemorySessions();
    });
    tearDown(() async { await dir.delete(recursive: true); });

    test('creates a signed TUS upload then HEADs and PATCHes with offsets', () async {
      var offset = 0;
      final seen = <String>[];
      final client = MockClient((request) async {
        seen.add(request.method);
        if (request.method == 'POST') {
          expect(request.headers['x-signature'], 'signed-token');
          expect(request.headers['upload-length'], '5');
          expect(request.headers['upload-metadata'], contains('bucketName '));
          return response(201, {'location': '/storage/v1/upload/resumable/session-1'});
        }
        if (request.method == 'HEAD') return response(200, {'upload-offset': '$offset', 'upload-length': '5'});
        if (request.method == 'PATCH') {
          expect(request.headers['x-signature'], 'signed-token');
          expect(request.headers['upload-offset'], '$offset');
          expect(request.headers['content-type'], 'application/offset+octet-stream');
          offset += request.contentLength ?? 0;
          return response(204, {'upload-offset': '$offset'});
        }
        fail('Unexpected method ${request.method}');
      });
      final storedPaths = <String>[];
      final result = await SupabaseTusUploader(client: client, sessions: sessions).upload(
        source: source, mimeType: 'image/png', endpoint: endpoint, bucket: 'social-test-media',
        createSignedSession: () async => const TusUploadSession(storagePath: 'social_test/u/posts/a.png', signedToken: 'signed-token'),
        onStoragePath: storedPaths.add,
      );
      expect(result.uploadUrl, endpoint.resolve('/storage/v1/upload/resumable/session-1'));
      expect(result.storagePath, 'social_test/u/posts/a.png');
      expect(offset, 5);
      expect(seen, ['POST', 'HEAD', 'PATCH']);
      expect(storedPaths, ['social_test/u/posts/a.png']);
      expect(sessions.value, isNull);
    });

    test('resumes existing persistent URL by HEAD offset instead of creating a new upload', () async {
      final uploadUrl = endpoint.resolve('/storage/v1/upload/resumable/session-existing');
      sessions.value = TusUploadSession(storagePath: 'social_test/u/posts/a.png', signedToken: 'signed-token', uploadUrl: uploadUrl);
      var patchOffset = -1;
      var createCount = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') { createCount++; return response(500); }
        if (request.method == 'HEAD') return response(200, {'upload-offset': '2', 'upload-length': '5'});
        if (request.method == 'PATCH') {
          patchOffset = int.parse(request.headers['upload-offset']!);
          expect(request.contentLength, 3);
          return response(204, {'upload-offset': '5'});
        }
        fail('Unexpected method ${request.method}');
      });
      await SupabaseTusUploader(client: client, sessions: sessions).upload(
        source: source, mimeType: 'image/png', endpoint: endpoint, bucket: 'social-test-media',
        createSignedSession: () async { createCount++; return sessions.value!; }, onStoragePath: (_) {},
      );
      expect(patchOffset, 2);
      expect(createCount, 0);
    });

    test('recovers after a transient failed PATCH using authoritative HEAD offset', () async {
      var patchAttempts = 0;
      var offset = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') return response(201, {'location': '/upload/session'});
        if (request.method == 'HEAD') return response(200, {'upload-offset': '$offset', 'upload-length': '5'});
        if (request.method == 'PATCH') {
          patchAttempts++;
          if (patchAttempts == 1) return response(500);
          offset += request.contentLength ?? 0;
          return response(204, {'upload-offset': '$offset'});
        }
        fail('Unexpected method ${request.method}');
      });
      await SupabaseTusUploader(client: client, sessions: sessions).upload(
        source: source, mimeType: 'image/png', endpoint: endpoint, bucket: 'social-test-media',
        createSignedSession: () async => const TusUploadSession(storagePath: 'social_test/u/posts/a.png', signedToken: 'signed-token'),
        onStoragePath: (_) {},
      );
      expect(patchAttempts, 2);
      expect(offset, 5);
    });

    test('rejects invalid server offsets', () async {
      final client = MockClient((request) async {
        if (request.method == 'POST') return response(201, {'location': '/upload/session'});
        if (request.method == 'HEAD') return response(200, {'upload-offset': '6', 'upload-length': '5'});
        fail('Unexpected method ${request.method}');
      });
      await expectLater(SupabaseTusUploader(client: client, sessions: sessions).upload(
        source: source, mimeType: 'image/png', endpoint: endpoint, bucket: 'social-test-media',
        createSignedSession: () async => const TusUploadSession(storagePath: 'social_test/u/posts/a.png', signedToken: 'signed-token'),
        onStoragePath: (_) {},
      ), throwsA(isA<StateError>()));
    });
  });
}
