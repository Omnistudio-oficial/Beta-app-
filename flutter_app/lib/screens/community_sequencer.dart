import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

const sequencerSoundTypes = <String>['kick', 'snare', 'hihat', 'clap', 'bass', 'lead'];

class SequencerPattern {
  SequencerPattern({required this.name, required this.bpm, required Map<String, List<bool>> lanes})
      : lanes = Map.unmodifiable({for (final type in sequencerSoundTypes) type: List<bool>.unmodifiable(lanes[type] ?? List<bool>.filled(16, false))});

  final String name;
  final int bpm;
  final Map<String, List<bool>> lanes;

  factory SequencerPattern.blank() => SequencerPattern(name: 'Mi patrón', bpm: 120, lanes: const {});

  factory SequencerPattern.fromJson(String name, String encoded, {int? fallbackBpm}) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) throw const FormatException('El patrón publicado no tiene un formato válido.');
    final rawBpm = decoded['bpm'] ?? fallbackBpm;
    final bpm = rawBpm is num ? rawBpm.round() : 120;
    if (bpm < 40 || bpm > 240) throw const FormatException('El tempo publicado debe estar entre 40 y 240 BPM.');
    final rawLanes = decoded['lanes'] ?? decoded['tracks'];
    final lanes = <String, List<bool>>{};
    // Current Kotlin sequencer JSON stores named boolean arrays at the root,
    // and also a `tracks` list of {soundType, steps} records. Accept both.
    for (final type in sequencerSoundTypes) {
      final raw = decoded[type] ?? (rawLanes is Map ? rawLanes[type] : null);
      if (raw is List) lanes[type] = _steps(raw);
    }
    if (rawLanes is List) {
      for (final item in rawLanes) {
        if (item is! Map) continue;
        final type = item['soundType']?.toString().toLowerCase();
        final steps = item['steps'];
        if (type != null && sequencerSoundTypes.contains(type) && steps is List) {
          lanes[type] = _steps(steps);
        }
      }
    }
    if (lanes.isEmpty) throw const FormatException('El patrón publicado no contiene pistas compatibles.');
    return SequencerPattern(name: name, bpm: bpm, lanes: lanes);
  }


  static List<bool> _steps(List<dynamic> raw) =>
      List<bool>.generate(16, (index) => index < raw.length && raw[index] == true);

  String toJson() => jsonEncode({'bpm': bpm, 'lanes': lanes});
}

abstract interface class CommunityPatternSource {
  Future<List<SequencerPattern>> loadPublicPatterns();
}

class CommunityPatternRepository implements CommunityPatternSource {
  CommunityPatternRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  @override
  Future<List<SequencerPattern>> loadPublicPatterns() async {
    final snapshot = await _firestore.collection('cloud_audio_projects').where('isPublic', isEqualTo: true).get();
    final patterns = <SequencerPattern>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final json = data['patternDataJson'];
      if (json is! String) continue;
      try {
        final bpm = data['bpm'];
        patterns.add(SequencerPattern.fromJson(
          data['title']?.toString() ?? 'Patrón comunitario',
          json,
          fallbackBpm: bpm is num ? bpm.round() : null,
        ));
      } on FormatException {
        // Skip legacy/community documents that do not use the supported 16-step format.
      }
    }
    return patterns;
  }
}

/// Generates every note locally with SoLoud oscillators; no audio is downloaded or streamed.
class LocalPatternSynth {
  LocalPatternSynth({SoLoud? engine}) : _engine = engine ?? SoLoud.instance;
  final SoLoud _engine;
  final Map<String, AudioSource> _sources = {};
  final Set<SoundHandle> _handles = {};
  Timer? _timer;
  Stopwatch? _clock;
  Duration _scheduled = Duration.zero;
  bool _ready = false;
  bool _playing = false;
  int _step = 0;
  int _bpm = 120;

  bool get isPlaying => _playing;
  int get currentStep => _step;
  static Duration stepDurationForBpm(int bpm) => Duration(microseconds: (60000000 / bpm / 4).round());

  Future<void> initialize() async {
    if (_ready) return;
    if (!_engine.isInitialized) await _engine.init();
    final waveforms = <String, WaveForm>{
      'kick': WaveForm.sin,
      'snare': WaveForm.triangle,
      'hihat': WaveForm.fSquare,
      'clap': WaveForm.square,
      'bass': WaveForm.saw,
      'lead': WaveForm.sin,
    };
    try {
      for (final entry in waveforms.entries) {
        _sources[entry.key] = await _engine.loadWaveform(entry.value, false, 0, 0);
      }
      _ready = true;
    } catch (_) {
      for (final source in _sources.values) {
        await _engine.disposeSource(source);
      }
      _sources.clear();
      rethrow;
    }
  }

  Future<void> start(SequencerPattern pattern, {void Function(int step)? onStep}) async {
    await initialize();
    await stop();
    _bpm = pattern.bpm;
    _clock = Stopwatch()..start();
    _scheduled = Duration.zero;
    _step = 0;
    _playing = true;
    final interval = stepDurationForBpm(_bpm);
    _timer = Timer.periodic(interval, (_) {
      if (!_playing) return;
      _step = (_step + 1) % 16;
      onStep?.call(_step);
      _fireStep(pattern, _step);
    });
    onStep?.call(0);
    _fireStep(pattern, 0);
  }

