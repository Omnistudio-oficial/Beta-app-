import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:video_player/video_player.dart';

import 'package:beta_app/social/social_repository.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key, this.service});
  final SocialService? service;

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  late final SocialService _service = widget.service ?? FirebaseSocialService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _caption = TextEditingController();
  final TextEditingController _exactHandle = TextEditingController();
  final List<SocialMediaFile> _selected = [];
  String? _pickerError;
  bool _posting = false;
  bool _showPublicFeed = true;
  bool _lookupBusy = false;
  SocialProfile? _lookupProfile;
  String? _lookupError;
  List<SocialFollowRequest> _followRequests = const [];
  bool _requestsLoaded = false;

  @override
  void dispose() {
    _caption.dispose();
    _exactHandle.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    setState(() => _pickerError = null);
    try {
      final files = await _picker.pickMultipleMedia(imageQuality: 90);
      if (!mounted || files.isEmpty) return;
      final pending = <SocialMediaFile>[];
      for (final file in files) {
        final mime = file.mimeType ?? lookupMimeType(file.name) ?? 'application/octet-stream';
        pending.add(SocialMediaFile(path: file.path, mimeType: mime, name: file.name));
      }
      final candidate = [..._selected, ...pending];
      final validation = SocialPostValidation.validate(caption: _caption.text, media: candidate);
      if (validation != null && candidate.length > socialMaxMediaItems) {
        setState(() => _pickerError = 'Puedes seleccionar hasta cinco archivos por publicación.');
        return;
      }
      final unsupported = pending.firstWhereOrNull((file) => !socialSupportedMimeTypes.contains(file.mimeType.toLowerCase().split(';').first));
      if (unsupported != null) {
        setState(() => _pickerError = 'No se admite ${unsupported.name}. Elige una foto o video compatible.');
        return;
      }
      setState(() => _selected.addAll(pending));
    } catch (_) {
      if (mounted) setState(() => _pickerError = 'No se pudo abrir el selector de fotos y videos.');
    }
  }

  Future<void> _lookupExactHandle() async {
    setState(() { _lookupBusy = true; _lookupProfile = null; _lookupError = null; });
    try {
      final profile = await _service.findProfileByExactHandle(_exactHandle.text);
      if (!mounted) return;
      setState(() {
        _lookupProfile = profile;
        if (profile == null) _lookupError = 'No se encontró una cuenta para ese handle exacto.';
      });
    } catch (_) {
      if (mounted) setState(() => _lookupError = 'No se pudo consultar ese handle. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _lookupBusy = false);
    }
  }

  Future<void> _loadFollowRequests() async {
    try {
      final requests = await _service.pendingFollowRequests();
      if (mounted) setState(() { _followRequests = requests; _requestsLoaded = true; });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudieron cargar las solicitudes.')));
    }
  }

  Future<void> _resolveRequest(SocialFollowRequest request, {required bool accept}) async {
    try {
      if (accept) { await _service.acceptFollowRequest(request.uid); }
      else { await _service.rejectFollowRequest(request.uid); }
      await _loadFollowRequests();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo actualizar la solicitud.')));
    }
  }

  Future<void> _publish() async {
    final validation = SocialPostValidation.validate(caption: _caption.text, media: _selected);
    if (validation != null) {
      setState(() => _pickerError = validation);
      return;
    }
    setState(() { _posting = true; _pickerError = null; });
    try {
      await _service.createPost(caption: _caption.text, media: List.of(_selected));
      if (!mounted) return;
      _caption.clear();
      setState(_selected.clear);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Publicación sincronizada con tu cuenta')));
    } catch (error) {
      if (mounted) setState(() => _pickerError = _safeError(error));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  String _safeError(Object error) {
    if (error is ArgumentError || error is StateError) return error.toString().replaceFirst(RegExp(r'^(Invalid argument\(s\): |Bad state: )'), '');
    return 'No se pudo sincronizar la publicación. Comprueba tu conexión e inténtalo de nuevo.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Social')),
        body: SafeArea(
          child: StreamBuilder<List<SocialPost>>(
            stream: _service.watchMyPosts(),
            builder: (context, snapshot) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Buscar una cuenta por su handle exacto', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: TextField(
                      key: const ValueKey('social-exact-handle'), controller: _exactHandle,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(hintText: '@usuario', border: OutlineInputBorder(), isDense: true),
                      onSubmitted: (_) => _lookupExactHandle(),
                    )),
                    IconButton(
                      tooltip: 'Buscar handle exacto',
                      onPressed: _lookupBusy ? null : _lookupExactHandle,
                      icon: _lookupBusy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
                    ),
                  ]),
                  const Text('Solo se consulta el handle escrito; Social no muestra una lista de cuentas no solicitada.'),
                  if (_lookupError != null) Text(_lookupError!, key: const ValueKey('social-profile-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  if (_lookupProfile != null) _FollowProfileCard(profile: _lookupProfile!, service: _service),
                  const SizedBox(height: 16),
                  Row(children: [
                    const Expanded(child: Text('Feed público', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                    Semantics(label: 'Mostrar feed público', child: Switch(value: _showPublicFeed, onChanged: (value) => setState(() => _showPublicFeed = value))),
                  ]),
                  if (!_requestsLoaded)
                    Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                      key: const ValueKey('social-load-follow-requests'),
                      onPressed: _loadFollowRequests,
                      icon: const Icon(Icons.person_add_alt_1), label: const Text('Revisar solicitudes de seguimiento'),
                    ))
                  else if (_followRequests.isNotEmpty)
                    Card(child: Column(children: [
                      const ListTile(title: Text('Solicitudes de seguimiento')),
                      for (final request in _followRequests) ListTile(
                        title: Text(request.displayName), subtitle: Text('@${request.username}'),
                        trailing: Wrap(children: [
                          IconButton(tooltip: 'Aceptar solicitud ${request.username}', onPressed: () => _resolveRequest(request, accept: true), icon: const Icon(Icons.check)),
                          IconButton(tooltip: 'Rechazar solicitud ${request.username}', onPressed: () => _resolveRequest(request, accept: false), icon: const Icon(Icons.close)),
                        ]),
                      ),
                    ]))
                  else
                    const Text('No tienes solicitudes pendientes.'),
                  if (_showPublicFeed) StreamBuilder<List<SocialPost>>(
                    stream: _service.watchPublicFeed(),
                    builder: (context, feed) {
                      if (feed.hasError) return const Card(child: ListTile(title: Text('No se pudo cargar el feed público.')));
                      if (feed.connectionState == ConnectionState.waiting && !feed.hasData) return const Center(child: CircularProgressIndicator());
                      final posts = feed.data ?? const <SocialPost>[];
                      if (posts.isEmpty) return const Card(child: ListTile(title: Text('El feed público está vacío.')));
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        for (final post in posts) _PublicPostCard(post: post, service: _service),
                      ]);
                    },
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const Text('Publica en tu cuenta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        const Text('Tus publicaciones se sincronizan con tu cuenta y permanecen privadas por defecto. No se publican en el feed público.'),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _caption,
                          maxLength: socialMaxCaptionLength,
                          maxLines: 4,
                          minLines: 2,
                          key: const ValueKey('social-caption'),
                          decoration: const InputDecoration(labelText: 'Escribe algo', border: OutlineInputBorder()),
                        ),
                        if (_selected.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (var index = 0; index < _selected.length; index++)
                              _SelectedMediaChip(file: _selected[index], onRemove: () => setState(() => _selected.removeAt(index))),
                          ]),
                        ],
                        if (_pickerError != null) ...[
                          const SizedBox(height: 8),
                          Text(_pickerError!, style: TextStyle(color: Theme.of(context).colorScheme.error), key: const ValueKey('social-error')),
                        ],
                        const SizedBox(height: 8),
                        Row(children: [
                          OutlinedButton.icon(
                            onPressed: _posting ? null : _pickMedia,
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                            label: const Text('Fotos o videos'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _posting ? null : _publish,
                            icon: _posting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload_outlined),
                            label: const Text('Publicar'),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        const Text('Máximo 5 archivos; cada uno hasta 50 MiB. Fotos y videos compatibles.'),
                      ]),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 20, 4, 8),
                    child: Text('Mis publicaciones sincronizadas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  if (snapshot.hasError)
                    const Card(child: ListTile(leading: Icon(Icons.cloud_off), title: Text('No se pudieron cargar tus publicaciones.')))
                  else if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData)
                    const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                  else if ((snapshot.data ?? []).isEmpty)
                    const Card(child: ListTile(title: Text('Aún no tienes publicaciones sincronizadas.')))
                  else
                    for (final post in snapshot.data!) _PostCard(post: post, service: _service),
                ],
              );
            },
          ),
        ),
      );
}

