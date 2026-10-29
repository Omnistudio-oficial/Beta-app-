import 'dart:convert';

import 'package:beta_app/screens/community_sequencer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders 16 steps per sound lane and loads public pattern titles', (tester) async {
    await tester.pumpWidget(MaterialApp(home: CommunitySequencerScreen(synth: _FakeSynth(), repository: _FakePatternSource())));
    expect(find.text('KICK'), findsOneWidget);
    expect(find.byKey(const Key('step-kick-15')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('load-public-patterns')), 350, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('load-public-patterns')));
    await tester.pumpAndSettle();
    expect(find.text('Public groove'), findsOneWidget);
  });

  test('16-step patterns parse only known instrument lanes and validate BPM', () {
    final pattern = SequencerPattern.fromJson('Test', '{"bpm":128,"lanes":{"kick":[true,false,true],"lead":[false,true],"unknown":[true]}}');
    expect(pattern.bpm, 128);
    expect(pattern.lanes.length, 6);
    expect(pattern.lanes['kick'], hasLength(16));
    expect(pattern.lanes['kick']!.take(3), [true, false, true]);
    expect(pattern.lanes['lead']![1], isTrue);
    expect(pattern.lanes['snare']!.every((step) => !step), isTrue);
    expect(() => SequencerPattern.fromJson('bad', '{"bpm":20,"lanes":{}}'), throwsFormatException);
  });

  test('parses actual published Kotlin project root lanes and tracks list', () {
    final pattern = SequencerPattern.fromJson('Lo-Fi test', jsonEncode({
      'bpm': 120,
      'kick': [true, false, false, false, true],
      'snare': [false, false, true],
      'tracks': [
        {'name': 'Kick Drum', 'soundType': 'kick', 'steps': [false, true]},
        {'name': 'Lead Synth', 'soundType': 'lead', 'steps': [true, false, true]},
        {'name': 'local sample', 'soundType': 'sample:/data/user/0/private.wav', 'steps': [true]},
      ],
    }));
    expect(pattern.bpm, 120);
    expect(pattern.lanes['kick']!.take(2), [false, true]);
    expect(pattern.lanes['lead']!.take(3), [true, false, true]);
    expect(pattern.lanes['hihat']!.every((step) => !step), isTrue);
  });

  test('sequencer step duration uses sixteenth-note timing', () {
    expect(LocalPatternSynth.stepDurationForBpm(120).inMicroseconds, 125000);
    expect(LocalPatternSynth.stepDurationForBpm(60).inMicroseconds, 250000);
  });
}

class _FakePatternSource implements CommunityPatternSource {
  @override
  Future<List<SequencerPattern>> loadPublicPatterns() async => [SequencerPattern(name: 'Public groove', bpm: 100, lanes: const {})];
}

class _FakeSynth extends LocalPatternSynth {
  bool _playing = false;
  @override
  bool get isPlaying => _playing;
  @override
  Future<void> start(SequencerPattern pattern, {void Function(int step)? onStep}) async { _playing = true; onStep?.call(0); }
  @override
  Future<void> stop() async { _playing = false; }
  @override
  Future<void> dispose() async { _playing = false; }
}
