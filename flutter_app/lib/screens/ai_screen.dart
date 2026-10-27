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
  final TextEditingController _saraChatInput = TextEditingController();
  final List<Map<String, String>> _saraGeneralChat = [];
  bool _useWorkspaceContext = false;
  final ScrollController _saraChatScroll = ScrollController();

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
    _saraChatInput.dispose();
    _saraChatScroll.dispose();
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

  Future<void> _sendSaraMessage() async {
    final text = _saraChatInput.text.trim();
    if (text.isEmpty || _connecting) return;
    if (_useWorkspaceContext && !_workspace.isConnected) {
      setState(() => _saraGeneralChat.add({'role': 'assistant', 'text': 'Conecta Google Workspace primero para hacer preguntas sobre tus datos. Puedes conversar normalmente con Sara desactivando el contexto de Google.'}));
      return;
    }
    setState(() {
      _saraGeneralChat.add({'role': 'user', 'text': text});
      _saraChatInput.clear();
      _connecting = true;
    });
    try {
      final answer = _useWorkspaceContext
          ? await _workspace.askSara(text)
          : await _workspace.chatWithSara(text);
      if (!mounted) return;
      setState(() => _saraGeneralChat.add({'role': 'assistant', 'text': answer}));
    } catch (error) {
      if (!mounted) return;
      final message = error.toString();
      final friendly = message.contains('Inicia sesión')
          ? 'Inicia sesión en OmniStudio y vuelve a preguntar.'
          : 'No pude conectar con Sara. Revisa tu conexión e inténtalo de nuevo.';
      setState(() => _saraGeneralChat.add({'role': 'assistant', 'text': friendly}));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
    if (mounted && _saraChatScroll.hasClients) {
      await _saraChatScroll.animateTo(_saraChatScroll.position.maxScrollExtent, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
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
            const Text('Elige una plantilla para preparar un prompt o pregunta a Sara en lenguaje natural sobre Google Workspace.'),
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
            Card(
              key: const Key('sara-chat'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Conversar con Sara', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SizedBox(height: 230, child: ListView(controller: _saraChatScroll, children: [
                    if (_saraGeneralChat.isEmpty)
                      const Text('Conversa con Sara sobre cualquier tema. Si activas el contexto de Google, podrá interpretar preguntas y consultar tus datos autorizados en modo de solo lectura.'),
                    for (final entry in _saraGeneralChat)
                      Align(alignment: entry['role'] == 'user' ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.all(10), constraints: const BoxConstraints(maxWidth: 440), decoration: BoxDecoration(color: entry['role'] == 'user' ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)), child: SelectableText(entry['text'] ?? ''))),
                  ])),
                  const SizedBox(height: 4),
                  SwitchListTile(key: const Key('sara-workspace-context'), contentPadding: EdgeInsets.zero, title: const Text('Usar contexto de Google Workspace'), subtitle: const Text('Solo lectura · requiere conectar Google'), value: _useWorkspaceContext, onChanged: _connecting ? null : (value) => setState(() => _useWorkspaceContext = value)),
                  const SizedBox(height: 8),
                  Row(children: [Expanded(child: TextField(key: const Key('sara-workspace-chat-input'), controller: _saraChatInput, minLines: 1, maxLines: 3, onSubmitted: (_) => _sendSaraMessage(), decoration: const InputDecoration(hintText: 'Escribe un mensaje para Sara', border: OutlineInputBorder()))), const SizedBox(width: 8), IconButton.filled(key: const Key('sara-workspace-chat-send'), onPressed: _connecting ? null : _sendSaraMessage, tooltip: 'Preguntar a Sara', icon: _connecting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send))]),
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
