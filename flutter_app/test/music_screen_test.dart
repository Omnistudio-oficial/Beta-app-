import 'dart:async';

import 'package:beta_app/models/music_item.dart';
import 'package:beta_app/screens/music_screen.dart';
import 'package:beta_app/services/music_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeMusicWorkspace implements MusicWorkspace {
  final List<MusicItem> items = [const MusicItem(id: '1', title: 'My song', artist: 'Artist', duration: '1:00', audioPath: '/fake/song.m4a')];
  final StreamController<Duration> durations = StreamController<Duration>.broadcast();
  final StreamController<Duration> positions = StreamController<Duration>.broadcast();
  final StreamController<bool> playingStates = StreamController<bool>.broadcast();
  Set<String> favorites = {};
  bool recording = false, playing = false;
  int saveCount = 0;
  Duration? lastSeek;
  int stopCount = 0;
  @override List<MusicItem> get tracks => items;
  @override bool get isRecording => recording;
  @override bool get isPlaying => playing;
  @override Stream<Duration> get durationChanges => durations.stream;
  @override Stream<Duration> get positionChanges => positions.stream;
  @override Stream<bool> get playingChanges => playingStates.stream;
  @override Future<Set<String>> loadFavorites() async => favorites;
  @override Future<void> saveFavorites(Set<String> ids) async { favorites = ids; }
  @override Future<void> play(MusicItem track) async { playing = true; playingStates.add(true); }
  @override Future<void> pause() async { playing = false; playingStates.add(false); }
  @override Future<void> seek(Duration position) async { lastSeek = position; positions.add(position); }
  @override Future<void> stop() async { playing = false; stopCount++; playingStates.add(false); positions.add(Duration.zero); }
  @override Future<void> importAudio() async { items.add(const MusicItem(id: 'imported', title: 'Imported', artist: 'Importado', duration: '—', audioPath: '/fake/imported.m4a')); }
  @override Future<void> startRecording() async { recording = true; }
  @override Future<void> stopRecording() async { recording = false; items.insert(0, const MusicItem(id: 'take', title: 'Take', artist: 'Mi estudio', duration: '—', audioPath: '/fake/take.m4a', isRecording: true)); }
  @override Future<void> cancelRecording() async { recording = false; }
  @override Future<void> saveProject(String title, MusicItem track) async { saveCount++; }
  @override Future<List<AudioProject>> loadProjects() async => const [];
  @override Future<void> dispose() async {
    await durations.close(); await positions.close(); await playingStates.close();
  }
}

Future<void> flushMusicEvents(WidgetTester tester) async {
  // Broadcast streams deliver asynchronously; flush their microtasks before
  // asserting the frame produced by the corresponding subscription.
  await tester.idle();
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows actual player duration and position, seeks, pauses and stops', (tester) async {
    final workspace = FakeMusicWorkspace();
    await tester.pumpWidget(MaterialApp(home: MusicScreen(workspace: workspace)));
    await tester.pumpAndSettle();
    workspace.durations.add(const Duration(seconds: 75));
    workspace.positions.add(const Duration(seconds: 12));
    await flushMusicEvents(tester);
    expect(find.text('00:12'), findsOneWidget);
    expect(find.text('01:15'), findsOneWidget);
    expect(tester.widget<Slider>(find.byKey(const Key('playback-seek'))).onChanged, isNotNull);

    await tester.tap(find.byKey(const Key('play-pause')));
    await tester.pumpAndSettle();
    expect(workspace.playing, isTrue);
    expect(find.byTooltip('Pausar'), findsOneWidget);

    final slider = tester.widget<Slider>(find.byKey(const Key('playback-seek')));
    slider.onChangeEnd!(const Duration(seconds: 35).inMilliseconds.toDouble());
    await tester.pumpAndSettle();
    expect(workspace.lastSeek, const Duration(seconds: 35));

    await tester.tap(find.byKey(const Key('play-pause')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Reproducir'), findsOneWidget);
    await tester.tap(find.byKey(const Key('stop-playback')));
    await tester.pumpAndSettle();
    expect(workspace.stopCount, 1);
    expect(find.text('00:00'), findsOneWidget);
  });

  testWidgets('reflects playback completion instead of leaving stale playing state', (tester) async {
    final workspace = FakeMusicWorkspace();
    await tester.pumpWidget(MaterialApp(home: MusicScreen(workspace: workspace)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play-pause')));
    await tester.pumpAndSettle();
    workspace.durations.add(const Duration(seconds: 20));
    workspace.positions.add(const Duration(seconds: 20));
    workspace.playingStates.add(false);
    await flushMusicEvents(tester);
    expect(find.byTooltip('Reproducir'), findsOneWidget);
    expect(find.text('00:20', skipOffstage: false), findsNWidgets(2));
    expect(tester.widget<Text>(find.byKey(const Key('playback-position'))).data, '00:20');
    expect(tester.widget<Text>(find.byKey(const Key('playback-duration'))).data, '00:20');
  });

  testWidgets('shows a live recording clock and resets it on cancel or save', (tester) async {
    final workspace = FakeMusicWorkspace();
    await tester.pumpWidget(MaterialApp(home: MusicScreen(workspace: workspace)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start-recording')));
    await tester.pump();
    expect(find.text('Grabando 00:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Grabando 00:02'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-recording')));
    await tester.pumpAndSettle();
    expect(workspace.recording, isFalse);
    expect(find.byKey(const Key('recording-status')), findsNothing);

    await tester.tap(find.byKey(const Key('start-recording')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Grabando 00:01'), findsOneWidget);
    await tester.tap(find.byKey(const Key('stop-recording')));
    await tester.pumpAndSettle();
    expect(workspace.recording, isFalse);
    expect(find.byKey(const Key('track-take')), findsOneWidget);
    expect(find.byKey(const Key('recording-status')), findsNothing);
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

  testWidgets('imports, records with stop/cancel, and saves project metadata', (tester) async {
    final workspace = FakeMusicWorkspace();
    await tester.pumpWidget(MaterialApp(home: MusicScreen(workspace: workspace)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-audio'))); await tester.pumpAndSettle();
    expect(find.byKey(const Key('track-imported')), findsOneWidget);
    await tester.tap(find.byKey(const Key('start-recording'))); await tester.pump();
    expect(find.byKey(const Key('stop-recording')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-recording'))); await tester.pumpAndSettle();
    expect(workspace.recording, isFalse);
    await tester.tap(find.byKey(const Key('start-recording'))); await tester.pump();
    await tester.tap(find.byKey(const Key('stop-recording'))); await tester.pumpAndSettle();
    expect(find.byKey(const Key('track-take')), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-project'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar').last); await tester.pumpAndSettle();
    expect(workspace.saveCount, 1);
  });
}
