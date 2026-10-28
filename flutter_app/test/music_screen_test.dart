import 'package:beta_app/models/music_item.dart';
import 'package:beta_app/screens/music_screen.dart';
import 'package:beta_app/services/music_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeMusicWorkspace implements MusicWorkspace {
  final List<MusicItem> items = [const MusicItem(id: '1', title: 'My song', artist: 'Artist', duration: '1:00', audioPath: '/fake/song.m4a')];
  Set<String> favorites = {};
  bool recording = false, playing = false;
  int saveCount = 0;
  @override List<MusicItem> get tracks => items;
  @override bool get isRecording => recording;
  @override bool get isPlaying => playing;
  @override Future<Set<String>> loadFavorites() async => favorites;
  @override Future<void> saveFavorites(Set<String> ids) async { favorites = ids; }
  @override Future<void> play(MusicItem track) async { playing = true; }
  @override Future<void> pause() async { playing = false; }
  @override Future<void> importAudio() async { items.add(const MusicItem(id: 'imported', title: 'Imported', artist: 'Importado', duration: '—', audioPath: '/fake/imported.m4a')); }
  @override Future<void> startRecording() async { recording = true; }
  @override Future<void> stopRecording() async { recording = false; items.insert(0, const MusicItem(id: 'take', title: 'Take', artist: 'Mi estudio', duration: '—', audioPath: '/fake/take.m4a', isRecording: true)); }
  @override Future<void> cancelRecording() async { recording = false; }
  @override Future<void> saveProject(String title, MusicItem track) async { saveCount++; }
  @override Future<List<AudioProject>> loadProjects() async => const [];
  @override Future<void> dispose() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('selects a track, plays, and saves a local favorite', (tester) async {
    final workspace = FakeMusicWorkspace();
    await tester.pumpWidget(MaterialApp(home: MusicScreen(workspace: workspace)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('track-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('play-pause'))); await tester.pumpAndSettle();
    expect(workspace.playing, isTrue);
    await tester.tap(find.byKey(const Key('selected-track-favorite'))); await tester.pumpAndSettle();
  });

  testWidgets('filters favorites and restores the full library', (tester) async {
    final workspace = FakeMusicWorkspace();
    await tester.pumpWidget(MaterialApp(home: MusicScreen(workspace: workspace)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorite-1'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('toggle-favorites-filter'))); await tester.pumpAndSettle();
    expect(find.byKey(const Key('track-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('toggle-favorites-filter'))); await tester.pumpAndSettle();
    expect(find.byKey(const Key('track-1')), findsOneWidget);
  });

  testWidgets('records with clear stop and cancel controls, imports and saves project', (tester) async {
    final workspace = FakeMusicWorkspace();
    await tester.pumpWidget(MaterialApp(home: MusicScreen(workspace: workspace)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-audio'))); await tester.pumpAndSettle();
    expect(find.byKey(const Key('track-imported')), findsOneWidget);
    await tester.tap(find.byKey(const Key('start-recording'))); await tester.pumpAndSettle();
    expect(find.byKey(const Key('stop-recording')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-recording'))); await tester.pumpAndSettle();
    expect(workspace.recording, isFalse);
    await tester.tap(find.byKey(const Key('start-recording'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stop-recording'))); await tester.pumpAndSettle();
    expect(find.byKey(const Key('track-take')), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-project'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar').last); await tester.pumpAndSettle();
    expect(workspace.saveCount, 1);
  });
}