class _FollowProfileCard extends StatefulWidget {
  const _FollowProfileCard({required this.profile, required this.service});
  final SocialProfile profile;
  final SocialService service;
  @override
  State<_FollowProfileCard> createState() => _FollowProfileCardState();
}

class _FollowProfileCardState extends State<_FollowProfileCard> {
  late Future<String?> _status = widget.service.followStatus(widget.profile.uid);
  bool _busy = false;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      final status = await widget.service.toggleFollow(widget.profile);
      if (mounted) setState(() => _status = Future.value(status));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo actualizar el seguimiento. Inténtalo de nuevo.')));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _status,
    builder: (context, snapshot) {
      final status = snapshot.data;
      final label = status == 'accepted' ? 'Dejar de seguir' : status == 'pending' ? 'Cancelar solicitud' : 'Seguir';
      return Card(key: ValueKey('follow-profile-${widget.profile.uid}'), child: ListTile(
        title: Text(widget.profile.displayName), subtitle: Text('@${widget.profile.username}${widget.profile.isPrivate ? ' · Cuenta privada' : ' · Cuenta pública'}'),
        trailing: TextButton(onPressed: _busy || snapshot.hasError || snapshot.connectionState == ConnectionState.waiting ? null : _toggle,
          child: Text(_busy ? 'Actualizando…' : label)),
      ));
    },
  );
}

