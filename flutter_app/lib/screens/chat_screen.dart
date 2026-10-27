import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:beta_app/screens/chat_media_actions.dart';
import 'package:beta_app/screens/chat_video_player.dart';
import 'package:beta_app/screens/chat_voice_note.dart';

import 'chat_attachment.dart';
import 'chat_drafts.dart';
import 'chat_repository.dart';
import 'chat_search.dart';

class ChatIdentity {
  const ChatIdentity({required this.uid, required this.email, this.displayName = ''});
  final String uid;
  final String email;
  final String displayName;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.repository, this.identity, this.attachmentPicker, this.mediaActions, this.draftStorage});
  final ChatRepository? repository;
  final ChatIdentity? identity;
  final ChatAttachmentPicker? attachmentPicker;
  final ChatMediaActions? mediaActions;
  final ChatDraftStorage? draftStorage;

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
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  bool _sending = false;
  String? _sendError;
  ChatAttachment? _pendingAttachment;
  VoiceNoteFile? _pendingVoiceNote;
  late final ChatAttachmentPicker _attachmentPicker;
  late final ChatMediaActions _mediaActions;
  late final ChatDraftStorage _draftStorage = widget.draftStorage ?? SharedPreferencesChatDraftStorage();
  late Stream<List<ChatChannel>> _channels;
  Future<void> _draftWrites = Future<void>.value();
  bool _draftReady = false;
  String? _draftError;

  @override
  void initState() {
    super.initState();
    _attachmentPicker = widget.attachmentPicker ?? DeviceChatAttachmentPicker();
    _mediaActions = widget.mediaActions ?? ChatMediaActions();
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
    _searchController.dispose();
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
                    onTap: () => _openChannel(user, channel),
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
      appBar: AppBar(
        title: _searching
            ? TextField(
                key: const ValueKey('chat-search-field'),
                controller: _searchController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Buscar mensajes…',
                  border: InputBorder.none,
                ),
              )
            : Text(channel.name),
        leading: IconButton(
          tooltip: _searching ? 'Cerrar búsqueda' : 'Volver',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() {
            if (_searching) {
              _searching = false;
              _searchController.clear();
            } else {
              _channel = null;
              _messages = null;
              _sendError = null;
              _draftReady = false;
              _draftError = null;
              _controller.clear();
            }
          }),
        ),
        actions: [
          if (_searching && _searchController.text.isNotEmpty)
            IconButton(
              key: const ValueKey('chat-search-clear'),
              tooltip: 'Borrar búsqueda',
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
              icon: const Icon(Icons.clear),
            ),
          if (!_searching)
            IconButton(
              key: const ValueKey('chat-search-open'),
              tooltip: 'Buscar en la conversación',
              onPressed: () => setState(() => _searching = true),
              icon: const Icon(Icons.search),
            ),
        ],
      ),
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
              final query = _searchController.text.trim();
              final visibleMessages = filterChatMessages(messages, query);
              if (visibleMessages.isEmpty) {
                return const Center(
                  key: ValueKey('chat-search-no-matches'),
                  child: Text('No se encontraron mensajes.'),
                );
              }
              return ListView.builder(
                reverse: false,
                padding: const EdgeInsets.all(12),
                itemCount: visibleMessages.length,
                itemBuilder: (context, index) {
                  final message = visibleMessages[index];
                  final mine = message.senderEmail.trim().toLowerCase() == user.email.trim().toLowerCase();
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Card(
                      color: mine ? Theme.of(context).colorScheme.primaryContainer : null,
                      child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (!mine) HighlightedChatText(message.senderName, query: query, style: Theme.of(context).textTheme.labelSmall),
                        HighlightedChatText(message.text, query: query),
                        _MessageTimestamp(timestamp: message.timestamp, messageId: message.id),
                        if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          if (message.mediaType == 'audio')
                            VoiceNotePlayer(url: message.mediaUrl!, caption: message.text)
                          else if (message.mediaType == 'image' || message.mediaType == 'gif')
                            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(message.mediaUrl!, width: 260, height: 190, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Text('No se pudo cargar la imagen.')))
                          else if (message.mediaType == 'video')
                            ChatVideoPlayer(source: Uri.parse(message.mediaUrl!), thumbnailUrl: message.mediaThumbnail)
                          else
                            _DocumentAttachment(
                              message: message,
                              onOpen: () => _openDocument(message),
                            ),
                          Text('Este archivo está en un bucket público: quien tenga el enlace puede acceder.', style: Theme.of(context).textTheme.labelSmall),
                        ],
                        if (message.text.trim().isNotEmpty)
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              key: ValueKey('chat-message-copy-${message.id}'),
                              tooltip: 'Copiar mensaje',
                              onPressed: () => _copyMessage(message.text),
                              icon: const Icon(Icons.copy, size: 18),
                            ),
                          ),
                      ])),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (_sendError != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(_sendError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_draftError != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(_draftError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_pendingVoiceNote case final voice?) Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Row(children: [const Icon(Icons.mic), const SizedBox(width: 8), Expanded(child: Text('${voice.fileName} · ${voice.mimeType}', maxLines: 1, overflow: TextOverflow.ellipsis)), IconButton(tooltip: 'Quitar nota de voz', onPressed: _sending ? null : () => setState(() => _pendingVoiceNote = null), icon: const Icon(Icons.close))])),
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
            IconButton(key: const ValueKey('chat-record-voice-note'), tooltip: 'Grabar nota de voz', onPressed: _sending ? null : _recordVoiceNote, icon: const Icon(Icons.mic)),
            IconButton(key: const ValueKey('chat-attach-media'), tooltip: 'Adjuntar foto, video o documento', onPressed: _sending ? null : _chooseAttachment, icon: const Icon(Icons.attach_file)),
            Expanded(child: TextField(controller: _controller, enabled: _draftReady && !_sending, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onChanged: (text) {
              setState(() {});
              if (_draftReady) _saveDraft(user, channel, text);
            }, onSubmitted: (_) => _send(user, channel), decoration: const InputDecoration(hintText: 'Escribe un mensaje…', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            IconButton.filled(key: const ValueKey('chat-send-text'), onPressed: _sending || (_controller.text.trim().isEmpty && _pendingAttachment == null && _pendingVoiceNote == null) ? null : () => _send(user, channel), tooltip: _pendingVoiceNote != null ? 'Subir y enviar nota de voz' : _pendingAttachment == null ? 'Enviar' : 'Subir y enviar adjunto', icon: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send)),
          ]),
        )),
      ]),
    );
  }

  Future<void> _openChannel(ChatIdentity user, ChatChannel channel) async {
    setState(() {
      _channel = channel;
      _messages = _repository.watchMessages(uid: user.uid, channelId: channel.id);
      _controller.clear();
      _draftReady = false;
      _draftError = null;
      _sendError = null;
    });
    try {
      await _draftWrites.catchError((_) {});
      final draft = await _draftStorage.read(uid: user.uid, channelId: channel.id);
      if (!mounted || _channel?.id != channel.id) return;
      _controller.value = TextEditingValue(text: draft ?? '', selection: TextSelection.collapsed(offset: (draft ?? '').length));
      setState(() => _draftReady = true);
    } catch (error) {
      if (mounted && _channel?.id == channel.id) setState(() {
        _draftReady = true;
        _draftError = 'No se pudo recuperar el borrador local: $error';
      });
    }
  }

  void _saveDraft(ChatIdentity user, ChatChannel channel, String text) {
    final previous = _draftWrites;
    _draftWrites = previous.catchError((_) {}).then((_) async {
      try {
        await _draftStorage.write(uid: user.uid, channelId: channel.id, text: text);
        if (mounted && _channel?.id == channel.id) setState(() => _draftError = null);
      } catch (error) {
        if (mounted && _channel?.id == channel.id) setState(() => _draftError = 'No se pudo guardar el borrador local: $error');
      }
    });
  }

  Future<void> _clearDraft(ChatIdentity user, ChatChannel channel) async {
    await _draftWrites.catchError((_) {});
    await _draftStorage.clear(uid: user.uid, channelId: channel.id);
  }

  Future<void> _copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensaje copiado')),
      );
    }
  }

  Future<void> _openDocument(ChatMessage message) async {
    final url = message.mediaUrl;
    if (url == null || url.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Descargando para abrir las opciones de compartir…')));
    try {
      await _mediaActions.downloadAndShare(
        url: url,
        fileName: message.mediaFileName.isNotEmpty ? message.mediaFileName : 'chat-attachment',
        mimeType: message.mediaMimeType,
      );
    } catch (error) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('No se pudo abrir el archivo: $error')));
    }
  }

  Future<void> _recordVoiceNote() async {
    final note = await showDialog<VoiceNoteFile>(context: context, builder: (_) => const VoiceNoteDialog());
    if (note == null || !mounted) return;
    setState(() { _pendingVoiceNote = note; _pendingAttachment = null; _sendError = null; });
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
    final voiceNote = _pendingVoiceNote;
    if (voiceNote != null) {
      final audioAttachment = ChatAttachment(path: voiceNote.path, name: voiceNote.fileName, mimeType: voiceNote.mimeType, mediaType: 'audio');
      setState(() { _sending = true; _sendError = null; });
      try {
        await _repository.sendAttachment(uid: user.uid, email: user.email, channelId: channel.id, attachment: audioAttachment, caption: _controller.text);
        try { await File(voiceNote.path).delete(); } catch (_) {}
        if (mounted) setState(() { _controller.clear(); _pendingVoiceNote = null; });
        try { await _clearDraft(user, channel); if (mounted) setState(() => _draftError = null); } catch (error) { if (mounted) setState(() => _draftError = 'La nota se envió, pero no se pudo limpiar el borrador local: $error'); }
      } catch (error) { if (mounted) setState(() => _sendError = 'No se pudo enviar la nota de voz: $error'); }
      finally { if (mounted) setState(() => _sending = false); }
      return;
    }
    final attachment = _pendingAttachment;
    if (attachment != null) {
      setState(() { _sending = true; _sendError = null; });
      try {
        await _repository.sendAttachment(uid: user.uid, email: user.email, channelId: channel.id, attachment: attachment, caption: _controller.text);
        if (mounted) setState(() { _controller.clear(); _pendingAttachment = null; });
        try {
          await _clearDraft(user, channel);
          if (mounted) setState(() => _draftError = null);
        } catch (error) {
          if (mounted) setState(() => _draftError = 'El mensaje se envió, pero no se pudo limpiar el borrador local: $error');
        }
      } catch (error) { if (mounted) setState(() => _sendError = 'No se pudo enviar: $error'); }
      finally { if (mounted) setState(() => _sending = false); }
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() { _sending = true; _sendError = null; });
    try {
      await _repository.sendText(uid: user.uid, email: user.email, channelId: channel.id, text: text);
      if (mounted) setState(() => _controller.clear());
      try {
        await _clearDraft(user, channel);
        if (mounted) setState(() => _draftError = null);
      } catch (error) {
        if (mounted) setState(() => _draftError = 'El mensaje se envió, pero no se pudo limpiar el borrador local: $error');
      }
    } catch (error) {
      if (mounted) setState(() => _sendError = 'No se pudo enviar: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

/// Returns an empty label for unset or out-of-range message timestamps.
String? formatChatMessageTimestamp(
  int timestamp, {
  required MaterialLocalizations localizations,
  required bool alwaysUse24HourFormat,
}) {
  if (timestamp <= 0) return null;
  try {
    final localDateTime = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    final date = localizations.formatFullDate(localDateTime);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(localDateTime),
      alwaysUse24HourFormat: alwaysUse24HourFormat,
    );
    return '$date · $time';
  } on ArgumentError {
    return null;
  }
}

class _MessageTimestamp extends StatelessWidget {
  const _MessageTimestamp({required this.timestamp, required this.messageId});

  final int timestamp;
  final String messageId;

  @override
  Widget build(BuildContext context) {
    final formatted = formatChatMessageTimestamp(
      timestamp,
      localizations: MaterialLocalizations.of(context),
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
    );
    if (formatted == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Semantics(
        label: 'Hora del mensaje: $formatted',
        child: Text(
          formatted,
          key: ValueKey('chat-message-time-$messageId'),
          style: Theme.of(context).textTheme.labelSmall,
          textAlign: TextAlign.end,
        ),
      ),
    );
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



class _DocumentAttachment extends StatelessWidget {
  const _DocumentAttachment({required this.message, required this.onOpen});
  final ChatMessage message;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final name = message.mediaFileName.isNotEmpty ? message.mediaFileName : 'Archivo adjunto';
    return OutlinedButton.icon(
      key: ValueKey('chat-open-media-${message.id}'),
      onPressed: onOpen,
      icon: const Icon(Icons.open_in_new),
      label: Text('$name · abrir o compartir'),
    );
  }
}