  void _fireStep(SequencerPattern pattern, int step) {
    final clock = _clock;
    if (clock == null) return;
    final due = clock.elapsed + const Duration(milliseconds: 120);
    if (_scheduled < due) _scheduled = due;
    for (final type in sequencerSoundTypes) {
      if (pattern.lanes[type]?[step] != true) continue;
      final source = _sources[type];
      if (source == null) continue;
      final handle = _engine.playClocked(source, _scheduled, volume: type == 'hihat' ? .18 : .38);
      _handles.add(handle);
      final speed = switch (type) {
        'kick' => 0.28,
        'snare' => 1.4,
        'hihat' => 8.0,
        'clap' => 2.2,
        'bass' => 0.55,
        _ => 1.8,
      };
      _engine.setRelativePlaySpeed(handle, speed);
      final voiceLength = type == 'hihat' ? const Duration(milliseconds: 55) : const Duration(milliseconds: 150);
      _engine.scheduleStop(handle, voiceLength);
      Timer(voiceLength + const Duration(milliseconds: 350), () => _handles.remove(handle));
    }
    _scheduled += stepDurationForBpm(_bpm);
  }

  Future<void> stop() async {
    _playing = false;
    _timer?.cancel();
    _timer = null;
    _clock?.stop();
    _clock = null;
    for (final handle in _handles.toList()) {
      try { await _engine.stop(handle); } catch (_) { /* voices may have ended already */ }
    }
    _handles.clear();
  }

  Future<void> dispose() async {
    await stop();
    for (final source in _sources.values) {
      await _engine.disposeSource(source);
    }
    _sources.clear();
    _ready = false;
  }
}

class CommunitySequencerScreen extends StatefulWidget {
  const CommunitySequencerScreen({super.key, this.synth, this.repository});
  final LocalPatternSynth? synth;
  final CommunityPatternSource? repository;
  @override
  State<CommunitySequencerScreen> createState() => _CommunitySequencerScreenState();
}

class _CommunitySequencerScreenState extends State<CommunitySequencerScreen> {
  late final LocalPatternSynth _synth = widget.synth ?? LocalPatternSynth();
  late final CommunityPatternSource _repository = widget.repository ?? CommunityPatternRepository();
  SequencerPattern _pattern = SequencerPattern.blank();
  List<SequencerPattern> _community = const [];
  int _activeStep = -1;
  bool _loadingCommunity = false;
  bool _busy = false;

  @override
  void dispose() {
    unawaited(_synth.dispose());
    super.dispose();
  }

  void _toggleStep(String type, int index) {
    final lanes = {for (final entry in _pattern.lanes.entries) entry.key: entry.value.toList()};
    lanes[type]![index] = !lanes[type]![index];
    setState(() => _pattern = SequencerPattern(name: _pattern.name, bpm: _pattern.bpm, lanes: lanes));
  }

  Future<void> _togglePlayback() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_synth.isPlaying) {
        await _synth.stop();
        if (mounted) setState(() => _activeStep = -1);
      } else {
        await _synth.start(_pattern, onStep: (step) { if (mounted) setState(() => _activeStep = step); });
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo iniciar el audio local: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadCommunity() async {
    setState(() => _loadingCommunity = true);
    try {
      final patterns = await _repository.loadPublicPatterns();
      if (mounted) setState(() => _community = patterns);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudieron cargar los patrones públicos: $error')));
    } finally {
      if (mounted) setState(() => _loadingCommunity = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Secuenciador comunitario')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Crea patrones de 16 pasos. El audio se sintetiza localmente en este dispositivo.', style: TextStyle(fontSize: 15)),
      const SizedBox(height: 12),
      Row(children: [const Text('Tempo'), Expanded(child: Slider(key: const Key('sequencer-bpm'), min: 40, max: 240, divisions: 200, value: _pattern.bpm.toDouble(), label: '${_pattern.bpm} BPM', onChanged: (value) => setState(() => _pattern = SequencerPattern(name: _pattern.name, bpm: value.round(), lanes: _pattern.lanes)))), Text('${_pattern.bpm} BPM')]),
      FilledButton.icon(key: const Key('sequencer-play'), onPressed: _busy ? null : _togglePlayback, icon: Icon(_synth.isPlaying ? Icons.stop : Icons.play_arrow), label: Text(_synth.isPlaying ? 'Detener' : 'Reproducir patrón')),
      const SizedBox(height: 12),
      for (final type in sequencerSoundTypes) _lane(type),
      const Divider(height: 32),
      Row(children: [const Expanded(child: Text('Patrones públicos de la comunidad', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), IconButton(key: const Key('load-public-patterns'), onPressed: _loadingCommunity ? null : _loadCommunity, icon: _loadingCommunity ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh), tooltip: 'Cargar patrones públicos')]),
      const Text('Solo se consultan patrones publicados como públicos. No se envía audio ni se escribe en la nube.'),
      for (var i = 0; i < _community.length; i++) ListTile(key: Key('community-pattern-$i'), leading: const Icon(Icons.public), title: Text(_community[i].name), subtitle: Text('${_community[i].bpm} BPM · reproducido con sintetizador local'), onTap: () { setState(() { _pattern = _community[i]; _activeStep = -1; }); }),
    ])),
  );

  Widget _lane(String type) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(type.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w600)),
    Wrap(spacing: 2, runSpacing: 2, children: List.generate(16, (index) => SizedBox(width: 38, height: 38, child: IconButton(key: Key('step-$type-$index'), padding: EdgeInsets.zero, onPressed: () => _toggleStep(type, index), icon: Container(decoration: BoxDecoration(color: _pattern.lanes[type]![index] ? Colors.deepPurple : (_activeStep == index ? Colors.amber : Colors.black12), borderRadius: BorderRadius.circular(7)), alignment: Alignment.center, child: Text('${index + 1}', style: const TextStyle(fontSize: 11, color: Colors.black87))))))),
  ]));
}
