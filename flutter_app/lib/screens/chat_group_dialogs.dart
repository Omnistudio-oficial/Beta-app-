import 'package:flutter/material.dart';

import 'chat_repository.dart';

class CreateChatGroupDialog extends StatefulWidget {
  const CreateChatGroupDialog({super.key, required this.onCreate});
  final Future<void> Function(String name, String description, List<String> memberEmails) onCreate;

  @override
  State<CreateChatGroupDialog> createState() => _CreateChatGroupDialogState();
}

class _CreateChatGroupDialogState extends State<CreateChatGroupDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _members = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() { _name.dispose(); _description.dispose(); _members.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) { setState(() => _error = 'Escribe un nombre para el grupo.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final emails = _members.text.split(RegExp(r'[,;\n]')).map((value) => value.trim()).where((value) => value.isNotEmpty).toSet().toList();
      await widget.onCreate(_name.text, _description.text, emails);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() { _busy = false; _error = 'No se pudo crear el grupo: $error'; });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('create-chat-group-dialog'),
    title: const Text('Crear grupo'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(key: const ValueKey('create-group-name'), controller: _name, decoration: const InputDecoration(labelText: 'Nombre del grupo')),
      TextField(key: const ValueKey('create-group-description'), controller: _description, decoration: const InputDecoration(labelText: 'Descripción (opcional)')),
      TextField(key: const ValueKey('create-group-members'), controller: _members, minLines: 1, maxLines: 4, decoration: const InputDecoration(labelText: 'Correos de integrantes', helperText: 'Separados por coma o salto de línea')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ])),
    actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(key: const ValueKey('create-group-submit'), onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Crear'))],
  );
}

class ManageChatGroupDialog extends StatefulWidget {
  const ManageChatGroupDialog({super.key, required this.channel, required this.uid, required this.email, required this.repository, required this.onLeave});
  final ChatChannel channel;
  final String uid, email;
  final ChatRepository repository;
  final Future<void> Function() onLeave;

  @override
  State<ManageChatGroupDialog> createState() => _ManageChatGroupDialogState();
}

class _ManageChatGroupDialogState extends State<ManageChatGroupDialog> {
  late final _name = TextEditingController(text: widget.channel.name);
  late List<ChatMember> _members = List.of(widget.channel.members);
  late final _description = TextEditingController(text: widget.channel.description);
  final _newMember = TextEditingController();
  bool _busy = false;
  String? _error;
  bool get _owner => widget.channel.creatorUid == widget.uid || widget.channel.creatorEmail.trim().toLowerCase() == widget.email.trim().toLowerCase();

  @override
  void dispose() { _name.dispose(); _description.dispose(); _newMember.dispose(); super.dispose(); }

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _error = null; });
    try { await action(); if (mounted) setState(() => _busy = false); }
    catch (error) { if (mounted) setState(() { _busy = false; _error = error.toString(); }); }
  }

  Future<void> _leave() async {
    final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('¿Salir de este grupo?'),
      content: const Text('Dejarás de pertenecer a este grupo y ya no aparecerá entre tus chats.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(key: const ValueKey('confirm-leave-group'), onPressed: () => Navigator.pop(context, true), child: const Text('Salir'))],
    ));
    if (accepted != true || !mounted) return;
    await _run(() async { await widget.onLeave(); if (mounted) Navigator.pop(context, true); });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('manage-chat-group-dialog'),
    title: Text('Administrar ${widget.channel.name}'),
    content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_owner) ...[
        TextField(key: const ValueKey('manage-group-name'), controller: _name, decoration: const InputDecoration(labelText: 'Nombre')),
        TextField(key: const ValueKey('manage-group-description'), controller: _description, decoration: const InputDecoration(labelText: 'Descripción')),
        Align(alignment: Alignment.centerRight, child: TextButton(key: const ValueKey('save-group-info'), onPressed: _busy ? null : () => _run(() => widget.repository.updateGroupInfo(uid: widget.uid, channelId: widget.channel.id, name: _name.text, description: _description.text)), child: const Text('Guardar cambios'))),
        const Divider(),
        TextField(key: const ValueKey('add-group-member-email'), controller: _newMember, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: 'Correo de integrante', suffixIcon: IconButton(key: const ValueKey('add-group-member'), tooltip: 'Agregar integrante', onPressed: _busy ? null : () { final email = _newMember.text.trim(); if (email.isEmpty) return; _run(() async { await widget.repository.addGroupMember(uid: widget.uid, channelId: widget.channel.id, memberEmail: email); setState(() => _members.add(ChatMember(email: email, name: email.split('@').first))); _newMember.clear(); }); }, icon: const Icon(Icons.person_add_alt_1)))),
      ],
      const SizedBox(height: 8), Text('Integrantes (${_members.length})', style: Theme.of(context).textTheme.titleSmall),
      for (final member in _members) Card(child: Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(member.name.isEmpty ? member.email : member.name)), if (_owner && member.email.toLowerCase() != widget.channel.creatorEmail.toLowerCase()) IconButton(key: ValueKey('remove-group-member-${member.email}'), tooltip: 'Quitar integrante', onPressed: _busy ? null : () => _run(() async { await widget.repository.removeGroupMember(uid: widget.uid, channelId: widget.channel.id, memberEmail: member.email); setState(() => _members.removeWhere((value) => value.email.toLowerCase() == member.email.toLowerCase())); }), icon: const Icon(Icons.person_remove_alt_1))]),
        if (_owner && member.email.toLowerCase() != widget.channel.creatorEmail.toLowerCase()) ...[
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, key: ValueKey('permission-messages-${member.email}'), title: const Text('Puede enviar mensajes'), value: member.canSendMessages, onChanged: _busy ? null : (value) => _run(() async { await widget.repository.updateGroupMemberPermissions(uid: widget.uid, channelId: widget.channel.id, memberEmail: member.email, canSendMessages: value, canSendMedia: member.canSendMedia); setState(() { final index = _members.indexWhere((value) => value.email == member.email); if (index >= 0) _members[index] = ChatMember(email: member.email, name: member.name, uid: member.uid, role: member.role, canSendMessages: value, canSendMedia: member.canSendMedia, canInviteMembers: member.canInviteMembers, avatarUrl: member.avatarUrl); }); })),
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, key: ValueKey('permission-media-${member.email}'), title: const Text('Puede enviar archivos'), value: member.canSendMedia, onChanged: _busy ? null : (value) => _run(() async { await widget.repository.updateGroupMemberPermissions(uid: widget.uid, channelId: widget.channel.id, memberEmail: member.email, canSendMessages: member.canSendMessages, canSendMedia: value); setState(() { final index = _members.indexWhere((value) => value.email == member.email); if (index >= 0) _members[index] = ChatMember(email: member.email, name: member.name, uid: member.uid, role: member.role, canSendMessages: member.canSendMessages, canSendMedia: value, canInviteMembers: member.canInviteMembers, avatarUrl: member.avatarUrl); }); })),
        ],
      ]))),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ]))),
    actions: [if (!_owner) TextButton(key: const ValueKey('leave-group'), onPressed: _busy ? null : _leave, child: const Text('Salir del grupo')), TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cerrar'))],
  );
}
