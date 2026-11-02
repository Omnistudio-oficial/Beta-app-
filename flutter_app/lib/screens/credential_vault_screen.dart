import 'package:flutter/material.dart';

import 'package:beta_app/services/credential_vault_service.dart';

class CredentialVaultScreen extends StatefulWidget {
  const CredentialVaultScreen({super.key, CredentialVaultService? service})
      : _service = service;

  final CredentialVaultService? _service;

  @override
  State<CredentialVaultScreen> createState() => _CredentialVaultScreenState();
}

class _CredentialVaultScreenState extends State<CredentialVaultScreen> {
  late final CredentialVaultService _service;
  final _label = TextEditingController();
  final _website = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  List<Map<String, dynamic>> _credentials = [];
  bool _loading = true;
  bool _saving = false;
  String? _editingId;
  bool _draft = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget._service ?? CredentialVaultService();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await _service.list();
      if (mounted) setState(() => _credentials = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _resetForm() {
    _editingId = null;
    _label.clear();
    _website.clear();
    _username.clear();
    _password.clear();
    _draft = false;
  }

  void _edit(Map<String, dynamic> item) {
    setState(() {
      _editingId = item['id']?.toString();
      _label.text = item['label']?.toString() ?? '';
      _website.text = item['origin']?.toString() ?? '';
      _username.clear();
      _password.clear();
      _draft = item['status'] == 'draft';
    });
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final id = _editingId;
      final args = {
        'label': _label.text.trim(),
        'websiteUrl': _website.text.trim(),
        'username': _username.text,
        'password': _password.text,
        'draft': _draft,
      };
      if (id == null) {
        await _service.save(
          label: args['label']! as String,
          websiteUrl: args['websiteUrl']! as String,
          username: (args['username']! as String).isEmpty ? null : args['username']! as String,
          password: (args['password']! as String).isEmpty ? null : args['password']! as String,
          draft: _draft,
        );
      } else {
        await _service.update(
          id: id,
          label: args['label']! as String,
          websiteUrl: args['websiteUrl']! as String,
          username: (args['username']! as String).isEmpty ? null : args['username']! as String,
          password: (args['password']! as String).isEmpty ? null : args['password']! as String,
          draft: _draft,
        );
      }
      if (mounted) {
        setState(_resetForm);
        FocusScope.of(context).unfocus();
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _service.delete(id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _website.dispose();
    _username.dispose();
    _password.dispose();
    if (widget._service == null) _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis credenciales')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_editingId == null ? 'Agregar credencial' : 'Editar credencial',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(controller: _label, decoration: const InputDecoration(labelText: 'Nombre (ej. Correo)')),
          TextField(controller: _website, keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Sitio web HTTPS')),
          TextField(controller: _username, decoration: const InputDecoration(labelText: 'Usuario (vuelve a escribirlo al editar)')),
          TextField(controller: _password, obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña (vuelve a escribirla al editar)')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Guardar como borrador'),
            value: _draft,
            onChanged: (value) => setState(() => _draft = value),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Guardando…' : (_editingId == null ? 'Guardar' : 'Actualizar')),
          ),
          if (_editingId != null)
            TextButton(onPressed: () => setState(_resetForm), child: const Text('Cancelar edición')),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          const Divider(height: 32),
          Text('Guardadas', style: Theme.of(context).textTheme.titleLarge),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading && _credentials.isEmpty) const Text('Todavía no hay credenciales.'),
          for (final item in _credentials)
            Card(
              child: ListTile(
                title: Text(item['label']?.toString() ?? 'Sin nombre'),
                subtitle: Text('${item['origin'] ?? ''} · ${item['status'] ?? ''}'),
                trailing: Wrap(
                  children: [
                    IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit),
                        onPressed: () => _edit(item)),
                    IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(item['id'].toString())),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
