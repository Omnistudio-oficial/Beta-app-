import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

abstract interface class ChatVideoController {
  bool get isInitialized;
  bool get isPlaying;
  double get aspectRatio;
  String? get error;
  Widget buildVideo();
  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);
  Future<void> dispose();
}

abstract interface class ChatVideoControllerFactory {
  ChatVideoController create(Uri source);
}

class PlatformChatVideoControllerFactory implements ChatVideoControllerFactory {
  const PlatformChatVideoControllerFactory();
  @override
  ChatVideoController create(Uri source) => _PlatformChatVideoController(source);
}

class _PlatformChatVideoController implements ChatVideoController {
  _PlatformChatVideoController(Uri source) : _controller = VideoPlayerController.networkUrl(source);
  final VideoPlayerController _controller;
  @override bool get isInitialized => _controller.value.isInitialized;
  @override bool get isPlaying => _controller.value.isPlaying;
  @override double get aspectRatio => _controller.value.aspectRatio;
  @override String? get error => _controller.value.hasError ? (_controller.value.errorDescription ?? 'No se pudo reproducir el video.') : null;
  @override Widget buildVideo() => VideoPlayer(_controller);
  @override Future<void> initialize() => _controller.initialize();
  @override Future<void> play() => _controller.play();
  @override Future<void> pause() => _controller.pause();
  @override void addListener(VoidCallback listener) => _controller.addListener(listener);
  @override void removeListener(VoidCallback listener) => _controller.removeListener(listener);
  @override Future<void> dispose() => _controller.dispose();
}

/// Network playback is initialized only after the user taps the preview.
/// Playback also starts only from that explicit tap.
class ChatVideoPlayer extends StatefulWidget {
  const ChatVideoPlayer({super.key, required this.source, required this.thumbnailUrl, this.controllerFactory = const PlatformChatVideoControllerFactory()});
  final Uri source;
  final String? thumbnailUrl;
  final ChatVideoControllerFactory controllerFactory;
  @override State<ChatVideoPlayer> createState() => _ChatVideoPlayerState();
}

class _ChatVideoPlayerState extends State<ChatVideoPlayer> {
  ChatVideoController? _controller;
  bool _loading = false;
  String? _error;

  Future<void> _start() async {
    if (_loading) return;
    var controller = _controller;
    if (controller == null || !controller.isInitialized) {
      if (controller != null) {
        controller.removeListener(_onChanged);
        await controller.dispose();
        _controller = null;
      }
      controller = widget.controllerFactory.create(widget.source);
      controller.addListener(_onChanged);
      _controller = controller;
      setState(() { _loading = true; _error = null; });
      try {
        await controller.initialize();
        if (!mounted) return;
        if (controller.error != null) throw StateError(controller.error!);
      } catch (_) {
        if (!mounted) return;
        setState(() { _loading = false; _error = controller!.error ?? 'No se pudo cargar el video.'; });
        return;
      }
    }
    try {
      await controller.play();
      if (mounted) setState(() { _loading = false; _error = controller!.error; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'No se pudo reproducir el video.'; });
    }
  }

  void _onChanged() {
    if (!mounted || _controller == null) return;
    final error = _controller!.error;
    if (error != _error) setState(() => _error = error);
  }

  Future<void> _toggle() async {
    final controller = _controller;
    if (controller == null) return _start();
    try {
      if (controller.isPlaying) { await controller.pause(); } else { await controller.play(); }
      if (mounted) setState(() => _error = controller.error);
    } catch (_) { if (mounted) setState(() => _error = 'No se pudo controlar el video.'); }
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_onChanged);
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return SizedBox(height: 190, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline), const SizedBox(height: 6), Text(_error!, textAlign: TextAlign.center), TextButton(onPressed: _start, child: const Text('Reintentar'))])));
    }
    if (controller?.isInitialized == true) {
      final ratio = controller!.aspectRatio.isFinite && controller.aspectRatio > 0 ? controller.aspectRatio : 16 / 9;
      return ClipRRect(borderRadius: BorderRadius.circular(8), child: Stack(alignment: Alignment.center, children: [AspectRatio(aspectRatio: ratio, child: controller.buildVideo()), IconButton.filledTonal(key: const ValueKey('chat-video-play-pause'), onPressed: _toggle, tooltip: controller.isPlaying ? 'Pausar video' : 'Reproducir video', icon: Icon(controller.isPlaying ? Icons.pause : Icons.play_arrow))]));
    }
    return InkWell(key: const ValueKey('chat-video-preview'), onTap: _loading ? null : _start, child: SizedBox(height: 190, width: 260, child: Stack(fit: StackFit.expand, alignment: Alignment.center, children: [
      if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty)
        Image.network(widget.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12, child: Icon(Icons.video_file_outlined, size: 48)))
      else const ColoredBox(color: Colors.black12, child: Icon(Icons.video_file_outlined, size: 48)),
      Center(child: _loading ? const CircularProgressIndicator() : const Icon(Icons.play_circle_fill, size: 58, color: Colors.white)),
    ])));
  }
}
