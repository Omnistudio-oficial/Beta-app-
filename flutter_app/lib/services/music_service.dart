import 'dart:async';
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
  Stream<Duration> get durationChanges;
  Stream<Duration> get positionChanges;
  Stream<bool> get playingChanges;
  Future<Set<String>> loadFavorites();
  Future<void> saveFavorites(Set<String> ids);
  Future<void> play(MusicItem track);
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
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

  MusicService({
    AudioPlayer? player,
    AudioRecorder? recorder,
    FirebaseAuth? auth,
    FirebaseDatabase? database,
  })  : _player = player ?? AudioPlayer(),
        _recorder = recorder ?? AudioRecorder(),
        _auth = auth,
        _database = database {
    _playerStateSubscription = _player.onPlayerStateChanged.listen((state) {
      _playing = state == PlayerState.playing;
    });
  }

  final AudioPlayer _player;
  final AudioRecorder _recorder;
  final FirebaseAuth? _auth;
  final FirebaseDatabase? _database;
  late final StreamSubscription<PlayerState> _playerStateSubscription;
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
  Stream<Duration> get durationChanges => _player.onDurationChanged;
  @override
  Stream<Duration> get positionChanges => _player.onPositionChanged;
  @override
  Stream<bool> get playingChanges => _player.onPlayerStateChanged.map((state) => state == PlayerState.playing);

  @override
  Future<Set<String>> loadFavorites() async =>
      (await SharedPreferences.getInstance()).getStringList(_favoritesKey)?.toSet() ?? <String>{};

  @override
  Future<void> saveFavorites(Set<String> ids) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_favoritesKey, ids.toList()..sort());
  }

  @override
  Future<void> play(MusicItem track) async {
    final path = track.audioPath;
    if (path == null || !await File(path).exists()) {
      throw StateError('El archivo de audio no está disponible.');
    }
    // Set the truthful state only after the native player accepts the source;
    // the player-state stream subsequently tracks pause/completion events.
    _playing = false;
    await _player.play(DeviceFileSource(path));
    _playing = true;
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _playing = false;
  }

  @override
  Future<void> seek(Duration position) async {
    final clamped = position.isNegative ? Duration.zero : position;
    await _player.seek(clamped);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _playing = false;
  }

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
    _tracks.add(MusicItem(
      id: 'import-${DateTime.now().microsecondsSinceEpoch}',
      title: selected.name,
      artist: 'Importado',
      duration: '—',
      audioPath: saved,
    ));
  }

  @override
  Future<void> startRecording() async {
    if (_recording) throw StateError('Ya hay una grabación en curso.');
    if (!await _recorder.hasPermission()) throw StateError('No se concedió permiso para usar el micrófono.');
    final dir = await getApplicationDocumentsDirectory();
    final library = Directory('${dir.path}/music_library');
    await library.create(recursive: true);
    final path = '${library.path}/recording_${DateTime.now().microsecondsSinceEpoch}.m4a';
    _recordingPath = path;
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
        path: path,
      );
      _recording = true;
    } catch (_) {
      _recordingPath = null;
      final file = File(path);
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  @override
  Future<void> stopRecording() async {
    if (!_recording) return;
    final expectedPath = _recordingPath;
    String? path;
    try {
      path = await _recorder.stop();
    } finally {
      _recording = false;
      _recordingPath = null;
    }
    final output = path ?? expectedPath;
    if (output == null || !await File(output).exists() || await File(output).length() == 0) {
      if (output != null) {
        final emptyFile = File(output);
        if (await emptyFile.exists()) await emptyFile.delete();
      }
      throw StateError('La grabación no produjo un archivo de audio válido.');
    }
    _tracks.insert(0, MusicItem(
      id: 'take-${DateTime.now().microsecondsSinceEpoch}',
      title: 'Grabación ${DateTime.now().toLocal().toString().substring(0, 16)}',
      artist: 'Mi estudio',
      duration: '—',
      audioPath: output,
      isRecording: true,
    ));
  }

  @override
  Future<void> cancelRecording() async {
    final path = _recordingPath;
    try {
      if (_recording) await _recorder.cancel();
    } finally {
      _recording = false;
      _recordingPath = null;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  @override
  Future<List<AudioProject>> loadProjects() async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) return const <AudioProject>[];
    final snapshot = await (_database ?? FirebaseDatabase.instance).ref('audio_projects/${user.uid}').get();
    final value = snapshot.value;
    if (value is! Map) return const <AudioProject>[];
    return value.entries
        .where((entry) => entry.value is Map)
        .map((entry) => AudioProject.fromSnapshot(
              entry.key.toString(),
              user.uid,
              Map<Object?, Object?>.from(entry.value as Map),
            ))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> saveProject(String title, MusicItem track) async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) throw StateError('Inicia sesión para guardar un proyecto');
    final id = 'project-${DateTime.now().microsecondsSinceEpoch}';
    final project = AudioProject(
      id: id,
      title: title.trim().isEmpty ? track.title : title.trim(),
      ownerUid: user.uid,
      sourceTrack: track.title,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    // Persist project metadata only; raw audio is intentionally not uploaded.
    await (_database ?? FirebaseDatabase.instance).ref('audio_projects/${user.uid}/$id').set(project.toJson());
  }

  @override
  Future<void> dispose() async {
    if (_recording || _recordingPath != null) await cancelRecording();
    await _player.stop();
    _playing = false;
    await _playerStateSubscription.cancel();
    await _player.dispose();
    await _recorder.dispose();
  }
}
