import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

String? extractChatYouTubeId(String text) {
  final input = text.trim();
  if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(input)) return input;
  final patterns = [
    RegExp(r'(?:v=|/v/|youtu\.be/|/embed/|/shorts/)([A-Za-z0-9_-]{11})'),
    RegExp(r'youtube\.com/watch\?.*v=([A-Za-z0-9_-]{11})'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(input);
    if (match != null) return match.group(1);
  }
  return null;
}

String buildChatYouTubeEmbedUrl(String videoId) => 'https://www.youtube.com/embed/$videoId?autoplay=1&playsinline=1&fs=1&rel=0&modestbranding=1&enablejsapi=1';
String buildChatYouTubeVideoUrl(String videoId) => 'https://www.youtube.com/watch?v=$videoId';

class ChatYouTubePlayer extends StatefulWidget {
  const ChatYouTubePlayer({super.key, required this.videoId, required this.title});
  final String videoId, title;
  @override State<ChatYouTubePlayer> createState() => _ChatYouTubePlayerState();
}

class _ChatYouTubePlayerState extends State<ChatYouTubePlayer> {
  YoutubePlayerController? _controller;
  bool _loading = false;
  String? _error;

  Future<void> _start() async {
    if (_loading || _controller != null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final controller = YoutubePlayerController.fromVideoId(
        videoId: widget.videoId,
        autoPlay: true,
        params: const YoutubePlayerParams(showControls: true, showFullscreenButton: true, playsInline: true),
      );
      if (!mounted) { controller.close(); return; }
      setState(() { _controller = controller; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'No se pudo abrir el video de YouTube.'; });
    }
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) return SizedBox(height: 190, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), TextButton(onPressed: () => setState(() => _error = null), child: const Text('Reintentar'))])));
    if (controller != null) return ClipRRect(borderRadius: BorderRadius.circular(8), child: YoutubePlayer(controller: controller, aspectRatio: 16 / 9));
    return InkWell(key: const ValueKey('chat-youtube-preview'), onTap: _loading ? null : _start, child: SizedBox(width: 260, height: 190, child: Stack(fit: StackFit.expand, alignment: Alignment.center, children: [
      Image.network('https://img.youtube.com/vi/${widget.videoId}/hqdefault.jpg', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12, child: Icon(Icons.ondemand_video, size: 48))),
      ColoredBox(color: Colors.black.withOpacity(0.16)),
      Center(child: _loading ? const CircularProgressIndicator() : const Icon(Icons.play_circle_fill, size: 58, color: Colors.white)),
      Positioned(left: 8, right: 8, bottom: 6, child: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 5, color: Colors.black87)]))),
    ])));
  }
}
