import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

const socialMaxCaptionLength = 2200;
const socialMaxMediaItems = 5;
const socialMaxFileBytes = 50 * 1024 * 1024;
const socialSupportedMimeTypes = <String>{
  'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'image/heif',
  'video/mp4', 'video/quicktime', 'video/webm', 'video/3gpp', 'video/x-m4v',
};

class SocialMediaFile {
  const SocialMediaFile({required this.path, required this.mimeType, required this.name});
  final String path;
  final String mimeType;
  final String name;
}

class SocialMediaItem {
  const SocialMediaItem({required this.path, required this.mimeType});
  final String path;
  final String mimeType;
  bool get isVideo => mimeType.startsWith('video/');
  Map<String, Object?> toMap() => {
        'mediaPath': path,
        'mediaType': isVideo ? 'video' : 'image',
        'mimeType': mimeType,
      };
}

class SocialPost {
  const SocialPost({required this.id, required this.ownerUid, required this.caption, required this.createdAt, this.mediaItems = const [], this.username = '', this.displayName = ''});
  final String id;
  final String ownerUid;
  final String caption;
  final int createdAt;
  final List<SocialMediaItem> mediaItems;
  final String username;
  final String displayName;

  factory SocialPost.fromSnapshot(DataSnapshot snapshot) {
    final raw = snapshot.value;
    final value = raw is Map ? Map<Object?, Object?>.from(raw) : <Object?, Object?>{};
    final items = parseMediaItems(value['mediaItems']);
    final legacyPath = value['mediaPath'];
    if (items.isEmpty && legacyPath is String && legacyPath.isNotEmpty) {
      items.add(SocialMediaItem(path: legacyPath, mimeType: value['mediaType'] == 'video' ? 'video/mp4' : 'image/jpeg'));
    }
    return SocialPost(
      id: '${value['id'] ?? snapshot.key ?? ''}',
      ownerUid: '${value['ownerUid'] ?? ''}',
      caption: '${value['caption'] ?? ''}',
      createdAt: (value['createdAt'] as num?)?.toInt() ?? 0,
      mediaItems: items,
      username: '${value['username'] ?? ''}',
      displayName: '${value['displayName'] ?? value['username'] ?? ''}',
    );
  }

  /// RTDB can serialize list-like mediaItems as a list or as a keyed map.
  static List<SocialMediaItem> parseMediaItems(Object? rawItems) {
    final entries = rawItems is List
        ? rawItems
        : rawItems is Map
            ? rawItems.values.toList()
            : const <Object?>[];
    return entries.whereType<Map>().map((entry) {
      final path = '${entry['mediaPath'] ?? ''}';
      final fallback = entry['mediaType'] == 'video' ? 'video/mp4' : 'image/jpeg';
      if (path.isEmpty) return null;
      return SocialMediaItem(path: path, mimeType: '${entry['mimeType'] ?? fallback}');
    }).whereType<SocialMediaItem>().toList();
  }
}

class SocialComment {
  const SocialComment({required this.id, required this.authorUid, required this.authorName, required this.text, required this.createdAt});
  final String id;
  final String authorUid;
  final String authorName;
  final String text;
  final int createdAt;
}

abstract interface class SocialService {
  String get currentUid;
  Stream<List<SocialPost>> watchMyPosts();
  Stream<List<SocialPost>> watchPublicFeed();
  Future<bool> canInteract(SocialPost post);
  Stream<Set<String>> watchLikes(SocialPost post);
  Stream<List<SocialComment>> watchComments(SocialPost post);
  Future<void> toggleLike(SocialPost post, bool liked);
  Future<void> addComment(SocialPost post, String text);
  Future<void> createPost({required String caption, required List<SocialMediaFile> media});
  Future<String> signedMediaUrl(SocialPost post, SocialMediaItem media);
}

class SocialPostValidation {
  static String? validate({required String caption, required List<SocialMediaFile> media}) {
    if (caption.trim().length > socialMaxCaptionLength) return 'El texto no puede superar 2.200 caracteres.';
    if (media.length > socialMaxMediaItems) return 'Puedes adjuntar hasta cinco archivos por publicación.';
    if (caption.trim().isEmpty && media.isEmpty) return 'Escribe algo o selecciona una foto o video.';
    for (final item in media) {
      if (!socialSupportedMimeTypes.contains(item.mimeType.toLowerCase().split(';').first.trim())) {
        return 'El formato ${item.name} no está permitido.';
      }
    }
    return null;
  }
}

