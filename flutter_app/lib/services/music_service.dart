import 'package:beta_app/models/music_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MusicService {
  static const _favoritesKey = 'music_favorite_ids';

  final List<MusicItem> _tracks = const [
    MusicItem(
      id: '1',
      title: 'Midnight Drive',
      artist: 'Nova Echo',
      duration: '3:24',
      coverUrl: 'https://picsum.photos/200/200?random=1',
    ),
    MusicItem(
      id: '2',
      title: 'Velvet Horizon',
      artist: 'Aurora Lane',
      duration: '4:10',
      coverUrl: 'https://picsum.photos/200/200?random=2',
    ),
    MusicItem(
      id: '3',
      title: 'City Lights',
      artist: 'The Signal',
      duration: '2:48',
      coverUrl: 'https://picsum.photos/200/200?random=3',
    ),
  ];

  List<MusicItem> get tracks => _tracks;

  Future<Set<String>> loadFavorites() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(_favoritesKey)?.toSet() ?? <String>{};
  }

  Future<void> saveFavorites(Set<String> ids) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_favoritesKey, ids.toList()..sort());
  }
}
