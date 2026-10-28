import 'package:flutter/material.dart';

import 'chat_calls.dart';

class ChatCallDialog extends StatefulWidget {
  const ChatCallDialog({super.key, required this.controller, required this.video, required this.peerName, required this.currentUid, this.incoming});
  final ChatCallController controller;
  final bool video;
  final String peerName;
  final String currentUid;
  final ChatCallSignal? incoming;
  @override State<ChatCallDialog> createState() => _ChatCallDialogState();
}

class _ChatCallDialogState extends State<ChatCallDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _reject() async {
    final call = widget.incoming;
    if (call == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.controller.rejectIncoming(call, uid: widget.currentUid);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() { _busy = false; _error = error.toString(); });
    }
  }


  Future<void> _answer() async {
    final call = widget.incoming;
    if (call == null || _busy) return;
    setState(() { _busy = true; _error = null; });
    try { await widget.controller.answerIncoming(call, uid: widget.currentUid); if (mounted) setState(() => _busy = false); }
    catch (error) { if (mounted) setState(() { _busy = false; _error = error.toString(); }); }
  }

  Future<void> _end() async {
    try {
      await widget.controller.endCall();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final call = widget.incoming;
      final incoming = call != null;
      final connected = widget.controller.localStream != null;
      return AlertDialog(
        key: const ValueKey('chat-call-dialog'),
        title: Text(incoming ? '${call.isVideo ? 'Videollamada' : 'Llamada'} de ${call.callerName}' : '${widget.video ? 'Videollamada' : 'Llamada'} con ${widget.peerName}'),
        content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.video && connected) SizedBox(height: 220, child: Stack(fit: StackFit.expand, children: [
            widget.controller.remoteStream != null ? ChatCallVideoView(stream: widget.controller.remoteStream) : const Center(child: Text('Esperando video de la otra persona…')),
            if (widget.controller.localStream != null) Positioned(right: 8, top: 8, width: 88, height: 120, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: ChatCallVideoView(stream: widget.controller.localStream, mirror: true))),
          ])),
          Text(widget.controller.status, textAlign: TextAlign.center),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (incoming && !connected) const Text('Solo puedes responder desde tu cuenta autenticada.'),
        ])),
        actions: [
          if (incoming && !connected) TextButton(key: const ValueKey('chat-call-reject'), onPressed: _busy ? null : _reject, child: const Text('Rechazar')),
          if (incoming && !connected) FilledButton(key: const ValueKey('chat-call-answer'), onPressed: _busy ? null : _answer, child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Responder')),
          if (connected && widget.video) IconButton(key: const ValueKey('chat-call-toggle-camera'), tooltip: widget.controller.isCameraEnabled ? 'Apagar cámara' : 'Encender cámara', onPressed: widget.controller.toggleCamera, icon: Icon(widget.controller.isCameraEnabled ? Icons.videocam : Icons.videocam_off)),
          if (connected) IconButton(key: const ValueKey('chat-call-toggle-mute'), tooltip: widget.controller.isMuted ? 'Activar micrófono' : 'Silenciar', onPressed: widget.controller.toggleMute, icon: Icon(widget.controller.isMuted ? Icons.mic_off : Icons.mic)),
          if (connected && widget.video) IconButton(key: const ValueKey('chat-call-switch-camera'), tooltip: 'Cambiar cámara', onPressed: widget.controller.switchCamera, icon: const Icon(Icons.cameraswitch)),
          if (connected || !incoming) TextButton(onPressed: _end, child: const Text('Finalizar')),
        ],
      );
    },
  );
}
