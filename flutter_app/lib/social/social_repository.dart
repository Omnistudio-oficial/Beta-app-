import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

import 'tus_upload.dart';

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

class SocialProfile {
  const SocialProfile({required this.uid, required this.username, required this.displayName, required this.visibility});
  final String uid;
  final String username;
  final String displayName;
  final String visibility;
  bool get isPrivate => visibility != 'public';
}

class SocialFollowRequest {
  const SocialFollowRequest({required this.uid, required this.username, required this.displayName});
  final String uid;
  final String username;
  final String displayName;
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
  Future<SocialProfile?> findProfileByExactHandle(String handle);
  Future<String?> followStatus(String targetUid);
  Future<String> toggleFollow(SocialProfile target);
  Future<List<SocialFollowRequest>> pendingFollowRequests();
  Future<void> acceptFollowRequest(String requesterUid);
  Future<void> rejectFollowRequest(String requesterUid);
  Future<String> currentVisibility();
  Future<void> updateCurrentVisibility(String visibility);
  Stream<Set<String>> watchLikes(SocialPost post);
  Stream<List<SocialComment>> watchComments(SocialPost post);
  Future<void> toggleLike(SocialPost post, bool liked);
  Future<void> addComment(SocialPost post, String text);
  Future<void> createPost({required String caption, required List<SocialMediaFile> media});
  Future<String> signedMediaUrl(SocialPost post, SocialMediaItem media);
}

/// Pure helpers keep public-index policy explicit and unit-testable.
class SocialVisibilityPolicy {
  static String normalize(Object? visibility) => visibility == 'public' ? 'public' : 'private';

  static bool shouldIndexPost(String visibility) => normalize(visibility) == 'public';

  static Map<String, Object?>? publicPostEntry(String visibility, Map<String, Object?> post) =>
      shouldIndexPost(visibility) ? post : null;

  static Map<String, Object?> publicPostIndexChanges(
      String uid, Map<String, Map<String, Object?>> posts, String visibility) => {
        for (final entry in posts.entries)
          'publicFeed/${publicFeedKey(uid, entry.key)}': publicPostEntry(visibility, entry.value),
      };

  static String publicFeedKey(String uid, String postId) => '${uid}_$postId';
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

/// Uses the deployed private-media function and authenticated Social RTDB paths.
class FirebaseSocialService implements SocialService {
  FirebaseSocialService({FirebaseAuth? auth, FirebaseDatabase? database, http.Client? client,
    String? supabaseUrl, String? publishableKey, TusUploadSessionStore? tusSessions})
      : _auth = auth ?? FirebaseAuth.instance,
        _database = database ?? FirebaseDatabase.instance,
        _http = client ?? http.Client(),
        _supabaseUrl = supabaseUrl ?? _defaultSupabaseUrl,
        _publishableKey = publishableKey ?? _defaultPublishableKey,
        _tusSessionsOverride = tusSessions;

  static const _defaultSupabaseUrl = String.fromEnvironment('SUPABASE_PROJECT_URL');
  static const _defaultPublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final FirebaseAuth _auth;
  final FirebaseDatabase _database;
  final http.Client _http;
  final String _supabaseUrl;
  final String _publishableKey;
  final TusUploadSessionStore? _tusSessionsOverride;
  late final Future<TusUploadSessionStore> _tusSessions =
      _tusSessionsOverride == null
          ? Future<TusUploadSessionStore>.value(TusUploadSessionStore.appPrivate())
          : Future<TusUploadSessionStore>.value(_tusSessionsOverride);

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

  /// Resolve one explicitly entered handle only; never enumerate the directory or
  /// expose profile records by prefix search. The existing Kotlin directory uses
  /// usernameLower as its exact child key.
  @override
  Future<SocialProfile?> findProfileByExactHandle(String handle) async {
    final normalized = handle.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(normalized)) return null;
    try {
      final snapshot = await _social.child('directory/$normalized').get();
      for (final entry in snapshot.children) {
        final raw = entry.value;
        if (raw is! Map) continue;
        final values = Map<Object?, Object?>.from(raw);
        final uid = values['uid'];
        final username = values['username'];
        final usernameLower = values['usernameLower'];
        final visibility = values['visibility'];
        if (uid is! String || uid.isEmpty || uid != entry.key || username is! String ||
            username.toLowerCase() != normalized || usernameLower != normalized ||
            (visibility != 'public' && visibility != 'private')) continue;
        if (uid == _user().uid) return null;
        return SocialProfile(uid: uid, username: username,
            displayName: values['displayName'] is String ? values['displayName'] as String : 'Usuario',
            visibility: visibility as String);
      }
    } catch (_) {
      // Never fall back to a broad directory read if exact lookup is denied.
    }
    return null;
  }

