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
  final List<SocialMediaFile> _selected = [];
  String? _pickerError;
  bool _posting = false;

  @override
  void dispose() {
    _caption.dispose();
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