/// Uses the deployed private-media function and authenticated per-user RTDB path.
/// It deliberately never writes publicFeed, profiles, or directory records.
class FirebaseSocialService implements SocialService {
  FirebaseSocialService({FirebaseAuth? auth, FirebaseDatabase? database, http.Client? client,
    String? supabaseUrl, String? publishableKey})
      : _auth = auth ?? FirebaseAuth.instance,
        _database = database ?? FirebaseDatabase.instance,
        _http = client ?? http.Client(),
        _supabaseUrl = supabaseUrl ?? _defaultSupabaseUrl,
        _publishableKey = publishableKey ?? _defaultPublishableKey;

  static const _defaultSupabaseUrl = String.fromEnvironment('SUPABASE_PROJECT_URL');
  static const _defaultPublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final FirebaseAuth _auth;
  final FirebaseDatabase _database;
  final http.Client _http;
  final String _supabaseUrl;
  final String _publishableKey;

  User _user() => _auth.currentUser ?? (throw StateError('Inicia sesión para usar Social.'));
  @override
  String get currentUid => _user().uid;
  DatabaseReference get _posts => _database.ref('social_test/postsByUser/${_user().uid}');
  DatabaseReference get _social => _database.ref('social_test');

  @override
  Stream<List<SocialPost>> watchMyPosts() => _posts.onValue.map((event) {
        final posts = event.snapshot.children
            .where((child) => child.value is Map)
            .map(SocialPost.fromSnapshot)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return posts;
      });

  /// Authenticated public-feed read; the deployed RTDB rules are authoritative.
  @override
  Stream<List<SocialPost>> watchPublicFeed() => _social.child('publicFeed')
      .orderByChild('createdAt').limitToLast(50).onValue.asyncMap((event) async {
        final posts = event.snapshot.children
            .where((child) => child.value is Map)
            .map(SocialPost.fromSnapshot)
            .where((post) => post.ownerUid.isNotEmpty && post.id.isNotEmpty)
            .toList();
        final visible = await Future.wait(posts.map((post) async {
          try {
            final visibility = await _social.child('profiles/${post.ownerUid}/visibility').get();
            return visibility.value == 'public' ? post : null;
          } catch (_) {
            return null;
          }
        }));
        return visible.whereType<SocialPost>().toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });

  @override
  Future<bool> canInteract(SocialPost post) async {
    final uid = _user().uid;
    if (post.ownerUid == uid) return true;
    try {
      final follower = await _social.child('followers/${post.ownerUid}/$uid/status').get();
      if (follower.value == 'accepted') return true;
    } catch (_) {
      // Private target may deny follower reads; public-profile check follows.
    }
    try {
      final visibility = await _social.child('profiles/${post.ownerUid}/visibility').get();
      return visibility.value == 'public';
    } catch (_) {
      return false;
    }
  }

  DatabaseReference _likes(SocialPost post) => _social.child('likes/${post.ownerUid}/${post.id}');
  DatabaseReference _comments(SocialPost post) => _social.child('comments/${post.ownerUid}/${post.id}');

  @override
  Stream<Set<String>> watchLikes(SocialPost post) => _likes(post).onValue.map((event) =>
      event.snapshot.children.where((child) => child.value == true).map((child) => child.key!).toSet());