  @override
  Future<String?> followStatus(String targetUid) async {
    final uid = _user().uid;
    final value = await _social.child('following/$uid/$targetUid/status').get();
    final status = value.value is String ? value.value as String : null;
    if (status != 'pending') return status;
    // Approvals are written by the target under followers/{target}/{requester};
    // the requester cannot update its own following node on the target's behalf.
    try {
      final accepted = await _social.child('followers/$targetUid/$uid/status').get();
      if (accepted.value == 'accepted') {
        // The profile owner is authoritative for this transition; mirror it in
        // the requester's own following index, matching native Social behavior.
        await _social.child('following/$uid/$targetUid/status').set('accepted');
        return 'accepted';
      }
    } catch (_) {
      // A denied read never grants access; continue to the requester-visible request.
    }
    try {
      final request = await _social.child('followRequests/$targetUid/$uid/status').get();
      if (request.value == 'rejected') {
        await _social.child('following/$uid/$targetUid').remove();
        return null;
      }
    } catch (_) {
      // Preserve the pending status when request state is unavailable.
    }
    return status;
  }

  @override
  Future<String> toggleFollow(SocialProfile target) async {
    final user = _user();
    if (target.uid == user.uid) throw StateError('No puedes seguir tu propio perfil.');
    final current = await followStatus(target.uid);
    if (current == 'accepted' || current == 'pending') {
      await _social.update({
        'following/${user.uid}/${target.uid}': null,
        'followers/${target.uid}/${user.uid}': null,
        'followRequests/${target.uid}/${user.uid}': null,
      });
      return '';
    }
    final now = ServerValue.timestamp;
    if (target.isPrivate) {
      await _social.update({
        'following/${user.uid}/${target.uid}': {'status': 'pending', 'createdAt': now},
        'followRequests/${target.uid}/${user.uid}': {
          'requesterUid': user.uid,
          'username': (user.displayName ?? user.email?.split('@').first ?? 'usuario').toLowerCase(),
          'displayName': user.displayName ?? user.email?.split('@').first ?? 'Usuario',
          'status': 'pending',
          'createdAt': now,
        },
      });
      return 'pending';
    }
    final relation = {'status': 'accepted', 'createdAt': now};
    await _social.update({
      'following/${user.uid}/${target.uid}': relation,
      'followers/${target.uid}/${user.uid}': relation,
      'followRequests/${target.uid}/${user.uid}': null,
    });
    return 'accepted';
  }

  @override
  Future<String> currentVisibility() async {
    final uid = _user().uid;
    final profile = await _social.child('profiles/$uid').get();
    return SocialVisibilityPolicy.normalize(profile.child('visibility').value);
  }

