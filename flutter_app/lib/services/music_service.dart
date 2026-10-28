import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:beta_app/models/music_item.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class MusicWorkspace {
  List<MusicItem> get tracks;
  bool get isRecording;
  bool get isPlaying;
  Future<Set<String>> loadFavorites();
  Future<void> saveFavorites(Set<String> ids);
  Future<void> play(MusicItem track);
  Future<void> pause();
  Future<void> importAudio();
  Future<void> startRecording();
  Future<void> stopRecording();
  Future<void> cancelRecording();
  Future<void> saveProject(String title, MusicItem track);
  Future<List<AudioProject>> loadProjects();
  Future<void> dispose();
}

class MusicService implements MusicWorkspace {
  static const _favoritesKey = 'music_favorite_ids';
  MusicService({AudioPlayer? player, AudioRecorder? recorder, FirebaseAuth? auth, FirebaseDatabase? database})
      : _player = player ?? AudioPlayer(),
        _recorder = recorder ?? AudioRecorder(),
        _auth = auth,
        _database = database;

  final AudioPlayer _player;
  final AudioRecorder _recorder;
  final FirebaseAuth? _auth;
  final FirebaseDatabase? _database;
  final List<MusicItem> _tracks = [];
  String? _recordingPath;
  bool _recording = false;
  bool _playing = false;

  @override
  List<MusicItem> get tracks => List.unmodifiable(_tracks);
  @override
  bool get isRecording => _recording;
  @override
  bool get isPlaying => _playing;

  @override
  Future<Set<String>> loadFavorites() async => (await SharedPreferences.getInstance()).getStringList(_favoritesKey)?.toSet() ?? <String>{};
  @override
  Future<void> saveFavorites(Set<String> ids) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_favoritesKey, ids.toList()..sort());
  }

  @override
  Future<void> play(MusicItem track) async {
    final path = track.audioPath;
    if (path == null || !await File(path).exists()) throw StateError('Audio file is unavailable');
    await _player.play(DeviceFileSource(path));
    _playing = true;
  }
  @override
  Future<void> pause() async { await _player.pause(); _playing = false; }

  Future<String> _copyIntoLibrary(String source) async {
    final dir = await getApplicationDocumentsDirectory();
    final library = Directory('${dir.path}/music_library');
    await library.create(recursive: true);
    final ext = source.contains('.') ? source.substring(source.lastIndexOf('.')) : '.m4a';
    final name = '${DateTime.now().microsecondsSinceEpoch}$ext';
    return (await File(source).copy('${library.path}/$name')).path;
  }

  @override
  Future<void> importAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: false, withData: false);
    final selected = result?.files.single;
    if (selected == null) return;
    final path = selected.path;
    if (path == null) return;
    final saved = await _copyIntoLibrary(path);
    _tracks.add(MusicItem(id: 'import-${DateTime.now().microsecondsSinceEpoch}', title: selected.name, artist: 'Importado', duration: '—', audioPath: saved));
  }

  @override
  Future<void> startRecording() async {
    if (!await _recorder.hasPermission()) throw StateError('Microphone permission was not granted');
    final dir = await getApplicationDocumentsDirectory();
    final library = Directory('${dir.path}/music_library');
    await library.create(recursive: true);
    _recordingPath = '${library.path}/recording_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100), path: _recordingPath!);
    _recording = true;
  }

  @override
  Future<void> stopRecording() async {
    if (!_recording) return;
    final path = await _recorder.stop();
    _recording = false;
    if (path == null || !await File(path).exists() || await File(path).length() == 0) throw StateError('Recording did not produce an audio file');
    final item = MusicItem(id: 'take-${DateTime.now().microsecondsSinceEpoch}', title: 'Grabación ${DateTime.now().toLocal().toString().substring(0, 16)}', artist: 'Mi estudio', duration: '—', audioPath: path, isRecording: true);
    _tracks.insert(0, item);
  }

  @override
  Future<void> cancelRecording() async {
    if (_recording) await _recorder.cancel();
    _recording = false;
    final path = _recordingPath;
    _recordingPath = null;
    if (path != null) { final file = File(path); if (await file.exists()) await file.delete(); }
  }

  @override
  Future<List<AudioProject>> loadProjects() async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) return const <AudioProject>[];
    final snapshot = await (_database ?? FirebaseDatabase.instance).ref('audio_projects/${user.uid}').get();
    final value = snapshot.value;
    if (value is! Map) return const <AudioProject>[];
    return value.entries.where((entry) => entry.value is Map).map((entry) => AudioProject.fromSnapshot(entry.key.toString(), user.uid, Map<Object?, Object?>.from(entry.value as Map))).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> saveProject(String title, MusicItem track) async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) throw StateError('Inicia sesión para guardar un proyecto');
    final id = 'project-${DateTime.now().microsecondsSinceEpoch}';
    final project = AudioProject(id: id, title: title.trim().isEmpty ? track.title : title.trim(), ownerUid: user.uid, sourceTrack: track.title, createdAt: DateTime.now().millisecondsSinceEpoch);
    await (_database ?? FirebaseDatabase.instance).ref('audio_projects/${user.uid}/$id').set(project.toJson());
  }

  @override
  Future<void> dispose() async {
    if (_recording) await cancelRecording();
    await _player.stop();
    await _player.dispose();
    await _recorder.dispose();
  }
}
