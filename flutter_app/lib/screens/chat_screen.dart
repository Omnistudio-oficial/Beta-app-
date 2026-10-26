import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'chat_repository.dart';

class ChatIdentity {
  const ChatIdentity({required this.uid, required this.email, this.displayName = ''});
  final String uid;
  final String email;
  final String displayName;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.repository, this.identity});
  final ChatRepository? repository;
  final ChatIdentity? identity;

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
  late Stream<List<ChatChannel>> _channels;

  @override
  void initState() {
    super.initState();
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
                      ])),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (_sendError != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(_sendError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(children: [
            Expanded(child: TextField(controller: _controller, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onChanged: (_) => setState(() {}), onSubmitted: (_) => _send(user, channel), decoration: const InputDecoration(hintText: 'Escribe un mensaje…', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _sending || _controller.text.trim().isEmpty ? null : () => _send(user, channel), tooltip: 'Enviar', icon: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send)),
          ]),
        )),
      ]),
    );
  }

  Future<void> _send(ChatIdentity user, ChatChannel channel) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
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
