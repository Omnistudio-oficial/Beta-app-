import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat_attachment.dart';
import 'chat_repository.dart';

class ChatIdentity {
  const ChatIdentity({required this.uid, required this.email, this.displayName = ''});
  final String uid;
  final String email;
  final String displayName;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.repository, this.identity, this.attachmentPicker});
  final ChatRepository? repository;
  final ChatIdentity? identity;
  final ChatAttachmentPicker? attachmentPicker;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatRepository _repository = widget.repository ?? FirebaseChatRepository();
  late final ChatIdentity? _user = widget.identity ?? _identityFromAuth();

  ChatIdentity? _identityFromAuth() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return ChatIdentity(uid: user.uid, email: user.email ?? '', displayName: user.displayName ?? '');
  }
  final TextEditingController _controller = TextEditingController();
  ChatChannel? _channel;
  Stream<List<ChatMessage>>? _messages;
  bool _sending = false;
  String? _sendError;
  ChatAttachment? _pendingAttachment;
  late final ChatAttachmentPicker _attachmentPicker;
  late Stream<List<ChatChannel>> _channels;

  @override
  void initState() {
    super.initState();
    _attachmentPicker = widget.attachmentPicker ?? DeviceChatAttachmentPicker();
    final user = _user;
    _channels = user == null || user.email.trim().isEmpty
        ? const Stream<List<ChatChannel>>.empty()
        : _repository.watchChannels(uid: user.uid, email: user.email);
  }

  void _retryChannels() {
    final user = _user;
    if (user == null) return;
    setState(() => _channels = _repository.watchChannels(uid: user.uid, email: user.email));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null || user.email.trim().isEmpty) {
      return Scaffold(appBar: AppBar(title: const Text('Chat')), body: const Center(child: Text('Inicia sesión con una cuenta de correo para ver tus chats.')));
    }
    if (_channel != null) return _buildConversation(user);
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(children: [
        const _AccessNotice(),
        Expanded(
          child: StreamBuilder<List<ChatChannel>>(
            stream: _channels,
            builder: (context, snapshot) {
              if (snapshot.hasError) return _ErrorPanel(message: 'No se pudieron cargar los chats: ${snapshot.error}', onRetry: _retryChannels);
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final channels = snapshot.data ?? const <ChatChannel>[];
              if (channels.isEmpty) return const Center(child: Text('No tienes chats disponibles.'));
              return ListView.builder(
                itemCount: channels.length,
                itemBuilder: (context, index) {
                  final channel = channels[index];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.chat_bubble_outline)),
                    title: Text(channel.name),
                    subtitle: Text(channel.lastMessage.isEmpty ? 'Sin mensajes todavía' : channel.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => setState(() {
                      _channel = channel;
                      _messages = _repository.watchMessages(uid: user.uid, channelId: channel.id);
                    }),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildConversation(ChatIdentity user) {
    final channel = _channel!;
    return Scaffold(
      appBar: AppBar(title: Text(channel.name), leading: BackButton(onPressed: () => setState(() { _channel = null; _messages = null; _sendError = null; }))),
      body: Column(children: [
        const _AccessNotice(),
        const MaterialBanner(content: Text('Los adjuntos usan almacenamiento público: cualquier persona con el enlace puede verlos. No envíes archivos sensibles.'), leading: Icon(Icons.public, color: Colors.deepOrange), actions: [SizedBox.shrink()]),
        Expanded(
          child: StreamBuilder<List<ChatMessage>>(
            stream: _messages,
            builder: (context, snapshot) {
              if (snapshot.hasError) return _ErrorPanel(message: 'No se pudieron cargar los mensajes: ${snapshot.error}', onRetry: () => setState(() => _messages = _repository.watchMessages(uid: user.uid, channelId: channel.id)));
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final messages = snapshot.data ?? const <ChatMessage>[];
              if (messages.isEmpty) return const Center(child: Text('Aún no hay mensajes.'));
              return ListView.builder(
                reverse: false,
                padding: const EdgeInsets.all(12),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  final mine = message.senderEmail.trim().toLowerCase() == user.email.trim().toLowerCase();
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Card(
                      color: mine ? Theme.of(context).colorScheme.primaryContainer : null,
                      child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (!mine) Text(message.senderName, style: Theme.of(context).textTheme.labelSmall),
                        Text(message.text),
                        if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          if (message.mediaType == 'image' || message.mediaType == 'gif')
                            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(message.mediaUrl!, width: 260, height: 190, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Text('No se pudo cargar la imagen.')))
                          else
                            OutlinedButton.icon(
                              key: ValueKey('chat-open-media-${message.id}'),
                              onPressed: () async { await Clipboard.setData(ClipboardData(text: message.mediaUrl!)); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enlace del archivo copiado'))); },
                              icon: const Icon(Icons.content_copy_outlined),
                              label: Text('${message.mediaFileName.isNotEmpty ? message.mediaFileName : (message.mediaType == 'video' ? 'Video' : 'Archivo')} · copiar enlace'),
                            ),
                          Text('Este archivo está en un bucket público: quien tenga el enlace puede acceder.', style: Theme.of(context).textTheme.labelSmall),
                        ],
                      ])),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (_sendError != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(_sendError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_pendingAttachment case final attachment?) Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            if (attachment.isImage)
              ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.file(File(attachment.path), width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)))
            else
              Icon(attachment.mediaType == 'video' ? Icons.video_file_outlined : Icons.insert_drive_file_outlined),
            const SizedBox(width: 8), Expanded(child: Text('${attachment.name} · ${(File(attachment.path).lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MiB', maxLines: 1, overflow: TextOverflow.ellipsis)),
            IconButton(tooltip: 'Quitar adjunto', onPressed: _sending ? null : () => setState(() => _pendingAttachment = null), icon: const Icon(Icons.close)),
          ]),
        ),
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(children: [
            IconButton(key: const ValueKey('chat-attach-media'), tooltip: 'Adjuntar foto, video o documento', onPressed: _sending ? null : _chooseAttachment, icon: const Icon(Icons.attach_file)),
            Expanded(child: TextField(controller: _controller, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onChanged: (_) => setState(() {}), onSubmitted: (_) => _send(user, channel), decoration: const InputDecoration(hintText: 'Escribe un mensaje…', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            IconButton.filled(key: const ValueKey('chat-send-text'), onPressed: _sending || (_controller.text.trim().isEmpty && _pendingAttachment == null) ? null : () => _send(user, channel), tooltip: _pendingAttachment == null ? 'Enviar' : 'Subir y enviar adjunto', icon: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send)),
          ]),
        )),
      ]),
    );
  }

  Future<void> _chooseAttachment() async {
    final kind = await showModalBottomSheet<String>(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(key: const ValueKey('chat-pick-image'), leading: const Icon(Icons.image_outlined), title: const Text('Foto o GIF'), onTap: () => Navigator.pop(context, 'image')),
      ListTile(key: const ValueKey('chat-pick-video'), leading: const Icon(Icons.video_library_outlined), title: const Text('Video'), onTap: () => Navigator.pop(context, 'video')),
      ListTile(key: const ValueKey('chat-pick-document'), leading: const Icon(Icons.attach_file), title: const Text('Archivo o documento'), onTap: () => Navigator.pop(context, 'file')),
    ])));
    if (kind == null || !mounted) return;
    try {
      final picked = switch (kind) { 'image' => await _attachmentPicker.pickImage(), 'video' => await _attachmentPicker.pickVideo(), _ => await _attachmentPicker.pickFile() };
      if (picked != null && mounted) setState(() { _pendingAttachment = picked; _sendError = null; });
    } catch (error) { if (mounted) setState(() => _sendError = error.toString()); }
  }

  Future<void> _send(ChatIdentity user, ChatChannel channel) async {
    if (_sending) return;
    final attachment = _pendingAttachment;
    if (attachment != null) {
      setState(() { _sending = true; _sendError = null; });
      try {
        await _repository.sendAttachment(uid: user.uid, email: user.email, channelId: channel.id, attachment: attachment, caption: _controller.text);
        if (mounted) setState(() { _controller.clear(); _pendingAttachment = null; });
      } catch (error) { if (mounted) setState(() => _sendError = 'No se pudo enviar: $error'); }
      finally { if (mounted) setState(() => _sending = false); }
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() { _sending = true; _sendError = null; });
    try {
      await _repository.sendText(uid: user.uid, email: user.email, channelId: channel.id, text: text);
      if (!mounted) return;
      _controller.clear();
    } catch (error) {
      if (mounted) setState(() => _sendError = 'No se pudo enviar: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _AccessNotice extends StatelessWidget {
  const _AccessNotice();
  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: const Text('Aviso: las reglas actuales de Firebase permiten que cualquier usuario autenticado lea todos los chats. El filtro de membresía en la app no protege los datos en el servidor.'),
    leading: const Icon(Icons.warning_amber_rounded),
    actions: const [SizedBox.shrink()],
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar'))])));
}