  @override
  Future<void> updateCurrentVisibility(String visibility) async {
    final user = _user();
    final uid = user.uid;
    final normalized = SocialVisibilityPolicy.normalize(visibility);
    final profileRef = _social.child('profiles/$uid');
    final profileSnapshot = await profileRef.get();
    final raw = profileSnapshot.value;
    final profile = raw is Map
        ? Map<String, Object?>.from(raw.map((key, value) => MapEntry('$key', value)))
        : <String, Object?>{};
    var username = (profile['username'] as String?)?.trim().replaceFirst(RegExp(r'^@'), '');
    if (username == null || !RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(username)) {
      username = await _availableUsername(_defaultUsername(user, uid), uid);
    }
    final displayName = (profile['displayName'] as String?)?.trim().isNotEmpty == true
        ? (profile['displayName'] as String).trim()
        : (user.displayName ?? user.email?.split('@').first ?? 'Usuario');
    profile['uid'] = uid;
    profile['username'] = username;
    profile['displayName'] = displayName;
    profile['visibility'] = normalized;
    profile['createdAt'] ??= DateTime.now().millisecondsSinceEpoch;

    final directoryEntry = <String, Object?>{
      'uid': uid,
      'username': username,
      'usernameLower': username.toLowerCase(),
      'displayName': displayName,
      'visibility': normalized,
      'updatedAt': ServerValue.timestamp,
      if (normalized == 'public' && profile['avatarUrl'] is String && (profile['avatarUrl'] as String).isNotEmpty)
        'avatarUrl': profile['avatarUrl'],
    };
    final currentUsernameValue = profileSnapshot.child('username').value;
    final currentUsername = currentUsernameValue is String ? currentUsernameValue.toLowerCase() : null;
    final directoryPath = 'directory/${username.toLowerCase()}/$uid';
    final posts = await _posts.get();
    final indexedPosts = <String, Map<String, Object?>>{};
    for (final child in posts.children) {
      final postId = child.key;
      final value = child.value;
      if (postId == null || value is! Map) continue;
      final post = Map<String, Object?>.from(value.map((key, item) => MapEntry('$key', item)))
        ..['ownerUid'] = uid
        ..['id'] = postId
        ..['username'] = username
        ..['displayName'] = displayName;
      indexedPosts[postId] = post;
    }

    final storySnapshot = await _social.child('storiesByUser/$uid').get();
    final indexedStories = storySnapshot.children
        .where((story) => story.key != null && story.value is Map)
        .map((story) {
          final id = story.key!;
          final values = Map<String, Object?>.from(
              (story.value as Map).map((key, item) => MapEntry('$key', item)))
            ..['ownerUid'] = uid
            ..['id'] = id
            ..['username'] = username
            ..['displayName'] = displayName
            ..['avatarUrl'] = profile['avatarUrl'] ?? '';
          return MapEntry(id, values);
        }).toList();

    if (normalized == 'private') {
      // RTDB multi-location update makes the privacy downgrade and all public
      // index removals atomic. Delete rules authorize each own index by ownerUid.
      final changes = <String, Object?>{
        'profiles/$uid': profile,
        directoryPath: directoryEntry,
        for (final entry in indexedPosts.entries) 'postsByUser/$uid/${entry.key}': entry.value,
        for (final entry in indexedStories) 'storiesByUser/$uid/${entry.key}': entry.value,
      };
      if (currentUsername != null && currentUsername != username.toLowerCase()) {
        final oldDirectory = await _social.child('directory/$currentUsername/$uid').get();
        if (oldDirectory.exists) changes['directory/$currentUsername/$uid'] = null;
      }
      for (final entry in indexedPosts.entries) {
        final feedPath = 'publicFeed/${SocialVisibilityPolicy.publicFeedKey(uid, entry.key)}';
        if ((await _social.child(feedPath).get()).exists) changes[feedPath] = null;
      }
      for (final entry in indexedStories) {
        final storyPath = 'publicStories/${uid}_${entry.key}';
        if ((await _social.child(storyPath).get()).exists) changes[storyPath] = null;
      }
      await _social.update(changes);
    } else {
      await profileRef.set(profile);
      await _social.child(directoryPath).set(directoryEntry);
      for (final entry in indexedPosts.entries) {
        await _posts.child(entry.key).set(entry.value);
      }
      for (final entry in indexedStories) {
        await _social.child('storiesByUser/$uid/${entry.key}').set(entry.value);
      }
      if (currentUsername != null && currentUsername != username.toLowerCase()) {
        await _social.child('directory/$currentUsername/$uid').remove();
      }
      final postIndexChanges = SocialVisibilityPolicy.publicPostIndexChanges(uid, indexedPosts, normalized);
      if (postIndexChanges.isNotEmpty) await _social.update(postIndexChanges);
      for (final entry in indexedStories) {
        await _social.child('publicStories/${uid}_${entry.key}').set(entry.value);
      }
    }
  }

  String _defaultUsername(User user, String uid) {
    final base = (user.email?.split('@').first ?? 'usuario').toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    final safeBase = base.length < 3 ? 'usuario' : base.substring(0, base.length.clamp(3, 15).toInt());
    return '${safeBase}_${uid.substring(uid.length > 4 ? uid.length - 4 : 0).toLowerCase()}';
  }

  Future<String> _availableUsername(String requested, String uid) async {
    final clean = requested.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    final base = clean.substring(0, clean.length.clamp(3, 20).toInt());
    for (var attempt = 1; attempt <= 999; attempt++) {
      final suffix = attempt == 1 ? '' : '_$attempt';
      final candidate = '${base.substring(0, (20 - suffix.length).clamp(3, base.length).toInt())}$suffix';
      final occupants = await _social.child('directory/$candidate').get();
      if (!occupants.children.any((child) => child.key != uid)) return candidate;
    }
    throw StateError('No se pudo preparar el nombre de usuario.');
  }

