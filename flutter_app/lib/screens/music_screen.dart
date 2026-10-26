import 'package:flutter/material.dart';

import 'package:beta_app/models/music_item.dart';
import 'package:beta_app/services/music_service.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  final MusicService _service = MusicService();
  late final List<MusicItem> _tracks = _service.tracks;
  Set<String> _favoriteIds = <String>{};
  MusicItem? _selectedTrack;
  bool _showFavoritesOnly = false;
  bool _favoritesLoaded = false;

  @override
  void initState() {
    super.initState();
    _selectedTrack = _tracks.isEmpty ? null : _tracks.first;
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final favorites = await _service.loadFavorites();
    if (!mounted) return;
    setState(() {
      _favoriteIds = favorites;
      _favoritesLoaded = true;
    });
  }

  Future<void> _toggleFavorite(MusicItem track) async {
    final next = Set<String>.from(_favoriteIds);
    if (!next.add(track.id)) next.remove(track.id);
    setState(() => _favoriteIds = next);
    try {
      await _service.saveFavorites(next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron guardar los favoritos en este dispositivo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleTracks = _showFavoritesOnly
        ? _tracks.where((track) => _favoriteIds.contains(track.id)).toList()
        : _tracks;
    final selected = _selectedTrack;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Music'),
        actions: [
          IconButton(
            key: const Key('toggle-favorites-filter'),
            tooltip: _showFavoritesOnly ? 'Mostrar toda la biblioteca' : 'Mostrar favoritos',
            icon: Icon(_showFavoritesOnly ? Icons.library_music : Icons.favorite),
            onPressed: () => setState(() => _showFavoritesOnly = !_showFavoritesOnly),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Biblioteca', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Selecciona una pista o guárdala en tus favoritos. La reproducción aún no está conectada.'),
              const SizedBox(height: 14),
              if (selected != null)
                Card(
                  key: const Key('selected-track'),
                  child: ListTile(
                    leading: const Icon(Icons.music_note, color: Colors.deepPurple, size: 34),
                    title: Text(selected.title),
                    subtitle: Text('${selected.artist} · ${selected.duration}'),
                    trailing: IconButton(
                      key: const Key('selected-track-favorite'),
                      tooltip: _favoriteIds.contains(selected.id) ? 'Quitar de favoritos' : 'Añadir a favoritos',
                      icon: Icon(
                        _favoriteIds.contains(selected.id) ? Icons.favorite : Icons.favorite_border,
                        color: _favoriteIds.contains(selected.id) ? Colors.red : null,
                      ),
                      onPressed: () => _toggleFavorite(selected),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text(_showFavoritesOnly ? 'Favoritos' : 'Todas las pistas', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: !_favoritesLoaded
                    ? const Center(child: CircularProgressIndicator())
                    : visibleTracks.isEmpty
                        ? const Center(child: Text('Todavía no tienes pistas favoritas.'))
                        : ListView.builder(
                            itemCount: visibleTracks.length,
                            itemBuilder: (context, index) {
                              final track = visibleTracks[index];
                              final isSelected = track.id == selected?.id;
                              final isFavorite = _favoriteIds.contains(track.id);
                              return ListTile(
                                key: Key('track-${track.id}'),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.deepPurple.withValues(alpha: 0.12),
                                  child: const Icon(Icons.music_note, color: Colors.deepPurple),
                                ),
                                title: Text(track.title),
                                subtitle: Text('${track.artist} · ${track.duration}'),
                                selected: isSelected,
                                trailing: IconButton(
                                  key: Key('favorite-${track.id}'),
                                  tooltip: isFavorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
                                  icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? Colors.red : null),
                                  onPressed: () => _toggleFavorite(track),
                                ),
                                onTap: () => setState(() => _selectedTrack = track),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
