import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceNoteFile {
  const VoiceNoteFile({required this.path, required this.mimeType, required this.fileName});
  final String path;
  final String mimeType;
  final String fileName;
}

class VoiceNoteEncoderChoice {
  const VoiceNoteEncoderChoice({required this.encoder, required this.extension, required this.mimeType});
  final AudioEncoder encoder;
  final String extension;
  final String mimeType;
}

VoiceNoteEncoderChoice voiceNoteEncoderChoice({required bool isAndroid, required bool opusSupported}) {
  if (isAndroid && opusSupported) {
    return const VoiceNoteEncoderChoice(encoder: AudioEncoder.opus, extension: 'ogg', mimeType: 'audio/ogg');
  }
  return const VoiceNoteEncoderChoice(encoder: AudioEncoder.aacLc, extension: 'm4a', mimeType: 'audio/mp4');
}

/// Dialog for recording, previewing, discarding, and explicitly sending a note.
/// Press and hold to record; slide left to cancel; swipe up to lock recording.
class VoiceNoteDialog extends StatefulWidget {
  const VoiceNoteDialog({super.key});

  @override
  State<VoiceNoteDialog> createState() => _VoiceNoteDialogState();
}

class _VoiceNoteDialogState extends State<VoiceNoteDialog> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _previewPlayer = AudioPlayer();
  String? _path;
  String? _mimeType;
  bool _recording = false;
  bool _locked = false;
  bool _cancelOnRelease = false;
  bool _previewing = false;
  String? _error;
  double _amplitude = -60;
  DateTime? _startedAt;

  @override
  void dispose() {
    if (_recording) _recorder.cancel();
    _recorder.dispose();
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_recording || _path != null) return;
    try {
      if (!await _recorder.hasPermission()) throw StateError('Permite el acceso al micrófono para grabar.');
      final temp = await getTemporaryDirectory();
      final useOpus = Platform.isAndroid && await _recorder.isEncoderSupported(AudioEncoder.opus);
      final choice = voiceNoteEncoderChoice(isAndroid: Platform.isAndroid, opusSupported: useOpus);
      final file = File('${temp.path}/voice-${DateTime.now().microsecondsSinceEpoch}.${choice.extension}');
      await _recorder.start(RecordConfig(encoder: choice.encoder, sampleRate: 48000, numChannels: 1, bitRate: 64000, echoCancel: true, noiseSuppress: true), path: file.path);
      if (!mounted) { await _recorder.cancel(); return; }
      setState(() { _recording = true; _path = file.path; _mimeType = choice.mimeType; _startedAt = DateTime.now(); _error = null; _locked = false; });
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((value) {
        if (mounted && _recording) setState(() => _amplitude = value.current);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _stop() async {
    if (!_recording) return;
    try {
      final filePath = await _recorder.stop();
      final path = filePath ?? _path;
      if (path == null || !await File(path).exists() || await File(path).length() == 0) throw StateError('No se generó un audio válido.');
      if (mounted) setState(() { _recording = false; _path = path; _previewing = false; });
    } catch (error) {
      if (mounted) setState(() { _recording = false; _error = error.toString(); _path = null; });
    }
  }

  Future<void> _discard() async {
    if (_recording) await _recorder.cancel();
    await _previewPlayer.stop();
    final path = _path;
    if (path != null) { try { await File(path).delete(); } catch (_) {} }
    if (mounted) setState(() { _recording = false; _path = null; _mimeType = null; _previewing = false; _locked = false; _error = null; });
  }

  Future<void> _togglePreview() async {
    final path = _path;
    if (path == null || _recording) return;
    try {
      if (_previewing) {
        await _previewPlayer.pause();
        if (mounted) setState(() => _previewing = false);
      } else {
        await _previewPlayer.play(DeviceFileSource(path));
        if (mounted) setState(() => _previewing = true);
        _previewPlayer.onPlayerComplete.first.then((_) { if (mounted) setState(() => _previewing = false); });
      }
    } catch (error) { if (mounted) setState(() => _error = 'No se pudo reproducir la vista previa: $error'); }
  }

  void _move(Offset delta) {
    if (!_recording || _locked) return;
    if (delta.dx < -80) setState(() => _cancelOnRelease = true);
    if (delta.dy < -80) setState(() => _locked = true);
  }

  Future<void> _release() async {
    if (!_recording || _locked) return;
    if (_cancelOnRelease) { await _discard(); } else { await _stop(); }
    if (mounted) setState(() => _cancelOnRelease = false);
  }

  void _send() {
    final path = _path, mime = _mimeType;
    if (path == null || mime == null || _recording) return;
    final extension = mime == 'audio/ogg' ? 'ogg' : 'm4a';
    Navigator.of(context).pop(VoiceNoteFile(path: path, mimeType: mime, fileName: 'nota-de-voz.$extension'));
  }

  String get _duration {
    final start = _startedAt;
    if (start == null) return '00:00';
    final seconds = (DateTime.now().difference(start).inMilliseconds / 1000).floor();
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('voice-note-dialog'),
    title: const Text('Nota de voz'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_recording) ...[
        Text(_locked ? 'Grabación bloqueada · toca Detener al terminar' : _cancelOnRelease ? 'Suelta para cancelar' : 'Grabando $_duration · desliza arriba para bloquear o a la izquierda para cancelar'),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: ((_amplitude + 60) / 60).clamp(0, 1)),
      ] else if (_path != null) ...[
        Text('Vista previa lista · ${_mimeType == 'audio/ogg' ? 'OGG/Opus' : 'AAC/M4A'}'),
        TextButton.icon(key: const Key('voice-note-preview'), onPressed: _togglePreview, icon: Icon(_previewing ? Icons.pause : Icons.play_arrow), label: Text(_previewing ? 'Pausar' : 'Escuchar')),
      ] else
        const Text('Mantén presionado el micrófono para grabar.'),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ]),
    actions: [
      TextButton(key: const Key('voice-note-close'), onPressed: _recording ? null : () => Navigator.of(context).pop(), child: const Text('Cerrar')),
      if (_recording) ...[
        TextButton(key: const Key('voice-note-cancel'), onPressed: _discard, child: const Text('Cancelar')),
        TextButton(key: const Key('voice-note-stop'), onPressed: _stop, child: const Text('Detener')),
      ] else if (_path != null) ...[
        TextButton(key: const Key('voice-note-discard'), onPressed: _discard, child: const Text('Descartar')),
        FilledButton(key: const Key('voice-note-send'), onPressed: _send, child: const Text('Enviar')),
      ] else
        GestureDetector(
          key: const Key('voice-note-hold'),
          onLongPressStart: (_) => _start(),
          onLongPressMoveUpdate: (details) => _move(details.offsetFromOrigin),
          onLongPressEnd: (_) => _release(),
          child: const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.mic), SizedBox(width: 6), Text('Mantener para grabar')]))
        ),
    ],
  );
}

class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({super.key, required this.url, required this.caption});
  final String url;
  final String caption;
  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;
  @override
  void dispose() { _player.dispose(); super.dispose(); }
  Future<void> _toggle() async {
    try {
      if (_playing) { await _player.pause(); if (mounted) setState(() => _playing = false); }
      else { if (mounted) setState(() => _loading = true); await _player.play(UrlSource(widget.url)); if (mounted) setState(() { _loading = false; _playing = true; }); _player.onPlayerComplete.first.then((_) { if (mounted) setState(() => _playing = false); }); }
    } catch (_) { if (mounted) setState(() { _loading = false; _playing = false; }); }
  }
  @override
  Widget build(BuildContext context) => Row(children: [IconButton(key: const Key('chat-voice-note-play'), onPressed: _toggle, icon: Icon(_loading ? Icons.hourglass_top : _playing ? Icons.pause : Icons.play_arrow)), Expanded(child: Text(_loading ? 'Cargando nota de voz…' : widget.caption, maxLines: 2, overflow: TextOverflow.ellipsis))]);
}