  @override
  Future<List<SocialFollowRequest>> pendingFollowRequests() async {
    final snapshot = await _social.child('followRequests/${_user().uid}').get();
    return snapshot.children.where((request) => request.child('status').value == 'pending').map((request) {
      final raw = request.value;
      final values = raw is Map ? Map<Object?, Object?>.from(raw) : <Object?, Object?>{};
      return SocialFollowRequest(uid: request.key ?? '',
        username: values['username'] is String ? values['username'] as String : '',
        displayName: values['displayName'] is String ? values['displayName'] as String : 'Usuario');
    }).where((request) => request.uid.isNotEmpty).toList();
  }

  @override
  Future<void> acceptFollowRequest(String requesterUid) async {
    final uid = _user().uid;
    final request = _social.child('followRequests/$uid/$requesterUid');
    final current = await request.get();
    if (current.child('status').value != 'pending') throw StateError('La solicitud ya no está pendiente.');
    await _social.child('followers/$uid/$requesterUid').set({'status': 'accepted', 'createdAt': ServerValue.timestamp});
    await request.child('status').set('accepted');
  }

  @override
  Future<void> rejectFollowRequest(String requesterUid) async {
    final uid = _user().uid;
    final request = _social.child('followRequests/$uid/$requesterUid');
    final current = await request.get();
    if (current.child('status').value != 'pending') throw StateError('La solicitud ya no está pendiente.');
    await request.child('status').set('rejected');
  }

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
        final baseUri = Uri.parse(_supabaseUrl);
        final projectId = baseUri.host.split('.').first;
        final tusEndpoint = Uri.https('$projectId.storage.supabase.co', '/storage/v1/upload/resumable');
        final uploader = SupabaseTusUploader(client: _http, sessions: await _tusSessions, publishableKey: _publishableKey);
        final session = await uploader.upload(
          source: source,
          mimeType: mime,
          endpoint: tusEndpoint,
          bucket: 'social-test-media',
          createSignedSession: () async {
            final prepared = await _callFunction(token, {
              'action': 'create-upload', 'entityType': 'post', 'mimeType': mime,
            });
            final path = prepared['storagePath'] as String?;
            final signedToken = prepared['token'] as String?;
            if (path == null || path.isEmpty || signedToken == null || signedToken.isEmpty) {
              throw StateError('No se pudo preparar la carga privada.');
            }
            return TusUploadSession(storagePath: path, signedToken: signedToken);
          },
          onStoragePath: (storagePath) {
            if (!uploaded.contains(storagePath)) uploaded.add(storagePath);
          },
        );
        mediaItems.add(SocialMediaItem(path: session.storagePath, mimeType: mime));
      }

      postRef = _posts.push();
      final id = postRef.key;
      if (id == null) throw StateError('No se pudo crear la publicación.');
      final videos = mediaItems.where((item) => item.isVideo).toList();
      final primary = videos.isNotEmpty ? videos.first : (mediaItems.isEmpty ? null : mediaItems.first);
      final profileSnapshot = await _social.child('profiles/${user.uid}').get();
      final visibility = SocialVisibilityPolicy.normalize(profileSnapshot.child('visibility').value);
      final username = profileSnapshot.child('username').value is String
          ? profileSnapshot.child('username').value as String
          : user.email?.split('@').first ?? 'usuario';
      final displayName = profileSnapshot.child('displayName').value is String
          ? profileSnapshot.child('displayName').value as String
          : user.displayName ?? username;
      final avatarUrl = profileSnapshot.child('avatarUrl').value is String
          ? profileSnapshot.child('avatarUrl').value as String
          : '';
      final postData = <String, Object?>{
        'id': id,
        'ownerUid': user.uid,
        'username': username,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'caption': caption.trim(),
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'topics': <String, bool>{},
        'mediaPath': primary?.path ?? '',
        'mediaType': primary == null ? '' : (primary.isVideo ? 'video' : 'image'),
        if (mediaItems.isNotEmpty) 'mediaItems': mediaItems.map((item) => item.toMap()).toList(),
      };
      await postRef.set(postData);
      final publicEntry = SocialVisibilityPolicy.publicPostEntry(visibility, postData);
      if (publicEntry != null) {
        await _social.child('publicFeed/${SocialVisibilityPolicy.publicFeedKey(user.uid, id)}').set(publicEntry);
      }
    } catch (_) {
      if (postRef != null) {
        try {
          final postId = postRef.key;
          if (postId != null) {
            await _social.child('publicFeed/${SocialVisibilityPolicy.publicFeedKey(user.uid, postId)}').remove();
          }
          await postRef.remove();
        } catch (_) { /* best effort */ }
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