  @override
  Stream<List<SocialComment>> watchComments(SocialPost post) => _comments(post).onValue.map((event) {
        final comments = event.snapshot.children.where((child) => child.value is Map).map((child) {
          final value = Map<Object?, Object?>.from(child.value as Map);
          return SocialComment(id: child.key ?? '', authorUid: '${value['authorUid'] ?? ''}',
              authorName: '${value['authorDisplayName'] ?? value['authorUsername'] ?? 'Usuario'}',
              text: '${value['text'] ?? ''}', createdAt: (value['createdAt'] as num?)?.toInt() ?? 0);
        }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return comments;
      });

  @override
  Future<void> toggleLike(SocialPost post, bool liked) async {
    final uid = _user().uid;
    if (liked) { await _likes(post).child(uid).set(true); }
    else { await _likes(post).child(uid).remove(); }
  }

  @override
  Future<void> addComment(SocialPost post, String text) async {
    final user = _user();
    final clean = text.trim();
    if (clean.isEmpty || clean.length > 1000) throw ArgumentError('El comentario debe tener entre 1 y 1.000 caracteres.');
    final ref = _comments(post).push();
    await ref.set({
      'authorUid': user.uid,
      'authorUsername': (user.displayName ?? user.email?.split('@').first ?? 'usuario').toLowerCase(),
      'authorDisplayName': user.displayName ?? user.email?.split('@').first ?? 'Usuario',
      'text': clean,
      'createdAt': ServerValue.timestamp,
    });
  }

  @override
  Future<void> createPost({required String caption, required List<SocialMediaFile> media}) async {
    if (_supabaseUrl.isEmpty || _publishableKey.isEmpty) {
      throw StateError('La configuración de contenido privado no está disponible en esta compilación.');
    }
    final validation = SocialPostValidation.validate(caption: caption, media: media);
    if (validation != null) throw ArgumentError(validation);
    final user = _user();
    final uploaded = <String>[];
    DatabaseReference? postRef;
    try {
      final mediaItems = <SocialMediaItem>[];
      for (final file in media) {
        final mime = file.mimeType.toLowerCase().split(';').first.trim();
        final source = File(file.path);
        final length = await source.length();
        if (length < 1 || length > socialMaxFileBytes) {
          throw ArgumentError('${file.name} debe pesar entre 1 byte y 50 MiB.');
        }
        final token = await user.getIdToken();
        if (token == null || token.isEmpty) throw StateError('No se pudo verificar la sesión.');
        final prepared = await _callFunction(token, {
          'action': 'create-upload', 'entityType': 'post', 'mimeType': mime,
        });
        final path = prepared['storagePath'] as String?;
        final signedUpload = prepared['signedUrl'] as String?;
        if (path == null || path.isEmpty || signedUpload == null || signedUpload.isEmpty) {
          throw StateError('No se pudo preparar la carga privada.');
        }
        final upload = http.StreamedRequest('PUT', _url(signedUpload))
          ..headers['apikey'] = _publishableKey
          ..headers['content-type'] = mime
          ..contentLength = length;
        uploaded.add(path);
        await upload.sink.addStream(source.openRead());
        await upload.sink.close();
        final response = await _http.send(upload);
        await response.stream.drain<void>();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw StateError('La carga privada fue rechazada (${response.statusCode}).');
        }
        mediaItems.add(SocialMediaItem(path: path, mimeType: mime));
      }

      postRef = _posts.push();
      final id = postRef.key;
      if (id == null) throw StateError('No se pudo crear la publicación.');
      final videos = mediaItems.where((item) => item.isVideo).toList();
      final primary = videos.isNotEmpty ? videos.first : (mediaItems.isEmpty ? null : mediaItems.first);
      final username = user.displayName ?? user.email?.split('@').first ?? 'usuario';
      await postRef.set(<String, Object?>{
        'id': id,
        'ownerUid': user.uid,
        'username': username,
        'displayName': username,
        'avatarUrl': '',
        'caption': caption.trim(),
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'topics': <String, bool>{},
        'mediaPath': primary?.path ?? '',
        'mediaType': primary == null ? '' : (primary.isVideo ? 'video' : 'image'),
        if (mediaItems.isNotEmpty) 'mediaItems': mediaItems.map((item) => item.toMap()).toList(),
      });
    } catch (_) {
      if (postRef != null) {
        try { await postRef.remove(); } catch (_) { /* best effort */ }
      }
      for (final path in uploaded) {
        try {
          final token = await _auth.currentUser?.getIdToken();
          if (token != null) await _callFunction(token, {'action': 'delete', 'storagePath': path});
        } catch (_) { /* preserve original failure */ }
      }
      rethrow;
    }
  }

  @override
  Future<String> signedMediaUrl(SocialPost post, SocialMediaItem media) async {
    final user = _user();
    if (post.ownerUid != user.uid) throw StateError('Solo puedes abrir contenido de tu cuenta.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) throw StateError('No se pudo verificar la sesión.');
    final response = await _callFunction(token, {
      'action': 'signed-download', 'storagePath': media.path,
      'entityType': 'post', 'entityId': post.id,
    });
    final signed = response['signedUrl'] as String?;
    if (signed == null || signed.isEmpty) throw StateError('No se pudo abrir el contenido privado.');
    return _url(signed).toString();
  }

  Future<Map<String, dynamic>> _callFunction(String token, Map<String, Object?> payload) async {
    final uri = Uri.parse('${_supabaseUrl.replaceFirst(RegExp(r'/$'), '')}/functions/v1/social-media-access');
    final response = await _http.post(uri, headers: {
      'apikey': _publishableKey,
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
    }, body: jsonEncode(payload));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? safeError;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] is String) safeError = decoded['error'] as String;
      } catch (_) { /* generic error */ }
      if (safeError == null || safeError.contains('http')) safeError = 'No se pudo verificar el acceso al contenido (${response.statusCode}).';
      throw StateError(safeError);
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) throw StateError('Respuesta de Social no válida.');
    return body;
  }

  Uri _url(String value) {
    final parsed = Uri.parse(value);
    if (parsed.hasScheme && (parsed.scheme == 'https' || parsed.scheme == 'http')) return parsed;
    final base = _supabaseUrl.replaceFirst(RegExp(r'/$'), '');
    if (value.startsWith('/storage/v1/')) return Uri.parse('$base$value');
    if (value.startsWith('/object/')) return Uri.parse('$base/storage/v1$value');
    throw StateError('La URL privada no es válida.');
  }
}
