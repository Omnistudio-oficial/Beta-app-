import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:beta_app/services/google_workspace_read_only.dart';

class AIScreen extends StatefulWidget {
  const AIScreen({super.key});

  @override
  State<AIScreen> createState() => _AIScreenState();
}

class _AIScreenState extends State<AIScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _selectedPrompt;
  String? _readyPrompt;
  final GoogleWorkspaceReadOnlyService _workspace = GoogleWorkspaceReadOnlyService();
  bool _connecting = false;
  String? _workspaceStatus;
  List<Map<String, dynamic>> _workspaceResults = const [];
  final TextEditingController _workspaceQuery = TextEditingController();

  static const _templates = <_PromptTemplate>[
    _PromptTemplate(
      title: 'Resumir un texto',
      icon: Icons.summarize_outlined,
      prompt: 'Resume el siguiente texto en puntos claros y breves:\n\n[Pega aquí el texto]',
    ),
    _PromptTemplate(
      title: 'Crear notas de producto',
      icon: Icons.note_alt_outlined,
      prompt: 'Crea notas de producto claras a partir de esta información:\n\n[Describe el producto y sus características]',
    ),
    _PromptTemplate(
      title: 'Redactar texto de bienvenida',
      icon: Icons.edit_note_outlined,
      prompt: 'Redacta un texto de bienvenida amigable para:\n\n[Describe la aplicación, el público y el tono]',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _workspaceQuery.dispose();
    super.dispose();
  }

  void _selectTemplate(_PromptTemplate template) {
    setState(() {
      _selectedPrompt = template.title;
      _readyPrompt = null;
      _controller.text = template.prompt;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  Future<void> _connectWorkspace() async {
    setState(() { _connecting = true; _workspaceStatus = null; });
    try {
      await _workspace.connect();
      if (!mounted) return;
      setState(() => _workspaceStatus = 'Conectado: ${_workspace.connectedEmail ?? 'cuenta Google'}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _workspaceStatus = 'No se pudo conectar. Revisa el permiso de Google e inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnectWorkspace() async {
    await _workspace.disconnect();
    if (!mounted) return;
    setState(() { _workspaceStatus = 'Desconectado'; _workspaceResults = const []; });
  }

  Future<void> _runWorkspaceQuery(String service) async {
    setState(() { _connecting = true; _workspaceStatus = null; });
    try {
      final query = _workspaceQuery.text.trim();
      final rows = switch (service) {
        'Gmail' => await _workspace.searchEmails(query),
        'Calendar' => await _workspace.upcomingEvents(),
        _ => await _workspace.searchDrive(query),
      };
      if (!mounted) return;
      setState(() { _workspaceResults = rows; _workspaceStatus = '$service: ${rows.length} resultado(s)'; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _workspaceStatus = 'No se pudo consultar $service. Vuelve a conectar y prueba de nuevo.');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _copyPrompt() async {
    final prompt = _readyPrompt;
    if (prompt == null) return;
    await Clipboard.setData(ClipboardData(text: prompt));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prompt copiado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Assistant')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Compositor de prompts', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Elige una plantilla y edítala. Esta pantalla prepara el texto; todavía no genera respuestas con IA.'),
            const SizedBox(height: 18),
            Card(
              key: const Key('google-workspace-card'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Google Workspace', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text('Conexión de solo lectura para Gmail, Calendar y Drive. Sara no enviará, editará ni borrará datos.'),
                  const SizedBox(height: 10),
                  if (!_workspace.isConnected)
                    FilledButton.icon(key: const Key('google-workspace-connect'), onPressed: _connecting ? null : _connectWorkspace, icon: const Icon(Icons.link), label: Text(_connecting ? 'Conectando…' : 'Conectar Google'))
                  else ...[
                    Text(_workspaceStatus ?? 'Conectado: ${_workspace.connectedEmail ?? 'cuenta Google'}'),
                    TextField(key: const Key('workspace-query'), controller: _workspaceQuery, decoration: const InputDecoration(labelText: 'Buscar en Gmail o Drive')),
                    Wrap(spacing: 8, children: [
                      OutlinedButton(key: const Key('workspace-gmail'), onPressed: _connecting ? null : () => _runWorkspaceQuery('Gmail'), child: const Text('Gmail')),
                      OutlinedButton(key: const Key('workspace-calendar'), onPressed: _connecting ? null : () => _runWorkspaceQuery('Calendar'), child: const Text('Calendar')),
                      OutlinedButton(key: const Key('workspace-drive'), onPressed: _connecting ? null : () => _runWorkspaceQuery('Drive'), child: const Text('Drive')),
                      TextButton(key: const Key('google-workspace-disconnect'), onPressed: _connecting ? null : _disconnectWorkspace, child: const Text('Desconectar')),
                    ]),
                  ],
                  if (_workspaceStatus != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_workspaceStatus!)),
                  for (final row in _workspaceResults.take(5))
                    ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text((row['subject'] ?? row['name'] ?? row['summary'] ?? row['snippet'] ?? row['id'] ?? 'Resultado').toString(), maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text((row['from'] ?? row['mimeType'] ?? row['start']?['dateTime'] ?? row['date'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Plantillas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final template in _templates)
              Card(
                child: ListTile(
                  leading: Icon(template.icon, color: Colors.deepPurple),
                  title: Text(template.title),
                  trailing: Icon(_selectedPrompt == template.title ? Icons.check_circle : Icons.arrow_forward_ios),
                  onTap: () => _selectTemplate(template),
                ),
              ),
            if (_selectedPrompt != null) ...[
              const SizedBox(height: 12),
              Text('Editar prompt: $_selectedPrompt', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                key: const Key('prompt-editor'),
                controller: _controller,
                minLines: 4,
                maxLines: 8,
                onChanged: (_) => setState(() => _readyPrompt = null),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('prepare-prompt'),
                  onPressed: _controller.text.trim().isEmpty
                      ? null
                      : () => setState(() => _readyPrompt = _controller.text.trim()),
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('Preparar prompt'),
                ),
              ),
            ],
            if (_readyPrompt != null) ...[
              const SizedBox(height: 18),
              Card(
                key: const Key('prepared-prompt'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Texto listo para usar', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SelectableText(_readyPrompt!),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _copyPrompt,
                          icon: const Icon(Icons.copy),
                          label: const Text('Copiar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PromptTemplate {
  final String title;
  final IconData icon;
  final String prompt;

  const _PromptTemplate({required this.title, required this.icon, required this.prompt});
}