class _PublicPostCard extends StatefulWidget {
  const _PublicPostCard({required this.post, required this.service});
  final SocialPost post;
  final SocialService service;
  @override
  State<_PublicPostCard> createState() => _PublicPostCardState();
}

class _PublicPostCardState extends State<_PublicPostCard> {
  final TextEditingController _comment = TextEditingController();
  bool _sending = false;
  @override
  void dispose() { _comment.dispose(); super.dispose(); }

  Future<void> _sendComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty || text.length > 1000) return;
    setState(() => _sending = true);
    try {
      await widget.service.addComment(widget.post, text);
      if (mounted) _comment.clear();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo publicar el comentario. Puede que el perfil o la publicación ya no permitan interacción.')));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: widget.service.canInteract(widget.post),
    builder: (context, permission) => _buildCard(context, permission.data == true),
  );

  Widget _buildCard(BuildContext context, bool allowed) {
    final post = widget.post;
    return Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!allowed) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Solo lectura; el perfil no permite interacciones para esta cuenta.')),
      Text(post.displayName.isEmpty ? (post.username.isEmpty ? 'Usuario' : '@${post.username}') : post.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
      if (post.ownerUid != widget.service.currentUid && post.username.isNotEmpty)
        _FollowProfileCard(profile: SocialProfile(uid: post.ownerUid, username: post.username, displayName: post.displayName.isEmpty ? post.username : post.displayName, visibility: 'public'), service: widget.service),
      Text(DateTime.fromMillisecondsSinceEpoch(post.createdAt).toLocal().toString().substring(0, 16), style: Theme.of(context).textTheme.labelSmall),
      if (post.caption.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(post.caption)),
      if (post.mediaItems.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Esta publicación incluye contenido multimedia; la vista segura de medios públicos aún no está disponible.')),
      if (allowed) ...[
        StreamBuilder<Set<String>>(stream: widget.service.watchLikes(post), builder: (context, snapshot) {
          final likes = snapshot.data ?? const <String>{};
          final liked = likes.contains(widget.service.currentUid);
          return Row(children: [IconButton(tooltip: liked ? 'Quitar Me gusta' : 'Me gusta', onPressed: () async {
            try { await widget.service.toggleLike(post, !liked); } catch (_) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo actualizar Me gusta. Revisa si el autor permite interacciones.')));
            }
          }, icon: Icon(liked ? Icons.favorite : Icons.favorite_border)), Text('${likes.length}')]);
        }),
        StreamBuilder<List<SocialComment>>(stream: widget.service.watchComments(post), builder: (context, snapshot) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final comment in (snapshot.data ?? const <SocialComment>[])) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('${comment.authorName}: ${comment.text}')),
        ])),
        Row(children: [Expanded(child: TextField(key: const ValueKey('social-comment'), controller: _comment, maxLength: 1000, decoration: const InputDecoration(hintText: 'Escribe un comentario', counterText: ''))), IconButton(onPressed: _sending ? null : _sendComment, icon: const Icon(Icons.send))]),
      ],
    ])));
  }
}

