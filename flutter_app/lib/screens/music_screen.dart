import 'package:beta_app/models/music_item.dart';
import 'package:beta_app/services/music_service.dart';
import 'package:flutter/material.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key, this.workspace});
  final MusicWorkspace? workspace;
  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  late final MusicWorkspace _service = widget.workspace ?? MusicService();
  Set<String> _favoriteIds = <String>{};
  MusicItem? _selectedTrack;
  bool _showFavoritesOnly = false;
  bool _favoritesLoaded = false;
  bool _recording = false;
  bool _playing = false;
  bool _busy = false;
  List<AudioProject> _projects = const [];

  @override
  void initState() {
    super.initState();
    final existingTracks = _service.tracks;
    _selectedTrack = existingTracks.isEmpty ? null : existingTracks.first;
    _loadFavorites();
    _loadProjects();
  }
  Future<void> _loadProjects() async {
    try { final projects = await _service.loadProjects(); if (mounted) setState(() => _projects = projects); } catch (_) { /* unavailable while signed out/offline */ }
  }
  @override
  void dispose() { _service.dispose(); super.dispose(); }

  Future<void> _loadFavorites() async {
    final favorites = await _service.loadFavorites();
    if (!mounted) return;
    setState(() { _favoriteIds = favorites; _favoritesLoaded = true; });
  }
  void _message(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  Future<void> _toggleFavorite(MusicItem track) async {
    final next = Set<String>.from(_favoriteIds);
    if (!next.add(track.id)) next.remove(track.id);
    setState(() => _favoriteIds = next);
    try { await _service.saveFavorites(next); } catch (_) { _message('No se pudieron guardar los favoritos en este dispositivo.'); }
  }
  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try { await action(); if (success != null) _message(success); if (success == 'Proyecto guardado en tu cuenta.') await _loadProjects(); }
    catch (e) { _message(e.toString().replaceFirst('Bad state: ', '')); }
    finally { if (mounted) setState(() { _busy = false; _recording = _service.isRecording; _playing = _service.isPlaying; }); }
  }
  Future<void> _saveProject(MusicItem track) async {
    final controller = TextEditingController(text: track.title);
    final title = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Guardar proyecto'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre del proyecto')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Guardar'))],
    ));
    controller.dispose();
    if (title == null) return;
    await _run(() => _service.saveProject(title, track), success: 'Proyecto guardado en tu cuenta.');
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _service.tracks;
    final visibleTracks = _showFavoritesOnly ? tracks.where((t) => _favoriteIds.contains(t.id)).toList() : tracks;
    final selected = _selectedTrack;
    return Scaffold(
      appBar: AppBar(title: const Text('Music Studio'), actions: [IconButton(key: const Key('toggle-favorites-filter'), tooltip: _showFavoritesOnly ? 'Mostrar toda la biblioteca' : 'Mostrar favoritos', icon: Icon(_showFavoritesOnly ? Icons.library_music : Icons.favorite), onPressed: () => setState(() => _showFavoritesOnly = !_showFavoritesOnly))]),
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Biblioteca', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Reproduce tus archivos de audio, importa una pista o graba una toma.'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(key: const Key('import-audio'), onPressed: _busy ? null : () => _run(_service.importAudio, success: 'Audio importado.'), icon: const Icon(Icons.file_upload), label: const Text('Importar audio')),
          FilledButton.icon(key: const Key('start-recording'), onPressed: (_busy || _recording) ? null : () => _run(_service.startRecording), icon: const Icon(Icons.mic), label: const Text('Grabar')),
          if (_recording) ...[
            FilledButton.icon(key: const Key('stop-recording'), onPressed: _busy ? null : () => _run(() async { await _service.stopRecording(); if (_service.tracks.isNotEmpty) _selectedTrack = _service.tracks.first; }, success: 'Grabación guardada en la biblioteca.'), icon: const Icon(Icons.stop), label: const Text('Detener y guardar')),
            TextButton(key: const Key('cancel-recording'), onPressed: _busy ? null : () => _run(_service.cancelRecording, success: 'Grabación cancelada.'), child: const Text('Cancelar')),
          ],
        ]),
        if (_recording) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Grabando… toca Detener y guardar o Cancelar.')),
        const SizedBox(height: 10),
        if (selected != null) Card(key: const Key('selected-track'), child: ListTile(
          leading: const Icon(Icons.music_note, color: Colors.deepPurple, size: 34),
          title: Text(selected.title), subtitle: Text('${selected.artist} · ${selected.duration}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(key: const Key('play-pause'), tooltip: _playing ? 'Pausar' : 'Reproducir', icon: Icon(_playing ? Icons.pause : Icons.play_arrow), onPressed: _busy ? null : () => _run(() async { if (_playing) { await _service.pause(); } else { await _service.play(selected); } })),
            IconButton(key: const Key('selected-track-favorite'), tooltip: _favoriteIds.contains(selected.id) ? 'Quitar de favoritos' : 'Añadir a favoritos', icon: Icon(_favoriteIds.contains(selected.id) ? Icons.favorite : Icons.favorite_border, color: _favoriteIds.contains(selected.id) ? Colors.red : null), onPressed: () => _toggleFavorite(selected)),
            IconButton(key: const Key('save-project'), tooltip: 'Guardar proyecto', icon: const Icon(Icons.cloud_upload_outlined), onPressed: () => _saveProject(selected)),
          ]),
        )),
        const SizedBox(height: 10),
        if (_projects.isNotEmpty) ...[
          Text('Mis proyectos (${_projects.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 52, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _projects.length, itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(right: 8), child: Chip(key: Key('project-${_projects[index].id}'), avatar: const Icon(Icons.audio_file, size: 18), label: Text(_projects[index].title))))),
        ],
        Text(_showFavoritesOnly ? 'Favoritos' : 'Pistas y tomas', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Expanded(child: !_favoritesLoaded ? const Center(child: CircularProgressIndicator()) : visibleTracks.isEmpty
          ? Center(child: Text(_showFavoritesOnly ? 'Todavía no tienes pistas favoritas.' : 'Tu biblioteca está vacía. Importa un archivo o graba una toma.'))
          : ListView.builder(itemCount: visibleTracks.length, itemBuilder: (context, index) {
            final track = visibleTracks[index];
            return ListTile(key: Key('track-${track.id}'), leading: CircleAvatar(backgroundColor: Colors.deepPurple.withValues(alpha: .12), child: const Icon(Icons.music_note, color: Colors.deepPurple)), title: Text(track.title), subtitle: Text('${track.artist} · ${track.duration}'), selected: track.id == selected?.id,
              trailing: IconButton(key: Key('favorite-${track.id}'), tooltip: _favoriteIds.contains(track.id) ? 'Quitar de favoritos' : 'Añadir a favoritos', icon: Icon(_favoriteIds.contains(track.id) ? Icons.favorite : Icons.favorite_border, color: _favoriteIds.contains(track.id) ? Colors.red : null), onPressed: () => _toggleFavorite(track)),
              onTap: () => setState(() => _selectedTrack = track));
          })),
      ]))),
    );
  }
}