class _SelectedMediaChip extends StatelessWidget {
  const _SelectedMediaChip({required this.file, required this.onRemove});
  final SocialMediaFile file;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => InputChip(
        avatar: Icon(file.mimeType.startsWith('video/') ? Icons.videocam_outlined : Icons.image_outlined, size: 18),
        label: SizedBox(width: 110, child: Text(file.name, overflow: TextOverflow.ellipsis)),
        onDeleted: onRemove,
      );
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.service});
  final SocialPost post;
  final SocialService service;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(DateTime.fromMillisecondsSinceEpoch(post.createdAt).toLocal().toString().substring(0, 16), style: Theme.of(context).textTheme.labelSmall),
            if (post.caption.isNotEmpty) ...[const SizedBox(height: 8), SelectableText(post.caption)],
            for (final item in post.mediaItems)
              Padding(padding: const EdgeInsets.only(top: 10), child: _PrivateMedia(post: post, media: item, service: service)),
          ]),
        ),
      );
}

class _PrivateMedia extends StatelessWidget {
  const _PrivateMedia({required this.post, required this.media, required this.service});
  final SocialPost post;
  final SocialMediaItem media;
  final SocialService service;

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: service.signedMediaUrl(post, media),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const ListTile(leading: Icon(Icons.lock_outline), title: Text('No se pudo cargar el archivo privado.'));
          if (!snapshot.hasData) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
          final uri = Uri.tryParse(snapshot.data!);
          if (uri == null) return const Text('Archivo privado no disponible.');
          return media.isVideo ? _VideoMedia(uri: uri) : ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(uri.toString(), fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox(height: 100, child: Center(child: Text('No se pudo mostrar la foto.')))),
          );
        },
      );
}

class _VideoMedia extends StatefulWidget {
  const _VideoMedia({required this.uri});
  final Uri uri;
  @override
  State<_VideoMedia> createState() => _VideoMediaState();
}

class _VideoMediaState extends State<_VideoMedia> {
  late final VideoPlayerController _controller = VideoPlayerController.networkUrl(widget.uri);
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _controller.initialize().then((_) { if (mounted) setState(() {}); }).catchError((_) { if (mounted) setState(() => _failed = true); });
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox(height: 120, child: Center(child: Text('No se pudo reproducir el video.')));
    if (!_controller.value.isInitialized) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    return Column(children: [
      AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)),
      IconButton(
        tooltip: _controller.value.isPlaying ? 'Pausar video' : 'Reproducir video',
        onPressed: () => setState(() => _controller.value.isPlaying ? _controller.pause() : _controller.play()),
        icon: Icon(_controller.value.isPlaying ? Icons.pause_circle : Icons.play_circle, size: 36),
      ),
    ]);
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final item in this) { if (test(item)) return item; }
    return null;
  }
}
